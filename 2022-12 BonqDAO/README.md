# BonqDAO Oracle Price Manipulation — February 2023

## Incident

- Folder: 2022-12-BonqDAO
- Protocol: BonqDAO
- Launch: 15 December 2022
- Exploit: 1 February 2023
- Network: Polygon
- Attack Type: Oracle Price Manipulation
- Primary Vulnerability: Improper Tellor oracle integration
- Affected Asset: WALBT
- Stablecoin: BEUR

## Summary

BonqDAO was a zero-interest overcollateralized lending protocol that
allowed users to borrow BEUR against supported collateral.

On 1 February 2023, an attacker exploited the WALBT price oracle.

BonqDAO used a custom TellorPriceFeed contract to obtain the WALBT/USD
price from TellorFlex.

The vulnerable implementation used:

    getCurrentValue()

This returned the latest submitted Tellor value immediately.

Because Tellor allows reporters to submit values that can subsequently
be disputed, newly submitted values should not be trusted immediately.

The attacker exploited this design.

## Attack

The attacker first staked:

    10 TRB

in TellorFlex.

The attacker then submitted an extremely high WALBT price of roughly:

    $5,000,000

per WALBT.

Bonq immediately consumed the new price.

The attacker created a WALBT trove and deposited:

    0.1 WALBT

Because the oracle reported an enormous WALBT value, the collateral
appeared to be worth an extremely large amount.

The attacker then borrowed approximately:

    100,000,000 BEUR

## Second Phase

The attacker later submitted an extremely low WALBT price.

This caused many existing WALBT-backed troves to become
undercollateralized.

The attacker liquidated more than 30 troves.

The attacker then used the previously obtained BEUR to purchase the
liquidated WALBT collateral.

Approximately:

    113.8M WALBT

was acquired.

## Attack Flow

```text
10 TRB
   |
   v
TellorFlex
   |
   | submitValue($5M WALBT)
   v
TellorPriceFeed
   |
   | getCurrentValue()
   v
Bonq Oracle
   |
   v
WALBT artificially expensive
   |
   v
0.1 WALBT collateral
   |
   v
~100M BEUR borrowed
   |
   |
   | second transaction
   v
submitValue(very low WALBT price)
   |
   v
Existing troves become undercollateralized
   |
   v
Liquidate troves
   |
   v
Buy WALBT collateral with BEUR
   |
   v
~113.8M WALBT acquired