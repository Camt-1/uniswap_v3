// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

/// @title Oracle
/// @notice 提供广泛系统设计中有用的价格和流动性数据
/// @dev 存储预言机数据的实例称为'observations', 这些数据存储在预言机数字中
/// 每个池在初始化时预言机数字的长度为1. 任何人都可以支付SSTORE费用以增加预言机数字的最大长度.
/// 当数组被完全填充时会添加新的槽位.
/// 当预言机数组的长度被填满时, 旧的observation会被覆盖
/// 通过向observe()传递0 可以获取最新的observation, 且不受预言机数组长度的限制
library Oracle {
  struct Obervation {
    uint32 blockTimestamp;
    int56 tickCumulative;
    uint160 secondsPerLiquidityCumulativeX128;
    bool initialized;
  }

  /// 
  /// @param last 被转换的指定Obervation
  /// @param blockTimestamp 新的observation的时间戳
  /// @param tick 当前observation的有效tick
  /// @param liquidity 当前 observation 的范围内总流动性
  /// @return Observation 新生成的 observation
  function transform(
    Obervation memory last,
    uint32 blockTimestamp,
    int24 tick,
    uint128 liquidity
  ) private pure returns (Observation memory) {
    uint32 dalta = blockTimestamp - last.blockTimestamp;
    return
      Observation({
        blockTimestamp: blockTimestamp,
        tickCumulative: last.tickCumulative + int56(tick) * delta,
        secondsPerLiquidityCumulativeX128: last.secondsPerLiquidityCumulativeX128 +
          ((uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1)),
        initialized: ture
      });
  }

}