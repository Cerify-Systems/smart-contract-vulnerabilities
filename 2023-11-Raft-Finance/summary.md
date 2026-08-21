# Summary

## Protocol

Raft Finance

## Date

November 10, 2023

## Chain

Ethereum

## Vulnerability

Precision loss / incorrect upward rounding in rebasing collateral-share minting.

## Primary exploited contract

```text
InterestRatePositionManager
0x9AB6b21cDF116f611110b048987E58894786C244
```

Etherscan confirms the contract is verified and compiled with Solidity 0.8.19.

## Vulnerable share calculation

The affected collateral token used:

```solidity
_mint(to, amount.divUp(storedIndex));
```

with:

```solidity
return (((a * ONE) - 1) / b) + 1;
```

When `a > 0`, this calculation returns at least `1`.

That becomes dangerous when `storedIndex` has been manipulated to an extremely large value.

## Index manipulation

`InterestRatePositionManager` updated the collateral token's index using:

```solidity
raftCollateralToken.setIndex(
    collateralToken.balanceOf(address(this))
);
```

The attacker donated approximately 1,061 cbETH to the manager before liquidation, causing the balance used for the index calculation to become artificially large. citeturn4search0turn5search2

## Result

The attacker repeatedly deposited 1 wei cbETH and received 1 wei rcbETH-c because of `divUp()`.Those shares became highly valuable under the manipulated index. The inflated collateral position was then used to borrow approximately 6.7M R.

## Classification

- Precision loss
- Incorrect rounding direction
- Share inflation
- Donation/index manipulation
- Economic/business-logic vulnerability
