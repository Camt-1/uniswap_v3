// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV3PoolImmutables {
  //部署池的合约,必须遵循IUniswapV3Factory接口
  function factory() external view returns (address);

  //池中第一个代币, 按地址排序
  function token0() external view returns (address);

  //池中第二个代币, 按地址排序
  function token1() external view returns (address);

  //矿池手续费, 以百分之一bip为单位(即1e-6)
  function fee() external view returns (uint24);

  //池刻度间隔
  function tickSpacing() external view returns (int24);

  //每个tick的最大流动性
  function maxLiquidityPerTick() external view returns (uint128);
}