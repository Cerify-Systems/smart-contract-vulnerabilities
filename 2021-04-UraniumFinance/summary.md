# Summary

## Overview

The Uranium Finance exploit was a major decentralized finance (DeFi) security incident that occurred on **28 April 2021** on the Binance Smart Chain (now BNB Chain). The attack exploited a critical logic error in the protocol's `UraniumPair.sol` smart contract, allowing an attacker to drain approximately **$50–57 million USD** worth of assets from multiple liquidity pools.

Unlike exploits involving flash loans, oracle manipulation, or reentrancy, this incident resulted from an arithmetic inconsistency introduced during a protocol upgrade. A single incorrect constant in the `swap()` function weakened the Automated Market Maker (AMM) invariant, allowing swaps that should have been rejected.


## Root Cause

Uranium Finance was forked from Uniswap V2 and modified its trading fee calculations by changing the scaling factor from **1000** to **10000**. While the adjusted token balances used the new value, the constant-product invariant (`x × y = k`) continued to use the original multiplier (`1000²`) instead of `10000²`.

This mismatch reduced the required invariant threshold by a factor of 100, enabling attackers to exchange a negligible amount of tokens for nearly the entire reserves of a liquidity pool.


## Attack

The attacker interacted directly with the vulnerable `swap()` function in the `UraniumPair` contract. By exploiting the weakened invariant check, they repeatedly performed swaps that transferred significantly more assets than permitted.

The exploit affected several liquidity pools containing assets such as:
- WBNB
- BUSD
- USDT
- ETH
- BTC
- ADA
- DOT

After draining the pools, the attacker consolidated the stolen assets into their own wallets and later moved portions of the funds across chains.

---

## Impact

- **Attack Date:** 28 April 2021
- **Protocol:** Uranium Finance
- **Blockchain:** Binance Smart Chain (BNB Chain)
- **Estimated Loss:** Approximately **$50–57 million USD**
- **Vulnerable Contract:** `UraniumPair.sol`

The exploit resulted in one of the largest losses on BNB Chain at the time. Most liquidity pools were drained, trading effectively stopped, and Uranium Finance was forced to suspend operations. The protocol never fully recovered from the incident.

## Resolution

The vulnerability was traced to an incorrect constant used in the invariant validation inside the `swap()` function. Correcting the invariant to use the same scaling factor as the fee calculations (`10000²`) restores the intended security properties of the AMM.

The incident also highlighted the importance of:

- Consistent mathematical implementations
- Comprehensive regression testing
- Property-based and invariant testing
- Independent security audits
- Formal verification of critical financial logic
