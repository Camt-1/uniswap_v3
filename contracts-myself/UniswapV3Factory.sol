// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Factory.sol';

import './UniswapV3PoolDeployer.sol';
import './NoDelegateCall.sol';

import './UniswapV3Pool.sol';

// UniswapV3PoolFactory工厂合约, 负责创建和管理池子
contract UniswapV3PoolFactory is IUniswapV3Factory, UniswapV3PoolDeployer, NoDelegateCall {
    // 合约拥有着
    address public override owner;

    // 记录不同fee对应的tickSpacing
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    // 记录每个(token0, token1, fee)对应的池子地址
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    // 构造函数, 初始化owner和默认的feeAmountTickSpacing
    constructor() {
        // 设置合约拥有者为部署者
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        // 启用500费率, tick间隔10
        feeAmountTickSpacing[500] = 10;
        emit FeeAmountEnabled(500, 10);
        // 启用3000费率, tick间隔60
        feeAmountTickSpacing[3000] = 60;
        emit FeeAmountEnabled(3000, 60);
        // 启用1000费率, tick间隔200
        feeAmountTickSpacing[1000] = 200;
        emit FeeAmountEnabled(1000, 200);
    }


    // 创建新的池子
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pool) {
        // 两个代币不相同
        require(tokenA != tokenB);
        // 按地址大小排序, 确保token0 < token1
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // token0不能为0地址
        require(token0 != address(0));
        // 获取tickSpacing
        int24 tickSpacing = feeAmountTickSpacing[fee];
        // 必须已启用该费率
        require(tickSpacing != 0);
        // 该池子不能已存在
        require(getPool[token0][token1][fee] == address(0));
        // 部署新池子
        pool = deploy(address(this), token0, token1, fee, tickSpacing);
        // 记录池子地址
        getPool[token0][token1][fee] = pool;
        // 触发事件
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    // 设置新的owner
    function setOwner(address _owner) external override {
        // 只有当前owner可以调用
        require(msg.sender == owner);
        // 触发事件
        emit OwnerChanged(owner, _owner);
        // 更新owner
        owner = _owner;
    }

    // 启用新的费率和tickSpacing
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override {
        // 只有owner可以调用
        require(msg.sender == owner);
        // 费率不能太大
        require(fee < 1000000);

        // tickSpacing必须在合理范围
        require(tickSpacing > 0 && tickSpacing < 16384);
        //该费率不能已存在
        require(feeAmountTickSpacing[fee] == 0);

        // 设置费率和tickSpacing
        feeAmountTickSpacing[fee] = tickSpacing;
        // 触发事件
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}