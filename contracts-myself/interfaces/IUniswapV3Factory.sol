// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Uniswap V3 工厂接口
/// @notice Uniswap V3 工厂用于创建 Uniswap V3 池以及对协议费用进行管理控制
interface IUniswapV3Factory {
  /// @notice 当工厂所有者发生变更时触发
  /// @param oldOwner 变更前的所有者
  /// @param newOwner 变更后的所有者
  event OwnerChanged(address indexed oldOwner, address indexed newOwner);

  /// @notice 当创建池时触发
  /// @param token0 池中第一个代币（根据地址排序）
  /// @param token1 池中第二个代币（根据地址排序）
  /// @param fee 池内每次交换收取的费用，以千分之一百万（百万分之一）的单位表示
  /// @param tickSpacing 初始化 tick 之间最小的间隔数
  /// @param pool 创建的池的地址  
  event PoolCreated(
    address indexed token0,
    address indexed token1,
    uint24 indexed fee,
    int24 tickSpacing,
    address pool
  );

  /// @notice 当通过工厂为池的创建启用新的费用金额时触发
  /// @param fee 启用的费用，以千分之一百万表示
  /// @param tickSpacing 针对使用该费用创建的所有池所强制执行的最小 tick 间隔数
  event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);

  /// @notice 返回当前工厂所有者的地址
  /// @dev 当前所有者可通过 setOwner 进行更改
  /// @return 返回工厂所有者的地址
  function owner() external view returns (address);

  /// @notice 根据给定费用金额返回相应的 tick 间隔数，如果该费用未启用则返回 0
  /// @dev 费用金额一旦启用便无法移除，因此该值应在调用上下文中硬编码或缓存
  /// @param fee 以千分之一百万表示的启用费用。如果费用未启用，则返回 0
  /// @return 返回对应的 tick 间隔数
  function feeAmountTickSpacing(uint24 fee) external view returns (int24);

  /// @notice 根据一对代币和费用返回对应的池地址，如果不存在则返回地址 0
  /// @dev tokenA 和 tokenB 可以按照 token0/token1 或 token1/token0 的顺序传入
  /// @param tokenA 代币之一的合约地址，可以是 token0 或 token1
  /// @param tokenB 另一种代币的合约地址
  /// @param fee 池内每次交换收取的费用，以千分之一百万表示
  /// @return pool 池的地址
  function getPool(
    address tokenA,
    address tokenB,
    uint24 fee
  ) external view returns (address pool);

  /// @notice 创建一个由指定的两个代币和费用构成的池
  /// @param tokenA 所需池中两个代币之一
  /// @param tokenB 所需池中的另一个代币
  /// @param fee 池的目标费用
  /// @dev tokenA 和 tokenB 可按任意顺序传入：token0/token1 或 token1/token0。tickSpacing 从费用中获取。如果池已存在、费用无效或代币参数无效，则调用会回退。
  /// @return pool 新创建池的地址
  function createdPool(
    address tokenA,
    address tokenB,
    uint24 fee
  ) external returns (address pool);

  /// @notice 更新工厂的所有者
  /// @dev 必须由当前所有者调用
  /// @param _owner 工厂的新所有者
  function setOwner(address _owner) external;

  /// @notice 为指定的 tickSpacing 启用某个费用金额
  /// @dev 一旦启用，费用金额永远不会被移除
  /// @param fee 要启用的费用金额，以千分之一百万表示（即 1e-6）
  /// @param tickSpacing 对所有使用该费用金额创建的池强制实施的 tick 间隔
  function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
}