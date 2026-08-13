# Official / Primary Analysis

## Akropolis Incident

Date:

12 November 2020

Protocol:

Akropolis / Delphi

Affected Pools:

- YCurve
- sUSD

Loss:

2,030,841.0177 DAI

## Root Cause

The Akropolis SavingsModule had two important weaknesses:

1. Deposited token addresses were not sufficiently validated.
2. The deposit logic did not have effective reentrancy protection.

The attacker created a malicious ERC-20-like token.

When Akropolis called the token's `transferFrom()` function, the malicious
token re-entered `SavingsModule.deposit()` using real DAI.

The nested DAI deposit changed the protocol balance while the original
deposit was still executing.

Because pool tokens were calculated using the balance difference before
and after the protocol deposit, the same DAI value could be counted twice.

## Attack Result

The attacker repeatedly performed this operation and drained:

2,030,841.0177 DAI

from the affected YCurve and sUSD pools.

A dYdX flash loan was used at the beginning of the attack to provide the
initial capital.