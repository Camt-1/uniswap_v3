// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

// 定义一个抽象合约 NoDelegateCall
abstract contract NoDelegateCall {
    // 保存合约的原始地址（部署时的地址）
    address private immutable original;

    // 构造函数，在合约部署时执行
    constructor() {
        // 将当前合约地址存储为原始地址
        original = address(this);
    }

    // 私有函数，用于检查当前调用是否为委托调用
    function checkNotDelegateCall() private view {
        // 如果当前合约地址与原始地址不一致，则抛出异常
        require(address(this) == original);
    }

    // 修饰符，用于限制函数不能通过委托调用执行
    modifier noDelegateCall() {
        // 调用检查函数
        checkNotDelegateCall();
        // 执行修饰符修饰的函数
        _;
    }
}