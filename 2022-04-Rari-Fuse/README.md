# Rari Capital Fuse Exploit — April 30, 2022

## Incident

On April 30, 2022, the Rari Capital Fuse lending pools were exploited for approximately $80 million.

The exploit was a cross-asset reentrancy attack involving the Fuse `CEther`/`CToken` borrowing flow and the pool `Comptroller`.

The critical sequence was:

1. The attacker supplied collateral.
2. The attacker borrowed ETH.
3. ETH was transferred to the attacker's contract before the borrower's borrow balance had been updated.
4. The attacker's fallback/receive function re-entered the pool through `Comptroller.exitMarket()`.
5. `exitMarket()` saw no outstanding borrow for the just-started borrow because the borrow state had not yet been written.
6. The attacker exited the collateral market and subsequently redeemed the collateral.
7. The process was repeated across multiple Fuse pools.

Independent incident analyses identify `exitMarket()` as the missing reentrancy protection and the ETH `borrow()` path as the interaction that exposed the issue. citeturn1search1turn1search2turn1search3


## Root cause

Rari had introduced a pool-wide reentrancy guard, but `exitMarket()` was not protected by it.

At the same time, the ETH borrowing path transferred ETH externally before the borrower's new debt had been fully recorded.

That created this state:

```text
Before borrow transfer:
    collateral = present
    debt        = old value

External ETH transfer
        ↓
attacker re-enters
        ↓
exitMarket()
        ↓
borrow snapshot still sees old debt
        ↓
collateral market can be exited
```

This was a classic **cross-function / cross-contract reentrancy** problem.

## Impact

The incident drained approximately $80 million from seven Rari Fuse pools. The attacker address identified by incident databases is:

```text
0x6162759eDAd730152F0dF8115c698a42E666157F
```

The attack was later followed by an agreement to reimburse affected users through Tribe DAO governance.


