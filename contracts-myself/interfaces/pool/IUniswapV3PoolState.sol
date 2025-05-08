// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV3PoolState {
  /**
   * 
   * @return sqrtPriceX96 该池当前价格, 表示为一个 Q64.96 格式的值
   * @return tick 该池当前tick
   * @return observationIndex 最后一个写入的预言机观测值的索引
   * @return observationCardinality 池中当前存储的最大观测值
   * @return observationCardinalityNext
   * @return feeProtocol 池中两个代币的协议费用
   * @return unlocked 该池当前是否允许重入
   */
  function slot0()
    external
    view
    returns (
      uint160 sqrtPriceX96,
      int24 tick,
      uint16 observationIndex,
      uint16 observationCardinality,
      uint16 observationCardinalityNext,
      uint8 feeProtocol,
      bool unlocked
    );

  function feeGrowthGlobal0X128() external view returns (uint256);

  function feeGrowthGlobal1X128() external view returns (uint256);

  function protocolFees() external view returns (uint128 token0, uint128 token1);

  function liquidity() external view returns (uint128);

  function ticks(int24 tick)
    external
    view
    returns (
      uint128 liquidityGross,
      int128 liquidityNet,
      uint256 feeGrowthOutside0X128,
      uint256 feeGrowthOutside1X128,
      int56 tickCumulativeOutside,
      uint160 secondsPerLiquidtiyOutsidexX128,
      uint32 secondsOutside,
      bool initialized
    );
  
  function tickBitmap(int16 wordPosition) external view returns (uint256);

  function positions(bytes32 key)
    external
    view
    returns (
      uint128 _liqulidity,
      uint256 feeGrowthInside0LastX128,
      uint256 feeGrowthInside1LastX128,
      uint128 tokensOwed0,
      uint128 toknesOwed1
    );

  function observations(uint256 index)
    external
    view
    returns (
      uint32 blockTimestamp,
      int56 tickCumulative,
      uint160 secondsPerLiquidityCumulativeX128,
      bool initialized
    );
}