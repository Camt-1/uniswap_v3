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

contract UniswapV3Pool is IUniswapV3Pool, NoDelegateCall {
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
        int24 _tickSpacing;
        // 从部署者获取参数
        (factory, token0, token1, fee, _tickSpacing) = IUniswapV3PoolDeployer(msg.sender).parameters();
        tickSpacing = _tickSpacing;
        // 计算每个tick最大流动性
        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    // 检测tick输入是否合法
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        require(tickLower < tickUpper, 'LTU'); // 下届必须小于上界
        require(tickLower >= TickMath.MIN_TICK, 'LTM'); // 下届不能小于最小tick
        require(tickUpper <= TickMath.MAX_TICK, 'TUM'); // 上界不能大于最大tick
    }

    // 获取当前区块时间戳(32位)
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // 截断为32位
    }

    // 获取池子token0余额
    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) = 
            token0.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }
    
    // 获取池子token1余额
    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) =
            token1.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    // 获取指定tick范围内的累计数据快照
    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
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
        // 检查tick范围是否合法
        checkTicks(tickLower, tickUpper);

        int56 tickCumulativeLower;
        int56 tickCumulativeUpper;
        uint160 secondsPerLiquidityOutsideLowerX128;
        uint160 secondsPerLiquidityOutsideUpperX128;
        uint32 secondsOutsideLower;
        uint32 secondsOutsideUpper;

        {
            // 获取tickLower和tickUpper的相关信息
            Tick.Info storage lower = ticks[tickLower];
            Tick.Info storage upper = ticks[tickUpper];
            bool initializedLower;
            (tickCumulativeLower, secondsPerLiquidityOutsideLowerX128, secondsOutsideLower, initializedLower) = (
                lower.tickCumulativeOutside,
                lower.secondsPerLiquidityOutsideX128,
                lower.secondsOutside,
                lower.initialized
            );
            require(initializedLower); // 确保tickLower已初始化

            bool initializedUpper;
            (tickCumulativeUpper, secondsPerLiquidityOutsideUpperX128, secondsOutsideUpper, initializedUpper) = (
                upper.tickCumulativeOutside,
                upper.secondsPerLiquidityOutsideX128,
                upper.secondsOutside,
                upper.initialized
            );
        }

        Slot0 memory _slot0 = slot0;

        // 根据当前tick位置计算累计数据
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
                    secondsPerLiquidityOutsideLowerX128 -
                    secondsPerLiquidityOutsideUpperX128,
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

    // 获取指定时间间隔的累计tick和流动性数据
    function observe(uint32[] calldata secondsAgos)
        external
        view
        override
        noDelegateCall
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128)
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

    // 增加观测数组的容量
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext)
        external
        override
        lock
        noDelegateCall
    {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext;
        uint16 observationCardinalityNextNew =
            observations.grow(observationCardinalityNextOld, observationCardinalityNext);
        slot0.observationCardinalityNext = observationCardinalityNextNew;
        if (observationCardinalityNextOld != observationCardinalityNextNew)
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
    }

    // 初始化池子
    function initialize(uint160 sqrtPriceX96) external override {
        require(slot0.sqrtPriceX96 == 0, 'AI'); // 确保池子未初始化

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(_blockTimestamp());

        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex:0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: 0,
            unlocked: true
        });

        emit Initialize(sqrtPriceX96, tick);
    }

    // 修改头寸参数结构体
    struct ModifyPositionParams {
        address owner; // 头寸所有者
        int24 tickLower; // 下界tick
        int24 tickUpper; // 上界tick
        int128 liquidityDelta; // 流动性变化量
    }

    // 修改头寸的内部函数
    function _modifyPosition(ModifyPositionParams memory params)
        private
        noDelegateCall
        returns (
            Position.Info storage position,
            int256 amount0,
            int256 amount1
        )
    {
        // 检查tick范围是否合法
        checkTicks(params.tickLower, params.tickUpper);

        Slot0 memory _slot0 = slot0;

        // 更新头寸信息
        position = _updatePosition(
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.liquidityDelta,
            _slot0.tick
        );
        
        if (params.liquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                // 计算token0的变化量
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (_slot0.tick < params.tickUpper) {
                uint128 liquidityBefore = liquidity;
            
                // 写入观测数据
                (slot0.observationIndex, slot0.observationCardinality) = observations.write(
                    _slot0.observationIndex,
                    _blockTimestamp(),
                    _slot0.tick,
                    liquidityBefore,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );

                // 计算token0和token1的变化量
                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    _slot0.sqrtPriceX96,
                    params.liquidityDelta
                );

                liquidity = LiquidityMath.addDelta(liquidityBefore, params.liquidityDelta);
            } else {
                // 当前价格高于上界时,只需要计算token1的变化量
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower), // 下界价格
                    TickMath.getSqrtRatioAtTick(params.tickUpper), // 上界价格
                    params.liquidityDelta // 流动性变化量
                );
            }
        }
    }

    // 更新头寸信息的内部函数
    function _updatePosition(
        address owner, // 头寸所有者地址
        int24 tickLower, // 下界tick
        int24 tickUpper, // 上界tick
        int128 liquidityDelta, // 流动性变化量
        int24 tick // 当前tick
    ) private returns (Position.Info storage position) {
        // 获取头寸信息
        position = positions.get(owner, tickLower, tickUpper);

        // 获取全局手续费增长变量
        uint256 _feeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        uint256 _feeGrowthGlobal1X128 = feeGrowthGlobal1X128;

        bool flippedLower; // 下界tick是否翻转
        bool flippedUpper; // 上界tick是否翻转

        if (liquidityDelta != 0) {
            // 获取当前区块时间戳
            uint32 time = _blockTimestamp();

            // 获取当前tick的累计数据
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) =
                observations.observeSingle(
                    time,
                    0,
                    slot0.tick,
                    slot0.observationIndex,
                    liquidity,
                    slot0.observationCardinality
                );

            // 更新下界tick的信息
            flippedLower = ticks.update(
                tickLower,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                false, // 下界tick
                maxLiquidityPerTick
            );

            // 更新上界tick的信息
            flippedUpper = ticks.update(
                tickUpper,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                true, // 上界tick
                maxLiquidityPerTick
            );

            // 如果下界tick翻转，则更新tick位图
            if (flippedLower) {
                tickBitmap.flipTick(tickLower, tickSpacing);
            }

            // 如果上界tick翻转，则更新tick位图
            if (flippedUpper) {
                tickBitmap.flipTick(tickUpper, tickSpacing);
            }
        }

        // 获取两个tick之间的手续费增长值
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = 
            ticks.getFeeGrowthInside(tickLower, tickUpper, tick, _feeGrowthGlobal0X128, _feeGrowthGlobal1X128);
        
        // 更新头寸信息,包括流动性和手续费
        position.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

        // 如果是移除流动性
        if (liquidityDelta < 0) {
            // 如果下界tick翻转,则清除该tick
            if (flippedLower) {
                ticks.clear(tickLower);
            }
            // 如果上界tick翻转,则清除该tick
            if (flippedUpper) {
                ticks.clear(tickUpper);
            }
        }
    }

    // 添加流动性
    // @param recipient 接收者地址
    // @param tickLower 下界tick
    // @param tickUpper 上界tick
    // @param amount 添加的流动性数量
    // @param data 回调数据
    // @return amount0 需要支付的token0数量
    // @return amount1 需要支付的token1数量
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        // 检查流动性数量必须大于0
        require(amount > 0);
        // 调用_modifyPosition修改头寸
        (, int256 amount0Int, int256 amount1Int) =
            _modifyPosition(
                ModifyPositionParams({
                    owner: recipient,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: int256(amount).toInt128()
                })
            );
        
        // 转换为无符号整数
        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        // 记录转账前的余额
        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        // 调用回调函数,让调用者转入token
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
        // 检查转账后的余额是否足够
        if (amount0 > 0) require(balance0Before.add(amount0) <= balance0(), 'M0');
        if (amount1 > 0) require(balance1Before.add(amount1) <= balance1(), 'M1');

        // 触发Mint事件
        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
    }

    // 收集手续费
    // @param recipient 接收者地址
    // @param tickLower 下界tick
    // @param tickUpper 上界tick
    // @param amount0Requested 请求收集的token0数量
    // @param amount1Requested 请求收集的token1数量
    // @return amount0 实际收集的token0数量
    // @return amount1 实际收集的token1数量
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override lock returns (uint128 amount0, uint128 amount1) {
        // 获取头寸信息
        Position.Info storage position = positions.get(msg.sender, tickLower, tickUpper);

        // 计算实际可收集的数量
        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        // 转账token0
        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        // 转账token1
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        // 触发Collect事件
        emit Collect(msg.sender, recipient, tickLower, tickUpper, amount0, amount1);
    }

    // 销毁流动性
    // @param tickLower 下界tick
    // @param tickUpper 上界tick
    // @param amount 销毁的流动性数量
    // @return amount0 获得的token0数量
    // @return amount1 获得的token1数量
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        // 调用_modifyPosition修改头寸
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) =
            _modifyPosition(
                ModifyPositionParams({
                    owner: msg.sender,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(amount).toInt128()
                })
            );
        
        // 转换为无符号整数
        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        // 更新待收集的token数量
        if (amount > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0),
                position.tokensOwed1 + uint128(amount1)
            );
        }

        // 触发Burn事件
        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    // 交换缓存结构体
    struct SwapCache {
        uint8 feeProtocol;           // 协议费率
        uint128 liquidityStart;      // 初始流动性
        uint32 blockTimestamp;       // 区块时间戳
        int56 tickCumulative;        // tick累计值
        uint160 secondsPerLiquidityCumulativeX128;  // 每单位流动性的秒数累计值
        bool computedLatestObservation;  // 是否已计算最新观察值
    }

    // 交换状态结构体
    struct SwapState {
        int256 amountSpecifiedRemaining;  // 剩余指定数量
        int256 amountCalculated;          // 计算得到的数量
        uint160 sqrtPriceX96;            // 当前价格
        int24 tick;                      // 当前tick
        uint256 feeGrowthGlobalX128;     // 全局手续费增长值
        uint128 protocolFee;             // 协议费用
        uint128 liquidity;               // 当前流动性
    }

    // 单步计算结构体
    struct StepComputations {
        uint160 sqrtPriceStartX96;      // 起始价格
        int24 tickNext;                 // 下一个tick
        bool initialized;               // 是否已初始化
        uint160 sqrtPriceNextX96;      // 下一个价格
        uint256 amountIn;              // 输入数量
        uint256 amountOut;             // 输出数量
        uint256 feeAmount;             // 手续费数量
    }

    // 交换函数
    // @param recipient 接收者地址
    // @param zeroForOne 是否用token0换token1
    // @param amountSpecified 指定的交换数量
    // @param sqrtPriceLimitX96 价格限制
    // @param data 回调数据
    // @return amount0 token0的变化量
    // @return amount1 token1的变化量
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override noDelegateCall returns (int256 amount0, int256 amount1) {
        // 检查交换数量不能为0
        require(amountSpecified != 0, 'AS');

        // 获取当前slot0状态
        Slot0 memory slot0Start = slot0;

        // 检查池子是否已解锁
        require(slot0Start.unlocked, 'LOK');
        // 检查价格限制是否合法
        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MAX_SQRT_RATIO,
            'SPL'
        );

        // 锁定池子
        slot0.unlocked = false;

        // 初始化交换缓存
        SwapCache memory cache =
            SwapCache({
                liquidityStart: liquidity,
                blockTimestamp: _blockTimestamp(),
                feeProtocol: zeroForOne ? (slot0Start.feeProtocol % 16) : (slot0Start.feeProtocol >> 4),
                secondsPerLiquidityCumulativeX128: 0,
                tickCumulative: 0,
                computedLatestObservation: false
            });

        // 判断是否为精确输入
        bool exactInput = amountSpecified > 0;

        // 初始化交换状态
        SwapState memory state =
            SwapState({
                amountSpecifiedRemaining: amountSpecified,
                amountCalculated: 0,
                sqrtPriceX96: slot0Start.sqrtPriceX96,
                tick: slot0Start.tick,
                feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
                protocolFee: 0,
                liquidity: cache.liquidityStart
            });

        // 循环执行交换步骤直到达到目标数量或价格限制
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepComputations memory step;

            // 记录当前价格
            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            // 获取下一个初始化的tick
            (step.tickNext, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                tickSpacing,
                zeroForOne
            );

            // 确保tick在合法范围内
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // 计算这一步的交换结果
            (step.sqrtPriceNextX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                fee
            );

            // 更新剩余数量和计算得到的数量
            if (exactInput) {
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated.sub(step.amountOut.toInt256());
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add((step.amountIn + step.feeAmount).toInt256());
            }

            // 如果有协议费用,则计算协议费用
            if (cache.feeProtocol > 0) {
                uint256 delta = step.feeAmount / cache.feeProtocol;
                step.feeAmount -= delta;
                state.protocolFee += uint128(delta);
            }

            // 如果有流动性,则更新手续费增长值
            if (state.liquidity > 0)
                state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);

            // 如果达到下一个tick
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // 如果tick已初始化
                if (step.initialized) {
                    // 如果还未计算最新观察值,则计算
                    if (!cache.computedLatestObservation) {
                        (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                            cache.blockTimestamp,
                            0,
                            slot0Start.tick,
                            slot0Start.observationIndex,
                            cache.liquidityStart,
                            slot0Start.observationCardinality
                        );
                        cache.computedLatestObservation = true;
                    }
                    // 穿越tick,更新流动性
                    int128 liquidityNet = 
                        ticks.cross(
                            step.tickNext,
                            (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
                            (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128),
                            cache.secondsPerLiquidityCumulativeX128,
                            cache.tickCumulative,
                            cache.blockTimestamp
                        );
                    
                    // 如果是反向交易,则取相反数
                    if (zeroForOne) liquidityNet = -liquidityNet;

                    // 更新流动性
                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }
                // 更新当前tick
                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // 如果价格变化但未达到下一个tick,则计算当前tick
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        // 如果tick发生变化,则更新观察值
        if (state.tick != slot0Start.tick) {
            (uint16 observationIndex, uint16 observationCardinality) =
                observations.write(
                    slot0Start.observationIndex,
                    cache.blockTimestamp,
                    slot0Start.tick,
                    cache.liquidityStart,
                    slot0Start.observationCardinality,
                    slot0Start.observationCardinalityNext
                );
            // 更新slot0
            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) = (
                state.sqrtPriceX96,
                state.tick,
                observationIndex,
                observationCardinality
            );
        } else {
            // 如果tick未变,只更新价格
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        // 如果流动性发生变化,则更新流动性
        if (cache.liquidityStart != state.liquidity) liquidity = state.liquidity;

        // 更新手续费相关状态
        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token0 += state.protocolFee;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token1 += state.protocolFee;
        }

        // 计算最终的token变化量
        (amount0, amount1) = zeroForOne == exactInput
            ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);

        // 处理token转账
        if (zeroForOne) {
            if (amount1 < 0) TransferHelper.safeTransfer(token1, recipient, uint256(-amount1));

            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            require(balance0Before.add(uint256(amount0)) <= balance0(), 'IIA');
        } else {
            if (amount0 < 0) TransferHelper.safeTransfer(token0, recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            require(balance1Before.add(uint256(amount1)) <= balance1(), 'IIA');
        }

        // 触发Swap事件并解锁池子
        emit Swap(msg.sender, recipient, amount0, amount1, state.sqrtPriceX96, state.liquidity, state.tick);
        slot0.unlocked = true;
    }

    // 闪电贷函数
    // @param recipient 接收者地址
    // @param amount0 借出的token0数量
    // @param amount1 借出的token1数量
    // @param data 回调数据
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override lock noDelegateCall {
        // 检查池子是否有流动性
        uint128 _liquidity = liquidity;
        require(_liquidity > 0, 'L');

        // 计算手续费
        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, fee, 1e6);
        // 记录转账前的余额
        uint256 balance0Before = balance0();
        uint256 balance1Before = balance1();

        // 转出token
        if (amount0 > 0) TransferHelper.safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(token1, recipient, amount1);

        // 调用回调函数
        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(fee0, fee1, data);

        // 获取转账后的余额
        uint256 balance0After = balance0();
        uint256 balance1After = balance1();

        // 检查是否归还了足够的token
        require(balance0Before.add(fee0) <= balance0After, 'F0');
        require(balance1Before.add(fee1) <= balance1After, 'F1');

        // 计算实际支付的手续费
        uint256 paid0 = balance0After - balance0Before;
        uint256 paid1 = balance1After - balance1Before;

        // 处理token0的手续费
        if (paid0 > 0) {
            uint8 feeProtocol0 = slot0.feeProtocol % 16;
            uint256 fees0 = feeProtocol0 == 0 ? 0 : paid0 / feeProtocol0;
            if (uint128(fees0) > 0) protocolFees.token0 += uint128(fees0);
            feeGrowthGlobal0X128 += FullMath.mulDiv(paid0 - fees0, FixedPoint128.Q128, _liquidity);
        }
        // 处理token1的手续费
        if (paid1 > 0) {
            uint8 feeProtocol1 = slot0.feeProtocol >> 4;
            uint256 fees1 = feeProtocol1 == 0 ? 0 : paid1 / feeProtocol1;
            if (uint128(fees1) > 0) protocolFees.token1 += uint128(fees1);
            feeGrowthGlobal1X128 += FullMath.mulDiv(paid1 - fees1, FixedPoint128.Q128, _liquidity);
        }
        
        // 触发Flash事件
        emit Flash(msg.sender, recipient, amount0, amount1, paid0, paid1);
    }

    // 设置协议费率
    // @param feeProtocol0 token0的协议费率
    // @param feeProtocol1 token1的协议费率
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override lock onlyFactoryOwner {
        // 检查费率是否合法:必须为0或者在4-10之间
        require(
            (feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10)) &&
                (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10))
        );
        // 保存旧的费率
        uint8 feeProtocolOld = slot0.feeProtocol;
        // 设置新的费率,token1的费率左移4位
        slot0.feeProtocol = feeProtocol0 + (feeProtocol1 << 4);
        // 触发事件
        emit SetFeeProtocol(feeProtocolOld % 16, feeProtocolOld >> 4, feeProtocol0, feeProtocol1);
    }

    // 收取协议费用
    // @param recipient 接收者地址
    // @param amount0Requested token0请求提取的数量
    // @param amount1Requested token1请求提取的数量
    // @return amount0 实际提取的token0数量
    // @return amount1 实际提取的token1数量
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override lock onlyFactoryOwner returns (uint128 amount0, uint128 amount1) {
        // 计算实际可提取的数量
        amount0 = amount0Requested > protocolFees.token0 ? protocolFees.token0 : amount0Requested;
        amount1 = amount1Requested > protocolFees.token1 ? protocolFees.token1 : amount1Requested;

        if (amount0 > 0) {
            // 如果提取全部数量,则保留1个wei,避免清空存储槽节省gas
            if (amount0 == protocolFees.token0) amount0--;
            // 减少协议费用余额
            protocolFees.token0 -= amount0;
            // 转账token0
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            // 如果提取全部数量,则保留1个wei,避免清空存储槽节省gas
            if (amount1 == protocolFees.token1) amount1--;
            // 减少协议费用余额
            protocolFees.token1 -= amount1;
            // 转账token1
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        // 触发事件
        emit CollectProtocol(msg.sender, recipient, amount0, amount1);
    }
}