# BatchOverflow (BeautyChain BEC Token)

## Overview

BatchOverflow was a critical integer overflow vulnerability discovered in April 2018 in several ERC-20 token contracts, most notably the BeautyChain (BEC) token. The vulnerability allowed attackers to create an enormous number of tokens without owning the corresponding balance, leading to unauthorized token creation and significant market disruption.

## Background

The vulnerability originated from improper arithmetic in the `batchTransfer()` function. Instead of using SafeMath for multiplication, the contract performed unchecked multiplication using Solidity's native `*` operator. Since Solidity versions prior to 0.8.0 did not automatically check for integer overflows, attackers could manipulate the multiplication result to overflow, bypassing balance validation.

## Root Cause

The vulnerable code is:

```solidity
uint cnt = _receivers.length;
uint256 amount = uint256(cnt) * _value;
```

The multiplication can overflow, causing `amount` to become a very small number (or zero). As a result, the balance check:

```solidity
require(balances[msg.sender] >= amount);
```

passes even when the sender does not possess enough tokens.

## Impact

- Unauthorized creation of massive token balances.
- Complete violation of ERC-20 token supply integrity.
- Exchanges suspended deposits and withdrawals of affected tokens.
- Millions of dollars worth of tokens became invalid.
- Multiple ERC-20 tokens using similar code were affected.

## Official Fix

The vulnerability can be prevented by using SafeMath multiplication:

```solidity
uint256 amount = SafeMath.mul(cnt, _value);
```

Modern Solidity versions (>=0.8.0) automatically detect arithmetic overflows and revert the transaction.

## Modern Best Practices

- Use Solidity 0.8.x or later.
- Always use checked arithmetic.
- Validate user-controlled arithmetic operations.
- Perform comprehensive smart contract security audits.
- Fuzz-test arithmetic-intensive functions.

## Repository Contents

- `contracts/BecToken.sol` – Original vulnerable BeautyChain token contract.
- `sources/official-analysis.md` – Summary of the incident.
- `sources/source-code-analysis.md` – Technical analysis of the vulnerability.
- `sources/references.md` – Reference materials.

## Notes

This repository contains the original vulnerable contract for educational and historical analysis.

## Lessons Learned

Even a single unchecked arithmetic operation can completely compromise the security of a smart contract.

## References

See `sources/references.md`.
