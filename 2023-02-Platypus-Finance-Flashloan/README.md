# Platypus Finance Flash Loan Attack — February 2023

## Incident

- Date: 16 February 2023
- Network: Avalanche
- Protocol: Platypus Finance
- Affected System: USP stablecoin collateral mechanism
- Primary Vulnerable Contract: MasterPlatypusV4
- Related Contract: PlatypusTreasure
- Primary Attack Loss: Approximately $8.5M
- Total February Incident Losses: Approximately $9.1M

## Summary

On 16 February 2023, Platypus Finance was exploited through a logic error
in the USP collateral system.

The attacker obtained 44 million USDC through an Aave V3 flash loan.

The USDC was deposited into Platypus and converted into LP-USDC tokens.

The LP-USDC tokens were then deposited into MasterPlatypusV4 and used as
collateral to borrow approximately 41.79 million USP from PlatypusTreasure.

The attacker then called:

    emergencyWithdraw()

The vulnerability was that MasterPlatypusV4 checked whether the position
was solvent BEFORE removing the LP collateral.

The check therefore still saw the collateral.

The position passed the solvency check.

MasterPlatypusV4 then returned the LP tokens to the attacker while leaving
the USP debt outstanding.

The attacker withdrew the original USDC and swapped portions of the USP
for other stablecoins.

## Attack Flow

```text
Aave V3
   |
   | 44M USDC
   v
Attacker
   |
   v
Platypus Pool
   |
   | LP-USDC
   v
MasterPlatypusV4
   |
   | collateral
   v
PlatypusTreasure
   |
   | ~41.79M USP
   v
Attacker
   |
   | emergencyWithdraw()
   v
MasterPlatypusV4
   |
   | isSolvent() = true
   |
   | collateral returned
   v
Attacker
   |
   +---- ~44M USDC
   |
   +---- ~41.79M USP debt
   |
   v
USP → stablecoin swaps
   |
   v
Aave flash loan repaid