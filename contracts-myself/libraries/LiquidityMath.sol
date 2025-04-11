// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

//该库用于计算流动性
library LiquidityMath{
  /**
   * @notice 将一个有符号的流动性增量添加到流动性中, 如果发生溢出或下溢则回退
   * @param x 变更前的流动性
   * @param y 流动性应变更的增量
   * @return z 流动性增量
   */
  function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
    if (y < 0) {
      require((z = x - uint128(-y)) < x, 'LS');
    } else {
      require((z = x + uint128(y)) > x, 'LA');
    }
  }
}