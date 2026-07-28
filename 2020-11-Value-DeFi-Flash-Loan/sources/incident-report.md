# Incident Report

## Incident

**Value DeFi Flash Loan Attack (2020)**

## Date

November 14, 2020

## Loss

Approximately **$6 million**

## Affected Protocol

Value DeFi – MultiStablesVault

## Attack Summary

On November 14, 2020, Value DeFi suffered a flash loan attack targeting its MultiStablesVault. The attacker borrowed a large amount of capital using an Aave flash loan and manipulated stablecoin prices within Curve Finance.

The vault relied on conversion rates derived from these manipulated prices to determine the value of deposits. As a result, the protocol minted significantly more vault shares than the attacker was entitled to receive.

The attacker then redeemed these inflated shares for legitimate assets, repaid the flash loan within the same transaction, and kept the remaining funds as profit.

## Root Cause

The protocol trusted externally derived conversion rates that were based on manipulable Curve Finance liquidity pools.

No Solidity language bug such as reentrancy or integer overflow was exploited. Instead, the attack abused incorrect economic assumptions within the protocol.

## Impact

- Approximately $6 million stolen.
- Incorrect vault share minting.
- Financial loss for protocol users.

## Attack Type

- Flash Loan Attack
- Oracle / Price Manipulation
- Business Logic Vulnerability