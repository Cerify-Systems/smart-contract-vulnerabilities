# Official Analysis

## Alpha Homora V2 Exploit

Date:

13 February 2021

The Alpha Homora V2 protocol was exploited through its integration with
C.R.E.A.M. V2 Iron Bank.

The exploit resulted in approximately $37.5–38 million of additional debt.

## Conditions Required

Alpha identified the following conditions:

1. HomoraBankV2 contained an unreleased sUSD lending pool.
2. The sUSD pool had no liquidity.
3. A rounding issue existed in the borrow calculation.
4. `resolveReserve()` could be called by anyone.
5. `resolveReserve()` could increase total debt without increasing total
   debt share.
6. HomoraBankV2 accepted custom spells.

## Attack

The attacker manipulated the sUSD debt accounting and repeatedly borrowed
assets using the resulting distorted debt-share state.

The attacker then used Alpha Homora's protocol-to-protocol credit relationship
with C.R.E.A.M. V2 Iron Bank to extract ETH and stablecoins.

## Impact

The additional debt was between:

Alpha Homora V2

and:

C.R.E.A.M. V2 Iron Bank

Alpha stated that user funds were not directly responsible for the debt.

## Response

Alpha paused borrowing and subsequently changed the permission model.

The remediation included:

- whitelisted spells,
- governance-only `resolveReserve()`,
- restricted execution,
- removal of unreleased borrowing assets.