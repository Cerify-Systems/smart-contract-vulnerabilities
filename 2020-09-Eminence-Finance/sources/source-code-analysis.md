# Source Code Analysis — Eminence Finance

## Incident

Date:

29 September 2020

Protocol:

Eminence Finance

Chain:

Ethereum

Primary asset:

EMN

Loss:

Approximately $15 million

Returned:

Approximately $8 million

## Vulnerability

The exploit resulted from a flaw in the interaction between the EMN
bonding curve and the secondary Eminence currencies.

The system allowed users to:

1. Mint EMN using DAI.
2. Use EMN to purchase secondary Eminence currencies.
3. Burn EMN as part of that purchase.
4. Redeem the remaining EMN for DAI.

The bonding-curve accounting did not safely handle this interaction.

## 1. EMN Bonding Curve

The EMN contract inherited the `ContinuousToken` logic.

The contract maintained:

    totalSupply()
    reserveBalance
    reserveRatio

The bonding curve calculated the amount of EMN minted or the amount
of DAI returned when EMN was burned.

## 2. Minting EMN

The attacker first obtained a large amount of DAI through a flash loan.

The DAI was supplied to the EMN contract.

The bonding curve calculated the amount of EMN to mint.

Conceptually:

    DAI
     ↓
    EMN

The EMN supply and reserve balance were updated.

## 3. Secondary Currency

Eminence also contained secondary currencies such as eAAVE.

These currencies used EMN as their underlying reserve asset.

When the attacker purchased a secondary currency, EMN was transferred
to the secondary currency contract and burned.

Therefore:

    EMN
     ↓
    secondary currency

The EMN supply decreased.

## 4. Accounting Problem

The important issue was the relationship between:

    EMN total supply
    EMN reserve balance
    secondary-token supply
    bonding-curve calculations

Burning EMN through the secondary currency mechanism changed the EMN
supply without maintaining the same economic relationship between the
EMN supply and the reserve.

This changed the bonding-curve exchange rate.

## 5. Exploit Cycle

The attacker repeatedly performed:

    Flash-loaned DAI
          ↓
    Mint EMN
          ↓
    Buy secondary currency
          ↓
    Burn EMN
          ↓
    Sell remaining EMN
          ↓
    Receive DAI
          ↓
    Repeat

The cycle generated more DAI than was initially required to perform
the operation.

## 6. Why the Cycle Was Profitable

The bonding curve assumed that its reserve and supply represented the
economic state of EMN.

However, the secondary-currency mechanism could burn EMN and alter the
supply side of the curve.

The attacker exploited this mismatch.

The result was that EMN could be redeemed for more DAI than the
economic system should have allowed.

## 7. Flash Loan

The attacker used a large flash loan to provide the temporary capital
required to perform the complete sequence atomically.

The flash loan itself was not the underlying vulnerability.

It amplified the bonding-curve accounting flaw.

## 8. Repetition

The attacker repeated the cycle within the same transaction.

Because the flash loan had to be repaid before the transaction ended,
the attacker could not simply rely on holding the borrowed funds.

Instead, the bonding-curve imbalance generated enough DAI to repay
the flash loan and leave excess funds.

## 9. Final Result

The attacker drained approximately:

$15 million

from the Eminence contracts.

Approximately:

$8 million

was later returned to a Yearn-associated deployer address.

## Root Cause

The root cause was an unsafe economic/accounting relationship between:

- EMN's bonding curve
- EMN reserve balance
- EMN total supply
- secondary Eminence currencies

The protocol did not maintain a strong invariant between the underlying
reserve and the supply changes caused by secondary-token operations.

## Vulnerability Classification

Primary:

- Bonding curve accounting flaw
- Economic invariant violation
- Cross-contract token accounting issue

Secondary:

- Flash-loan-assisted exploit
- Unchecked composability between token systems
- Unaudited production deployment

## Security Lessons

1. Bonding curves must maintain strict supply/reserve invariants.
2. Burning an underlying token through another protocol component must
   correctly update all dependent accounting.
3. Economic invariants should be tested across multiple interacting
   contracts.
4. Flash-loan scenarios should be included in security testing.
5. Functional contracts should not be deployed to mainnet before they
   are tested and audited.
6. Secondary tokens using an underlying reserve asset must not be able
   to create an accounting imbalance.

## Key Functions

Relevant functions include:

    buy()
    sell()
    calculateContinuousMintReturn()
    calculateContinuousBurnReturn()
    _continuousMint()
    _continuousBurn()

The deployed EMN source shows that `_continuousMint()` increases
`reserveBalance`, while `_continuousBurn()` calculates a reimbursement
through the bonding curve and decreases `reserveBalance`.