# Deus Finance — March 2022 Oracle Manipulation Incident

## Incident Overview

On March 15, 2022, Deus Finance on Fantom suffered a flash-loan-assisted oracle manipulation attack that resulted in approximately $3 million in losses. The affected component was the DEI lending system. The attacker manipulated the USDC/DEI market used by the protocol's price oracle, causing the protocol to value collateral incorrectly and triggering liquidations of positions that should not have been liquidated under an honest price.

The central technical problem was the use of a spot market-derived price for collateral valuation. The lending contract trusted `Oracle.getPrice()` when deciding whether a position was solvent. The oracle ultimately depended on the USDC/DEI pair and could therefore be influenced by temporary liquidity changes created inside the same transaction.

## Primary Vulnerable Contracts

The principal exploit-relevant deployment was `DeiLenderSolidex` at `0xeC1Fc57249CEa005fC16b2980470504806fcA20d`. The associated Oracle deployment identified in contemporary incident analysis was `0x5CEB2b0308a7f21CcC0915DB29fa5095bEAdb48D`.

The Solidity files in `contracts/` contain the vulnerable logic reconstructed from the deployed contract's reported implementation. The most important functions are `liquidate()`, `isSolvent()`, `getPrice()` and `getOnChainPrice()`.

## Vulnerability Class

The incident is classified as flash-loan-assisted oracle manipulation and spot-price manipulation. The deeper issue was the assumption that a DEX pool could safely serve as a reliable collateral price source while its reserves were freely movable during a transaction.

## Impact

Approximately $3 million in value was extracted in the March 15 incident. The manipulated price caused affected lending positions to be treated as insolvent, allowing the attacker to liquidate them and obtain their underlying assets.

## Repository Structure

`contracts/DeiLenderSolidex_vulnerable.sol` contains the lending-side logic that consumed the manipulated price. `contracts/Oracle_vulnerable.sol` contains the price calculation logic. `summary.md` provides the detailed incident summary. `exploit.md` explains the vulnerable logic and exploitation sequence. `fix.md` discusses the remediation and secure design principles. `writeups/aftermath.md` covers the protocol response and lessons learned.

This repository intentionally does not include transaction lists or a separate attack-analysis file.
