# Harvest Finance (October 2020) — Price Oracle Manipulation Vulnerability

## Overview

On **October 26, 2020**, the DeFi yield-aggregator protocol **Harvest Finance** was exploited via a flash-loan-driven price oracle manipulation attack. The attacker used flash loans to distort the exchange rate on a Curve Finance liquidity pool, tricking Harvest's vault contracts into minting shares at an incorrect price. The attack drained approximately **$34 million** from the `fUSDC` and `fUSDT` vaults in a matter of minutes.

## About Harvest Finance

Harvest Finance was a yield-farming aggregator protocol that automatically moved depositors' funds across various DeFi lending and liquidity protocols (such as Curve Finance) to optimize yield. Users deposited stablecoins (e.g., USDC, USDT) into Harvest's vaults and received vault-share tokens (e.g., `fUSDC`, `fUSDT`) in return, representing their proportional claim on the vault's underlying assets — which grew in value over time as the strategy earned yield. The project's native governance/reward token was FARM.

## The Vulnerability

**Category:** Price Oracle Manipulation (Flash Loan Attack)

Harvest's vault contracts priced their shares (`fUSDC`/`fUSDT`) using the **live, spot-price value** of the vault's underlying position in a Curve Finance liquidity pool. This price was read directly on-chain, in real time, with no protection against short-term manipulation.

### Attack sequence

1. The attacker took out large flash loans of USDC and USDT (via Uniswap V2).
2. Using Curve's `exchange_underlying` function, the attacker swapped a large amount of USDT for USDC, which temporarily and artificially skewed the pool's internal price ratio.
3. While the pool was skewed, the attacker deposited into Harvest's vault. Because the vault's share-price calculation relied on the distorted pool price, the deposit minted far more vault shares than it should have.
4. The attacker reversed the Curve swap, restoring the pool's price ratio and, with it, the vault's share price.
5. The attacker redeemed the over-minted shares for a much larger amount of underlying stablecoins than originally deposited.
6. The flash loans were repaid, and the profit was pocketed — all within a single atomic transaction. This was repeated multiple times to maximize extraction.

## Root Cause

The underlying root cause was **not a classic coding bug** (e.g., reentrancy, overflow, or access control) — it was a **flawed price oracle design**:

- The vault used an **unprotected, single-block spot price** derived directly from Curve pool reserves as its source of truth for computing share value.
- There was **no time-weighted average price (TWAP)**, no minimum elapsed time between price reads, and **no sanity/deviation check** to detect whether the pool was in an abnormal, manipulated state.
- Because flash loans allow anyone to command large amounts of capital risk-free within a single transaction, any protocol pricing assets off an instantaneously manipulable on-chain pool is exposed to this style of attack.
- The deposit and withdrawal logic trusted this manipulable price completely, allowing shares to be minted and redeemed at two different (attacker-controlled) prices within the same transaction.

This pattern — flash loan → skew AMM pool price → exploit protocol that trusts that spot price → reverse the skew → repay loan — became a template for numerous later DeFi exploits.

## Vault.sol — Contract Associated with the Vulnerability

The vulnerability lived in Harvest's core vault contract, `Vault.sol`. Three functions were central to the exploit:

### 1. `underlyingBalanceWithInvestment()`
Computes the vault's total underlying asset value by combining the vault's idle balance with the value currently invested in the strategy (which included the vault's Curve LP position). This function pulled a **live, spot-price** figure for the invested balance — the value that turned out to be manipulable within a single transaction.

### 2. `getPricePerFullShare()`
Calculates the value of one vault share by dividing the vault's total underlying balance (from the function above) by the total share supply. Since its input was manipulable, this "price per share" could be temporarily pushed up or down by an attacker before being read by other functions.

### 3. `_deposit()`
Mints new vault shares to a depositor using the formula:
```
toMint = amount * underlyingUnit() / getPricePerFullShare()
```
Because `getPricePerFullShare()` could be manipulated to be artificially low, this function would mint an inflated number of shares for a given deposit amount — the direct mechanism the attacker exploited to gain oversized share allocations, later redeemed via `withdraw()` at a corrected (higher) price for profit.

> **Post-hack fix:** The current version of `_deposit()` includes an added guard, `require(IStrategy(strategy()).depositArbCheck(), "Too much arb");`, which checks Curve pool balance ratios before allowing a deposit and rejects deposits made while the pool is in an abnormal/skewed state — the manipulation-detection safeguard that was missing at the time of the attack.

## Reference

**Official Harvest Finance contracts repository (source of `Vault.sol` referenced above):**
https://github.com/harvest-finance/harvest/blob/master/contracts/Vault.sol

Full repository: https://github.com/harvest-finance/harvest

### Additional resources
- Proof-of-concept exploit reconstruction: https://github.com/ethereumvex/Harvest-exploit
- Proof-of-concept exploit reproduction: https://github.com/abdulsamijay/Defi-Hack-Analysis-POC/tree/master/src/harvest-finance
- Original exploit transaction (Etherscan): https://etherscan.io/tx/0x9d093325272701d63fdafb0af2d89c7e23eaf18be1a51c580d9bce89987a2dc1