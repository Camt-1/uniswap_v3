// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV3PoolDerivedState {
  /**
   * - 返回从当前区块时间戳起, 指定时间的点(secondsAgo)的累计价格(tick)和流动性值.
   * - 可用于计算某时间段内的时间加权平均价格或流动性范围内的时间加权平均流动性.
   * @param secondsAgos 一个数组, 指定从当前区块时间戳开始的过去时间点(如[3600, 0]表示过去一小时和当前时间点)
   * @return tickCumulatives 一个数组, 表示每个secondsAgo时间点的累计价格(tick)
   * @return secondsPerLiquidityCumulativeX128s 一个数组, 表示在每个secondsAgo时间点的累计秒数/流动性值
   */
  function observe(uint32[] calldata secondsAgos)
    external
    view
    returns (
      int56[] memory tickCumulatives,
      uint160[] memory secondsPerLiquidityCumulativeX128s
    );
  

  /**
   * - 返回特定价格范围内(由tickLower和tickUPper定义)的快照值,
   * 包括累计价格, 每单位流动性的累计秒数和区间内的累计秒数.
   * - 这些快照值只能用于与其它快照进行比较, 用于分析某段时间内的变化.
   * @param tickLower 价格范围的下界(最低tick值)
   * @param tickUpper 价格范围的上届(最高tick值)
   * @return tickCumulativeInside 区间内的价格累计值
   * @return secondsPerLiquidityInsidex128 区间内的单位流动性的累计秒数(Q128格式)
   * @return secondesInside 区间内的累计秒数
   */
  function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
    external
    view
    returns (
      int56 tickCumulativeInside,
      uint160 secondsPerLiquidityInsidex128,
      uint32 secondesInside
    );
}