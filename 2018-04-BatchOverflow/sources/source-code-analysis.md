# Source Code Analysis

## Overview

The vulnerability exists in the `batchTransfer()` function of the BeautyChain (BEC) token contract. The function allows a sender to transfer the same token amount to multiple recipients in a single transaction.

## Vulnerable Code

```solidity
function batchTransfer(address[] _receivers, uint256 _value)
    public
    whenNotPaused
    returns (bool)
{
    uint cnt = _receivers.length;
    uint256 amount = uint256(cnt) * _value;

    require(cnt > 0 && cnt <= 20);
    require(_value > 0 && balances[msg.sender] >= amount);

    balances[msg.sender] = balances[msg.sender].sub(amount);

    for (uint i = 0; i < cnt; i++) {
        balances[_receivers[i]] = balances[_receivers[i]].add(_value);
        Transfer(msg.sender, _receivers[i], _value);
    }

    return true;
}
```

## Root Cause

The vulnerability is caused by the following statement:

```solidity
uint256 amount = uint256(cnt) * _value;
```

The multiplication uses Solidity's native `*` operator instead of `SafeMath.mul()`. In Solidity versions prior to 0.8.0, integer overflows do not automatically revert the transaction.

An attacker can choose a very large value for `_value` so that the multiplication overflows. As a result, `amount` becomes a much smaller number (or even zero), causing the balance check to succeed incorrectly.

```solidity
require(_value > 0 && balances[msg.sender] >= amount);
```

The contract then subtracts only the overflowed value from the sender's balance while transferring the full `_value` amount to every recipient.

## Impact

This flaw allows an attacker to create an enormous number of tokens without possessing the required balance. The total token supply is effectively inflated, violating the security guarantees of the ERC-20 standard.

## Mitigation

The multiplication should use checked arithmetic:

```solidity
uint256 amount = SafeMath.mul(cnt, _value);
```

Modern Solidity versions (0.8.0 and later) automatically detect integer overflow and revert the transaction, preventing this class of vulnerability.