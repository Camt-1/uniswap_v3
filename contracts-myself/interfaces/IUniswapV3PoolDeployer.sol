// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 一个用于部署 Uniswap V3 池的合约接口
/// @notice 构造池的合约必须实现此接口，以便向池传递参数
/// @dev 使用此接口来避免在池合约中包含构造函数参数，从而使池的 init code hash 保持恒定，从而可以低成本地在链上计算使用 CREATE2 生成的池地址
interface IUniswapV3PoolDeployer {
  /// @notice 获取用于构造池的参数，这些参数在池创建期间是临时设置的
  /// @dev 由池构造函数调用以获取池的参数
  /// @return factory 工厂地址
  /// @return token0 根据地址排序的池中第一个代币
  /// @return token1 根据地址排序的池中第二个代币
  /// @return fee 池内每次交换收取的费用，以千分之一百万单位表示
  /// @return tickSpacing 初始化 tick 之间的最小间隔数
  function parameters() 
    external
    view
    returns (
      address factory,
      address token0,
      address token1,
      uint24 fee,
      int24 tickSpacing
    );
}