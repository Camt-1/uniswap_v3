// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Uniswap 的最简 ERC20 接口
/// @notice 包含 Uniswap V3 中使用的部分完整 ERC20 接口
interface IERC20 {
  /// @notice 返回某个账户的代币余额
  /// @param account 要查询代币余额的账户地址
  /// @return 返回该账户持有的代币数量
  function balanceOf(address account) external view returns (uint256);

  /// @notice 将一定数量的代币从 msg.sender 转移到接收方
  /// @param recipient 接收转移代币的账户地址
  /// @param amount 要从发送者转移到接收者的代币数量
  /// @return 转移成功时返回 true，转移失败时返回 false
  function transfer(address recipient, uint256 amount) external returns (bool);

  /// @notice 返回代币所有者给予花费者的当前授权额度
  /// @param owner 代币所有者的账户地址
  /// @param spender 被授权可花费代币的账户地址
  /// @return 返回 owner 授权给 spender 的当前额度
  function allowance(address owner, address spender) external view returns (uint256);

    /// @notice 设置 msg.sender 为代币所有者时，给予 spender 指定数量的代币授权额度
    /// @param spender 将被授权花费代币的账户地址
    /// @param amount 授权 spender 可使用的代币数量
    /// @return 授权成功时返回 true，授权失败时返回 false
  function approve(address spender, uint256 amount) external view returns (bool);

    /// @notice 从 sender 向 recipient 转移一定数量的代币，转移量不超过 msg.sender 被授权的额度
    /// @param sender 发起转移的账户地址
    /// @param recipient 接收代币的账户地址
    /// @param amount 转移的代币数量
    /// @return 转移成功时返回 true，转移失败时返回 false
  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  /// @notice 当代币通过 transfer 或 transferFrom 从一个地址转移到另一个地址时触发的事件
  /// @param from 发出代币的账户地址，即代币余额减少的账户
  /// @param to 接收代币的账户地址，即代币余额增加的账户
  /// @param value 转移的代币数量
  event Transfer(address indexed from, address indexed to, uint256 value);

  /// @notice 当代币所有者改变其账户授权给某个花费者的额度时触发的事件
  /// @param owner 授权花费者的代币所有者账户地址
  /// @param spender 被授权可以花费代币的账户地址
  /// @param value 新设置的授权额度
  event Approval(address indexed owner, address indexed spender, uint256 value);
}