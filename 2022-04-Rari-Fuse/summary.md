# Summary

## Incident

**Protocol:** Rari Capital Fuse / Fei Protocol  
**Date:** April 30, 2022  
**Chain:** Ethereum  
**Loss:** approximately $80M  
**Class:** Cross-function reentrancy

## Vulnerable Components

```text
Comptroller.exitMarket()
        +
CEther/CToken borrow flow
```

The Rari Fuse `Comptroller` source is based on Compound and contains `exitMarket()` without the pool-wide non-reentrancy hook that protected other operations. The repository source is Solidity 0.5.17. citeturn3search1turn1search1

## Core bug

The ETH borrow path performed an external ETH transfer while the borrower's new borrow balance had not yet been finalized.

The attacker contract received ETH and re-entered:

```solidity
Comptroller.exitMarket(cToken)
```

`exitMarket()` checked the attacker's account snapshot.

Because the new ETH debt was not yet reflected in the snapshot, the check:

```text
amountOwed == 0
```

could pass.

The attacker then removed the collateral market from the account's liquidity calculation and redeemed the collateral.

## Attack

```text
flash loan
    ↓
deposit collateral
    ↓
enter Fuse market
    ↓
borrow ETH
    ↓
ETH sent to attacker
    ↓
receive()/fallback()
    ↓
exitMarket()
    ↓
collateral released
    ↓
redeem collateral
    ↓
repay flash loan
    ↓
retain stolen assets
```

The attack was repeated across multiple Fuse pools. 
