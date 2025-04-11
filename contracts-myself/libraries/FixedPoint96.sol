// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.4.0;

/// @title FixedPoint96
/// @notice 用于处理二进制点数的库
/// @dev 用于SqrtPriceMath.sol
library FixedPoint96 {
  uint8 internal constant RESOLUTTION = 96;
  uint256 internal constant Q96 = 0x1000000000000000000000000;
}