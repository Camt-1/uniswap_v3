// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Pool.sol';

import './NoDelegateCall.sol';

import '../contracts/libraries/LowGasSafeMath.sol';
import '../contracts/libraries/SafeCast.sol';
import '../contracts/libraries/Tick.sol';
import '../contracts/libraries/TickBitmap.sol';
import '../contracts/libraries/Position.sol';
import '../contracts/libraries/Oracle.sol';

import '../contracts/libraries/FullMath.sol';
import '../contracts/libraries/FixedPoint128.sol';
import '../contracts/libraries/TransferHelper.sol';
import '../contracts/libraries/TickMath.sol';
import '../contracts/libraries/LiquidityMath.sol';
import '../contracts/libraries/SqrtPriceMath.sol';
import '../contracts/libraries/SwapMath.sol';

import './interfaces/IUniswapV3PoolDeployer.sol';
import './interfaces/IUniswapV3Factory.sol';
import './interfaces/IERC20Minimal.sol';
import './interfaces/callback/IUniswapV3MintCallback.sol';
import './interfaces/callback/IUniswapV3SwapCallback.sol';
import './interfaces/callback/IUniswapV3FlashCallback.sol';

contract demo is IUniswapV3Pool, NoDelegateCall {
     using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Oracle for Oracle.Observation[65535];

    // 工厂合约地址
    address public immutable override factory;
    // 代币0地址
    address public immutable override token0;
    // 代币1地址
    address public immutable override token1;
    // 交易手续费
    uint24 public immutable override fee;
    // 价格刻度间隔
    int24 public immutable override tickSpacing;
    // 每个tick最大流动性
    uint128 public immutable override maxLiquidityPerTick;

    // 槽0结构体, 存储池子的核心状态
    struct Slot0 {
        uint160 sqrtPriceX96; // 当前价格(Q64.96格式的平方根价格)
        int24 tick; // 当前tick
        uint16 observationIndex; // 最近移除更新的观测索引
        uint16 observationCardinality; // 当前观测数组容量
        uint16 observationCardinalityNext; // 下一个观测数组容量
        uint8 feeProtocol; // 协议手续费比例
        bool unlocked; // 池子是否解锁(重入保护)
    }

    // 槽0变量
    Slot0 public override slot0;
    // token0全局手续费增长
    uint256 public override feeGrowthGlobal0X128;
    // tokne1全局手续费增长
    uint256 public override feeGrowthGlobal1X128;

    // 协议累计手续费结构体
    struct ProtocolFees {
        uint128 token0;
        uint128 token1;
    }
    // 协议累计手续费变量
    ProtocolFees public override protocolFees;

    //当前池子流动性
    uint128 public override liquidity;

    // tick信息映射
    mapping(int24 => Tick.Info) public override ticks;
    // tick位图
    mapping(int16 => uint256) public override tickBitmap;
    // 头寸信息映射
    mapping(bytes32 => Position.Info) public override positions;
    // 观测数组
    Oracle.Observation[65535] public override observations;

    // 互斥锁修饰符, 防止重入攻击, 并确保池子已经初始化
    modifier lock() {
        require(slot0.unlocked, 'LOK');
        // 上锁
        slot0.unlocked = false;
        _;
        //解锁
        slot0.unlocked = true;
    }

    // 仅允许工厂合约owner调用的修饰符
    modifier onlyFactoryOwner() {
        require(msg.sender == IUniswapV3Factory(factory).owner());
        _;
    }

    constructor() {
    }

    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) =
            token0.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    function snpashotcumulativesInside(int24 tickLower, int24 tickUpper)
        external
        view
        override
        noDelegateCall
        returns (
            int56 tickCumulativeInside,
            uint160 secondsPerLiquidityInsideX128,
            uint32 secondsInside
        )
    {
        checkTicks(tickLower, tickUpper);

        int56 tickCumulativeLower;
        int56 tickCumulativeUpper;
        uint160 secondsPerLiquidityOutsideLowerX128;
        uint160 secondsPerLiquidityOutsideUpperX128;
        uint32 secondsOutsideLower;
        uint32 secondsOutsideUpper;

        {
            Tick.Info storage lower = ticks[tickLower];
            Tick.Info storage upper = ticks[tickUpper];

            bool initializedLower;
            (
                tickCumulativeLower,
                secondsPerLiquidityOutsideLowerX128,
                secondsOutsideLower,
                initializedLower
            ) = (
                lower.tickCumulativeOutside,
                lower.secondsPerLiquidityOutsideX128,
                lower.secondsOutside,
                lower.initialized
            );

            bool initializedUpper;
            (
                tickCumulativeUpper,
                secondsPerLiquidityOutsideUpperX128,
                secondsOutsideLower,
                initializedLower
            ) = (
                upper.tickCumulativeOutside,
                upper.secondsPerLiquidityOutsideX128,
                upper.secondsOutside,
                upper.initialized
            );
        }

        Slot0 memory _slot0 = slot0;

        if (_slot0.tick < tickLower) {
            return (
                tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityOutsideLowerX128 - secondsPerLiquidityOutsideUpperX128,
                secondsOutsideLower - secondsOutsideUpper
            );
        } else if (_slot0.tick < tickUpper) {
            uint32 time = _blockTimestamp();
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = 
                observations.observeSingle(
                    time,
                    0,
                    _slot0.tick,
                    _slot0.observationIndex,
                    liquidity,
                    _slot0.observationCardinality
                );
            return (
                tickCumulative - tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityCumulativeX128 -
                    secondsPerLiquidityOutideLowerX128 -
                    secondsPerLiquidityOutideUpperX128,
                time - secondsOutsideLower - secondsOutsideUpper
            );
        } else {
            return (
                tickCumulativeUpper - tickCumulativeLower,
                secondsPerLiquidityOutsideUpperX128 - secondsPerLiquidityOutsideLowerX128,
                secondsOutsideUpper - secondsOutsideLower
            );
        }
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        override
        onDelegateCall
        returns (int56[] memory tickCumulative, uint160[] memory secondsPerLiquidityCumulativeX128)
    {
        return
            observations.observe(
                _blockTimestamp(),
                secondsAgos,
                slot0.tick,
                slot0.observationIndex,
                liquidity,
                slot0.observationCardinality
            );
    }

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext)
        external
        override
        lock
        noDelegateCall
    {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext;
        uint16 observationCardinalityNextNew =
            observations.grow(observationCardianlityNextOld, observationCardinalityNext);
        slot0.obserevationCardinalityNxt = observationCardinalityNextNew;
        if (observationCardinalityNext != observationCardinalityNextNew)
            emit IncreaseObservationCardianlityNext(observationCardinalityNextOld, observationCardinalityNextNew);
    }

    function initialize(uint160 sqrtPriceX96) external override {
        require(slot0.sqrtPriceX96 == 0, 'AI');

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(_blockTimestamp());

        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardianlity: cardianlity,
            observationCardianlityNext: cardianlityNext,
            feeProtocol: 0,
            unlocked: true
        });

        emit Initialize(sqrtPriceX96, tick);
    }

    struct ModifyPosttionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
    }

    function _modifyPosition(ModifyPosttionParams memory params)
        private
        noDelegateCall
        returns (
            Position.Info storage position,
            int256 amount0,
            int256 amount1
        )
    {
        checkTicks(params.tickLower, params.tickUpper);

        Slot0 memory _slot0 = slot0;

        position = _updatePosition(
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.liquidityDelta,
            _slot0.tick
        );

        if (params.liquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtratioAtTick(params.tickLower),
                    TickMath.getSqrtratioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (_slot0.tick < params.tickUpper) {
                uint128 liqudityBefore = liquidity;

            }
        }
    }
}