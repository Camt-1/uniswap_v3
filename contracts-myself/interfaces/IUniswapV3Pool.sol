// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './pool/IUniswapV3PoolImmutables.sol';
import './pool/IUniswapV3PoolState.sol';
import './pool/IUniswapV3PoolDerivedState.sol';
import './pool/IUniswapV3PoolActions.sol';
import './pool/IUniswapV3PoolOwnerActions.sol';
import './pool/IUniswapV3PoolEvents.sol';

/// @title Uniswap V3 池接口
/// @notice Uniswap 池用于在严格符合 ERC20 规范的任意两种资产之间提供交换和自动化做市功能
/// @dev 池接口被拆分为多个更小的部分
interface IUniswapV3Pool is
  IUniswapV3PoolImmutables,
  IUniswapV3PoolState,
  IUniswapV3PoolDerivedState,
  IUniswapV3PoolActions,
  IUniswapV3PoolOwnerActions,
  IUniswapV3PoolEvents
{
  
}