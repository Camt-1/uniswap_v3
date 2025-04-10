// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV3PoolActions {
  /**
   * 初始化池的初始价格
   * @param sprtPriceX96 池的初始价格, 表示为一个 Q64.96 格式的值
   * (即价格是sqrt(amountToken1/amountToken0))
   */
  function initialize(uint160 sprtPriceX96) external;

  /**
   * 添加流动性
   * @param recipient 接收流动性的地址
   * @param tickLower 添加流动性的区间下界
   * @param tickUpper 添加流动性的区间上界
   * @param amount 要添加的流动性数量
   * @param data 传递给回调函数的额外数据
   * @return amount0 添加流动性所需支付的token0数量
   * @return amount1 添加流动性所需支付的token1数量
   */
  function mint(
    address recipient,
    int24 tickLower,
    int24 tickUpper,
    uint128 amount,
    bytes calldata data
  ) external returns (uint256 amount0, uint256 amount1);

  /**
   * 提取代币
   * @param recipient 接收代币的地址
   * @param tickLower 提取代币的区间的上界
   * @param tickUpper 提取代币的区间的下界
   * @param amount0Requested 请求提取的token0数量
   * @param amount1Requested 请求提取的token1数量
   * @return amount0 实际收集到的token0数量
   * @return amount1 实际收集到的token1数量
   */
  function collect(
    address recipient,
    int24 tickLower,
    int24 tickUpper,
    uint128 amount0Requested,
    uint128 amount1Requested
  ) external returns (uint128 amount0, uint128 amount1);

  /**
   * 提取流动性
   * @param tickLower 提取流动性的区间下界
   * @param tickUpper 提取流动性的区间上界
   * @param amount 要提取的流动性数量
   * @return amount0 提取流动性后返回的token0数量
   * @return amount1 提取流动性后返回的token1数量
   */
  function burn(
    int24 tickLower,
    int24 tickUpper,
    uint128 amount
  ) external returns (uint256 amount0, uint256 amount1);

  /**
   * 进行token0和token1之间的交换
   * @param recipient 接收交换输出的地址
   * @param zeroForOne 交换方向, true表示从token0换成token1, false表示从token1换成tokne0
   * @param amountSpecified 交换的具体金额, 正值表示输入, 负值表示输出
   * @param sqrtPriceLimitX96 价格限制, 表示为Q64.96格式
   * @param data 传递给回调函数的额外数据
   * @return amount0 池内的token0的余额变化(负值表示减少, 正值表示增加)
   * @return amount1 池内的token1的余额变化(负值表示减少, 正值表示增加)
   */
  function swap(
    address recipient,
    bool zeroForOne,
    int256 amountSpecified,
    uint160 sqrtPriceLimitX96,
    bytes calldata data
  ) external returns (int256 amount0, int256 amount1);

  /**
   * 执行闪电贷操作,即借用token0和/或token1,并在回调中归还(加上手续费)
   * @param recipient 接收借款代币的地址
   * @param amount0 借走的token0数量
   * @param amount1 借走的token1数量
   * @param data 传递给回调函数的额外数据
   */
  function flash(
    address recipient,
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
  ) external;

  //扩展observations数组可存储的容量,用于预言机
  //默认的observations数组的实际存储的容量只是1, 需要扩展这个容量才可以计算预言机价格
  function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;
}