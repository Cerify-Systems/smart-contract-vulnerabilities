# Fix

## 1. Protect `exitMarket()` with the same reentrancy mechanism

The immediate problem was that `exitMarket()` was left outside the pool-wide reentrancy protection introduced in the April security upgrade.

It should not be possible to call `exitMarket()` while another market operation is in its intermediate state.

## 2. Follow Checks-Effects-Interactions

The ETH borrow path should not transfer ETH to an arbitrary external receiver before recording the borrower's debt.

The safer sequence is:

```text
validate borrow
    ↓
update borrow state
    ↓
update total borrows
    ↓
emit accounting events
    ↓
transfer ETH
```

rather than:

```text
validate borrow
    ↓
transfer ETH
    ↓
external callback
    ↓
update borrow state
```

## 3. Use a pool-wide reentrancy guard consistently

The incident showed why protecting only the obvious `borrow`, `mint`, and `redeem` functions is insufficient.An attacker does not need to re-enter the same function.The attacker can re-enter a second function whose assumptions depend on the first function's incomplete state.

Therefore all functions that can observe or modify the same financial state need a coherent reentrancy strategy.

## 4. Regression tests

The security test suite should include:

- borrow ETH to an attacker contract;
- trigger a fallback during the ETH transfer;
- call `exitMarket()` from the fallback;
- verify that the reentrant call fails;
- verify that the borrow balance is already recorded before any external call;
- verify that collateral remains locked after a borrow;
- repeat across different markets.

The critical invariant is:

```text
A borrower cannot remove collateral during an in-progress borrow
before the borrower's debt has been recorded.
```

## 5. Defense-in-depth

Additional protections include:

- checks-effects-interactions ordering;
- `nonReentrant` on all relevant state-changing entry points;
- updating debt before external transfers;
- mainnet-fork regression tests for historical exploits;
- monitoring for unusual borrow → callback → exitMarket sequences.
