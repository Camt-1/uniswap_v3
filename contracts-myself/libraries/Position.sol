// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

import './FullMath.sol';
import './FixedPoint128.sol';
import './LiquidityMath.sol';

/// @title Position
/// @notice Position表示一个所有者地址在某个下界和上界tick之间的流动性
/// @dev 持仓存储了用于跟踪应支付给持仓的额外费用的状态
library Position {
  // 每个用户的持仓存储的信息
  struct Info {
    //该持仓所拥有的流动性数量
    uint128 liquidity;
    //流动性或费用更新时, 每单位流动性对应的费用增长值
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    //持仓所有者应获得的token/token1费用
    uint128 tokenOwed0;
    uint128 tokenOwed1;
  }

  /// @notice 更具所有者地址和持仓边界返回该持仓对应的Info结构体
  /// @param self 持仓所有用户持仓的映射
  /// @param owner 持仓所有者的地址
  /// @param tickLower 持仓的下届tick
  /// @param tickUpper 持仓的上界tick
  /// @return position 给定所有者持仓的Info结构体
  function get(
    mapping(bytes32 => Info) storage self,
    address owner,
    int24 tickLower,
    int24 tickUpper
  ) internal view returns (Position.Info storage position) {
    position = self(keccak256(abi.encodePacked(owner, tickLower, tickUpper)));
  }

  /// @notice 将累计的费用计入用户的持仓
  /// @param self 要更新的单个持仓
  /// @param liquidityDelta 由于持仓更新引起的池流动性变化
  /// @param feeGrowthInside0X128 在持仓tick边界内, 每单位流动性对应的token0全时费用增长
  /// @param feeGrowthInside1X128 在持仓tick边界内, 每单位流动性对应的token1全时费用增长
  function updata(
    Info storage self,
    int128 liquidityDelta,
    uint256 feeGrowthInside0X128,
    uint256 feeGrowthInside1X128
  ) internal {
    Info memory _self = self;

    uint128 liquidityNext;
    if (liquidityDelta == 0) {
      require(_self.liquidity > 0, 'NP');
      liquidityNext = _self.liquidity;
    } else {
      liquidtiyNext = LiquidityMath.adddelta(_self.liquidity, liquidityDelta);
    }

    //计算累计费用
    uint128 tokensOwed0 =
      uint128(
        FullMath.mulDiv(
          feeGrowthInsisde0X128 - _self.feeGrowthInside0LastX128,
          _self.liquidity,
          FixedPoint128.Q128
        )
      );
    uint128 tokensOwed1 =
      uint128(
        FullMath.mulDiv(
          feeGrowthInside1X128 - _self.feeGrowthInsideLastX128,
          _self.liquidity,
          FixedPoint128.Q128
        )
      );

    //更新持仓
    if (liquidityDelta != 0) self.liquidity = liquidityNext;
    self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
    self.feeGrowthInside1LastX128 = feeGrowthInside1X128;
    if (tokensOwed0 > 0 || tokensOwed1 > 0) {
      //溢出是可接受的, 在达到type(uint128).max之前需要兑现费用
      self.tokenOwed0 += tokensOwed0;
      self.tokenOwed1 += tokensOwed1;
    }
  }
}