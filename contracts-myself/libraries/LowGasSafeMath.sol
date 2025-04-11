// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;

//该库用于处理执行数学运算时发生的溢出或下溢, 以实现最小gas消耗
library LowGasSafeMath {
  /// @notice 返回x + y, 如果结果溢出uint256则回退
  /// @param x 被加数
  /// @param y 加数
  /// @return z x与y的和
  function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
    require((z = x + y) >= x);
  }

  /// @notice 返回x - y, 如果结果下溢则回退
  /// @param x 被减数
  /// @param y 减数
  /// @return z x与y的差值
  function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
    require((z = x - y) <= x);
  }

  /// @notice 返回 x * y，如果结果溢出则回退
  /// @param x 被乘数
  /// @param y 乘数
  /// @return z x 与 y 的乘积
  function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
    require(x == 0 || (z = x * y) / x == y);
  }

  /// @notice 返回 x + y，如果结果溢出或下溢则回退
  /// @param x 被加数
  /// @param y 加数
  /// @return z x 与 y 的和
  function add(int256 x, int256 y) internal pure returns (int256 z) {
    require((z = x + y) >= x == (y >= 0));
  }

  /// @notice 返回 x - y，如果结果溢出或下溢则回退
  /// @param x 被减数
  /// @param y 减数
  /// @return z x 与 y 的差值
  function sub(int256 x, int256 y) internal pure returns (int256 z) {
    require((z = x - y) <= x == (y >= 0));
  }
}