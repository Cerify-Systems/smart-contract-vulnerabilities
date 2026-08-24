# Uranium Finance Exploit (April 2021)

## Overview

Uranium Finance was a decentralized exchange (DEX) built on the Binance Smart Chain (now BNB Smart Chain). It was a fork of the Uniswap V2 automated market maker (AMM) protocol and provided users with token swaps, liquidity pools, and yield farming.

On **28 April 2021**, Uranium Finance suffered one of the largest DeFi exploits on BNB Smart Chain after a critical logic error was introduced during the migration from **v2** to **v2.1** of its smart contracts. The vulnerability allowed an attacker to drain approximately **$50–57 million USD** worth of assets from multiple liquidity pools.
Unlike many DeFi exploits involving flash loans or oracle manipulation, this attack resulted from a simple arithmetic inconsistency in the protocol's `swap()` function. A single incorrect constant in the invariant check completely broke the security guarantees of the AMM, allowing an attacker to receive significantly more tokens than they were entitled to.


## Incident Information

| Field                   | Value                                                            |
| ----------------------- | ---------------------------------------------------------------- |
| **Protocol**            | Uranium Finance                                                  |
| **Blockchain**          | Binance Smart Chain (BNB Chain)                                  |
| **Attack Date**         | 28 April 2021                                                    |
| **Loss**                | Approximately $50–57.2 Million                                   |
| **Attack Type**         | Smart Contract Logic Error                                       |
| **Vulnerable Contract** | `UraniumPair.sol`                                                |
| **Root Cause**          | Incorrect constant used in constant-product invariant validation |


## Background

Uranium Finance was developed as a fork of Uniswap V2 with modified trading fees. During development, the protocol changed several mathematical constants used for fee calculations. In the original Uniswap implementation, swap calculations use the constant **1000** to account for trading fees.
Uranium Finance modified these calculations to use **10000**, but one critical validation check inside the `swap()` function was accidentally left unchanged.
This inconsistency weakened the invariant responsible for ensuring that liquidity pools could never lose value during swaps

## Root Cause

The vulnerability originated from an incorrect implementation of the constant-product invariant.

The protocol correctly updated:

* fee calculations
* adjusted balances

to use:

```text
10000
```

However, the final invariant verification still used:

```text
1000²
```

instead of

```text
10000²
```

Because the validation threshold became 100× smaller than intended, the contract accepted swaps that should have been rejected. As a result, an attacker could provide only a tiny amount of input tokens while receiving nearly the entire reserve of the output token.


## Attack Overview

The attacker interacted directly with Uranium Finance's pair contracts.

The exploit did not require:

* Flash loans
* Oracle manipulation
* Governance attacks
* Private keys
* Reentrancy

Instead, the attacker repeatedly exploited the incorrect mathematical validation in the AMM.The attack drained liquidity from numerous pools, including assets such as:

* WBNB
* BUSD
* USDT
* ETH
* BTC
* ADA
* DOT
The stolen assets were later moved across chains and portions were laundered through privacy tools.


## Timeline

**16 April 2021**

* Uranium Finance migrated to its Version 2 contracts.
* The migration introduced the arithmetic bug.

**28 April 2021**

* The attacker exploited the vulnerable pair contracts.
* Multiple liquidity pools were drained.
* Uranium Finance suspended operations and warned users to withdraw liquidity.

**29 April 2021**

* The project published a post-mortem acknowledging the vulnerability.
* The team explained that the issue had been discovered internally shortly before the attack, but a fix had not yet been deployed.


## Lessons Learned

The Uranium Finance exploit demonstrates several important smart contract security lessons:

* Small arithmetic changes can invalidate fundamental protocol assumptions.
* Forking audited protocols does not guarantee security after modifications.
* Every mathematical constant should be reviewed when changing protocol economics.
* Automated testing should verify invariants after every code modification.
* Formal verification and invariant testing can detect logic inconsistencies before deployment.


## Repository Structure

```text
2021-04-UraniumFinance/
│
├── contracts/
│   └── UraniumPair.sol
│
├── exploit.md
├── fix.md
├── summary.md
├── README.md
│
└── writeups/
    └── sources.md
```