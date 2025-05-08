// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3PoolDeployer.sol';

import './UniswapV3Pool.sol';

// 合约用于部署Uniswap V3池子
contract UniswapV3PoolDeployer is IUniswapV3PoolDeployer {
    // 用于存储部署池子所需的参数
    struct Parameters {
        address factory;
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
    }

    // 公共参数变量, 供外部调用
    Parameters public override parameters;

    // 部署池子的内部函数
    function deploy(
        address factory,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing
    ) internal returns (address pool) {
        // 赋值参数
        parameters = Parameters({
            factory: factory,
            token0: token0,
            token1: token1,
            fee: fee,
            tickSpacing: tickSpacing
        });
        // 使用CREATE2部署新的UniswapV3合约, 并返回地址
        pool = address(new UniswapV3Pool{salt: keccak256(abi.encode(token0, token1, fee))}());
        // 部署完成后删除参数, 释放存储空间
        delete parameters;
    }
}