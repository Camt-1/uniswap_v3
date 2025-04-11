// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0 <0.8.0;

/// @title 包含 512 位数学函数
/// @notice 支持在中间值发生溢出的情况下执行乘法和除法运算而不丢失精度
/// @dev 处理“虚幻溢出”，即允许在中间结果超过 256 位时进行乘法和除法运算
library FullMath {
  /**
   * 以完全精度计算floor(a * b / denominator).
   * 如果结果溢出uint256或denominator == 0, 则抛出异常
   * @param a 被乘数
   * @param b 乘数
   * @param denominator 除数
   * @return result 256位计算结果
   */
  function mulDiv(
    uint256 a,
    uint256 b,
    uint256 denominator
  ) internal pure returns (uint256 result) {
    //512位乘法[prod1 prod0] = a * b
    //通过模 2**256 和模 2**256 - 1 来计算结果
    //然后使用中国剩余定理重建512位结果
    //最终结果存储在两个256位变量中, product = prod1 * 2**256 + prod0
    uint256 prod0; //乘积的最低有效256位
    uint256 prod1; //乘积的最高有效256位
    assembly {
      let mm := mulmod(a, b, not(0))
      prod0 := mul(a, b)
      prod1 := sub(sub(mm, prod0), lt(mm, prod0))
    }

    //处理未溢出的情况, 256位除法
    if (prod1 == 0) {
      require(denominator > 0);
      assembly {
        result := div(prod0, denominator)
      }
      return result;
    }

    //确保结果小于 2**256, 同时确保denominator != 0
    require(denominator > prod1);

    ///////////////////////////////////////////////
    // 512 位除以 256 位
    ///////////////////////////////////////////////

    //通过减去余数使除法变得精确
    //使用mulmod计算余数
    uint256 remainder;
    assembly {
      remainder := mulmod(a, b, denominator)
    }
    //从512位减去256位数
    assembly {
      prod1 := sub(prod1, gt(remainder, prod0))
      prod0 := sub(prod0, remainder)
    }

    //从denominator中提取出2的幂
    //计算denominator的最大的幂因子, uint256 twos = -denominator & denominator;
    //将denominator除以2的幂因子
    uint256 twos = denominator & (~denominator + 1);
    assembly {
      denominator := div(denominator, twos)
    }

    //将[prod1 prod0]除以2的幂因子
    assembly {
      prod0 := div(prod0, twos)
    }

    //将prod1的位移入prod0, 需翻转`twos`
    assembly {
      twos := add(div(sub(0, twos), twos), 1)
    }
    prod0 |= prod1 * twos;

    //计算denominator在模 2**256 下的逆元
    uint256 inv = (3 * denominator) ^ 2;

    inv *= 2 - denominator * inv; //模 2**8 的逆元
    inv *= 2 - denominator * inv; //模 2**16 的逆元
    inv *= 2 - denominator * inv; //模 2**32 的逆元
    inv *= 2 - denominator * inv; //模 2**64 的逆元
    inv *= 2 - denominator * inv; //模 2**128 的逆元
    inv *= 2 - denominator * inv; //模 2**256 的逆元

    //通过与denominator的模逆元相乘, 计算最终结果
    result = prod0 * inv;
    return result;
  }

  /**
   * 以完全精度计算ceil(a * b / denominator).
   * 如果结果溢出uint256或denominator == 0, 则抛出异常
   * @param a 被乘数
   * @param b 乘数
   * @param denominator 除数
   * @return result 256位计算结果
   */
  function mulDivRoundingUp(
    uint256 a,
    uint256 b,
    uint256 denominator
  ) internal pure returns (uint256 result) {
    result = mulDiv(a, b, denominator);
    if (mulmod(a, b, denominator) > 0) {
      require(result < type(uint256).max);
      result++;
    }
  }
}