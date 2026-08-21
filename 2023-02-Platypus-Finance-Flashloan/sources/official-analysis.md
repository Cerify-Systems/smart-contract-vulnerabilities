# Official Analysis — Platypus Finance

## Incident

Date:

16 February 2023

Protocol:

Platypus Finance

Network:

Avalanche

Affected System:

USP stablecoin

## Incident Summary

Platypus Finance suffered an exploitation of its USP collateral system.

The root cause was a logic error in the solvency check mechanism.

The vulnerable integration involved:

    MasterPlatypusV4

and:

    PlatypusTreasure

## Root Cause

The `emergencyWithdraw()` function of MasterPlatypusV4 checked whether
the user's position was solvent before removing the user's collateral.

As a result, a user could:

1. Deposit LP tokens.
2. Use the LP tokens as collateral.
3. Borrow USP.
4. Pass the solvency check.
5. Withdraw the collateral.
6. Keep the outstanding USP debt.

This resulted in unsecured debt.

## Main Attack

The attacker obtained:

    44,000,000 USDC

through an Aave V3 flash loan.

The USDC was deposited into Platypus and converted into LP-USDC.

The LP-USDC was deposited into MasterPlatypusV4.

The attacker then borrowed approximately:

    41,794,533 USP

The attacker called:

    emergencyWithdraw()

The solvency check passed because the collateral was still included in
the position.

The LP tokens were then returned to the attacker.

The attacker withdrew the original USDC and swapped USP into other
stablecoins.

## Impact

The primary attack resulted in approximately:

    $8.5 million

of extracted value.

Platypus later reported that three related attacks resulted in a total
loss of approximately:

    $9.1 million.

## Remediation

The protocol needed to ensure that collateral cannot be withdrawn while
the associated debt remains outstanding.

Possible protections include:

- updating collateral state before solvency validation,
- checking outstanding debt directly,
- preventing emergency withdrawal when debt exists,
- adding invariant-based testing,
- reviewing all external integrations after protocol upgrades.