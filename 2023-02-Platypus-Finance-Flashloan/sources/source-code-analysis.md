# Source Code Analysis — Platypus Finance

## Incident

Date:

16 February 2023

Protocol:

Platypus Finance

Chain:

Avalanche

Affected System:

USP stablecoin collateral mechanism

Primary Vulnerable Contract:

MasterPlatypusV4.sol

Related Contract:

PlatypusTreasure.sol

Estimated Loss:

Approximately $8.5 million for the primary attack.

## 1. MasterPlatypusV4

MasterPlatypusV4 is responsible for managing LP-token staking positions.

Users can deposit LP tokens and later withdraw them.

The contract also integrates with PlatypusTreasure because the staked
LP tokens can be used as collateral for borrowing USP.

## 2. emergencyWithdraw()

The vulnerable function was:

    emergencyWithdraw(uint256 _pid)

The function was intended to allow users to withdraw their LP tokens
without receiving rewards.

The relevant execution order was:

    1. Check solvency.
    2. Transfer LP tokens.
    3. Set user.amount to zero.

This order was unsafe.

## 3. Solvency Check

Before withdrawing the LP tokens, MasterPlatypusV4 called:

    platypusTreasure.isSolvent()

The function returned:

    bool isSolvent
    uint256 debtAmount

MasterPlatypusV4 only used the boolean value.

If:

    isSolvent == true

the emergency withdrawal was allowed.

## 4. What isSolvent Means

PlatypusTreasure considered a position solvent when:

    debtAmount <= borrowLimitUSP

This means the collateral was sufficient to cover the outstanding debt.

However, this does NOT mean that all collateral can safely be withdrawn
while the debt remains outstanding.

That distinction was the key design failure.

## 5. Attacker's Position

The attacker created approximately:

    44,000,000 USDC

of collateral.

The USDC was converted into LP-USDC tokens.

The LP-USDC tokens were deposited into MasterPlatypusV4.

The attacker then borrowed approximately:

    41,794,533 USP

from PlatypusTreasure.

The position was still considered solvent.

## 6. Exploitation

The attacker called:

    emergencyWithdraw()

MasterPlatypusV4 first called:

    isSolvent()

At this point the LP tokens were still recorded as collateral.

Therefore the solvency check returned:

    true

The contract then transferred the LP tokens back to the attacker.

Only after transferring the collateral did it execute:

    user.amount = 0

## 7. Result

The attacker therefore ended with:

    Collateral = 0
    Debt       ≈ 41.79M USP

The debt was no longer backed by the collateral that had originally
enabled the borrowing.

This created bad debt for the protocol.

## 8. Recovery of USDC

Because the attacker had recovered the LP-USDC tokens, the attacker
could withdraw the original USDC liquidity from the Platypus Pool.

Approximately:

    44M USDC

was recovered.

The attacker then used the borrowed USP to obtain other stablecoins.

## 9. Stablecoin Swaps

The attacker swapped portions of the USP into:

- USDC
- USDC.e
- USDT
- USDT.e
- BUSD
- DAI.e

The attacker did not need to repay the USP debt because the collateral
had already been withdrawn.

## 10. Flash Loan Repayment

The recovered USDC was used to repay the Aave V3 flash loan.

The remaining assets represented the economic gain from the exploit.

## 11. Root Cause

The root cause was an incorrect ordering of state validation and state
changes.

The contract checked:

    Is the position solvent?

before performing:

    Remove all collateral.

The correct security invariant should have been:

    After withdrawal:
        remaining collateral must still cover the debt

or, for a full emergency withdrawal:

    outstanding debt must be zero.

## 12. Comparison With withdraw()

The normal withdraw() function did not have the same vulnerability.

It updated the user's stake position before performing the relevant
solvency validation.

Therefore the solvency calculation considered the reduced collateral.

The emergencyWithdraw() implementation used the opposite order.

## 13. Recommended Fix

One possible fix is to update the user's collateral amount before
performing the solvency check.

Conceptually:

    user.amount = 0;

    check solvency;

    transfer collateral;

However, a safer design for emergency withdrawal with active debt is
to explicitly require that the debt is zero.

For example:

    require(debtAmount == 0);

The exact implementation should preserve the protocol's collateral
and debt invariants.

## 14. Vulnerability Classification

Primary:

- Business logic error
- Incorrect solvency validation
- Incorrect state-update ordering
- Collateral withdrawal with outstanding debt

Secondary:

- Flash-loan-assisted attack
- Bad-debt creation
- Cross-contract accounting dependency

## 15. Security Lesson

A solvency check must evaluate the state that will exist AFTER the
requested operation.

A user can be solvent before withdrawing collateral but completely
insolvent after withdrawing that collateral.

Therefore:

    solvent before withdrawal
        !=
    safe to withdraw all collateral

This distinction must be enforced explicitly in lending protocols.