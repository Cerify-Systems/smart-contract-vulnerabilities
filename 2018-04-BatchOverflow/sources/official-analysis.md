# Official Analysis

## Summary

BatchOverflow is an integer overflow vulnerability discovered in April 2018 that affected several ERC-20 token contracts, including the BeautyChain (BEC) token. The flaw allowed attackers to generate extremely large quantities of tokens by exploiting unchecked arithmetic in the `batchTransfer()` function.

## Root Cause

The vulnerability occurred because the contract calculated the total transfer amount using unchecked multiplication:

```solidity
uint256 amount = uint256(cnt) * _value;
```

If `_value` was sufficiently large, the multiplication overflowed, causing `amount` to wrap around to a very small value or zero. The subsequent balance check therefore succeeded even though the sender did not own the required number of tokens.

## Impact

- Unauthorized token creation.
- Inflation of token supply.
- Suspension of deposits and withdrawals by cryptocurrency exchanges.
- Financial losses and loss of trust in affected ERC-20 tokens.

## Resolution

The issue can be prevented by using checked arithmetic (e.g., `SafeMath.mul()`) or by compiling contracts with Solidity version 0.8.0 or later, where integer overflow checks are built into the language.

## Source

- PeckShield Security Analysis
- CVE-2018-10299
- BeautyChain (BEC) Verified Contract