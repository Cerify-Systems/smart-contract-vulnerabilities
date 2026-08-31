# Fei Protocol / Rari Capital Fuse Reentrancy — April 2022

## Incident

- Date: 30 April 2022
- Protocol: Rari Capital Fuse
- Ecosystem: Fei Protocol / Tribe DAO
- Chain: Ethereum
- Loss: Approximately $80 million
- Vulnerability: Reentrancy
- Attack Vector: ETH transfer followed by reentrant `exitMarket()`
- Affected Pools: 8, 18, 27, 127, 144, 146 and 156

## Summary

On 30 April 2022, multiple Rari Capital Fuse pools were exploited.

The attacker exploited a reentrancy vulnerability in the Fuse lending contracts.

The vulnerable borrowing flow transferred ETH to the borrower using a low-level call before the borrower's internal borrowing state had been completely updated.

Because the attacker controlled the receiving contract, the ETH transfer triggered the attacker's fallback/receive function.

The attacker then re-entered the Fuse protocol through `exitMarket()`.

This allowed the attacker to remove collateral while the original borrow operation was still executing.

## Attack Flow

1. The attacker obtained temporary liquidity through flash loans.
2. USDC was supplied to a vulnerable Fuse pool as collateral.
3. The attacker entered the collateral market.
4. The attacker borrowed ETH from another Fuse market.
5. The vulnerable contract transferred ETH using a low-level call.
6. The attacker's callback executed before the borrower's state was fully updated.
7. The callback called `exitMarket()`.
8. The attacker withdrew the collateral that had been used to support the outstanding borrow.
9. The attacker repeated the process against other vulnerable pools.
10. The flash loans were repaid and the remaining assets became the attacker's profit.

## Root Cause

The root cause was a cross-function/cross-contract reentrancy vulnerability.

The ETH transfer occurred before the borrow state was completely updated.

The attacker therefore received an execution opportunity while the protocol was in an inconsistent intermediate state.

## Vulnerable Pattern

The vulnerable ordering was conceptually:

```text
check borrow
    ↓
transfer ETH to borrower
    ↓
borrow state update