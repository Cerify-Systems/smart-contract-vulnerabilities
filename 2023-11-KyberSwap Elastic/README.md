# KyberSwap Elastic (2023) – Mathematical / Rounding Logic Vulnerability

## Overview

This repository contains a focused study of the **KyberSwap Elastic Exploit (November 2023)**, one of the most significant DeFi security incidents caused by a **mathematical rounding error and business logic flaw** rather than traditional vulnerabilities such as reentrancy or access control issues.

The exploit allowed attackers to manipulate swap calculations and create an inconsistent pool state, resulting in losses exceeding **$48 million** across multiple liquidity pools.

---

## Vulnerability Classification

| Category                     | Type                              |
| ---------------------------- | --------------------------------- |
| Smart Contract Vulnerability | Mathematical Precision Error      |
| Subcategory                  | Rounding Logic Vulnerability      |
| Impact                       | Liquidity Accounting Manipulation |
| Severity                     | Critical                          |
| Exploited In                 | November 2023                     |
| Estimated Loss               | ~$48M+                            |

---

## Case Study Summary

KyberSwap Elastic uses a concentrated liquidity model similar to Uniswap V3, where liquidity is distributed across predefined price ranges known as **ticks**.

During swap execution, the protocol calculates:

* Current liquidity
* Current price
* Target price
* Tick transitions

A rounding issue inside the swap computation logic caused the protocol to incorrectly determine whether a swap had crossed a tick boundary.

As a result:

```text
Price State      → Updated
Liquidity State  → Not Updated
```

This created an invalid pool state where liquidity accounting became inconsistent with the actual market position.

Attackers leveraged this discrepancy to perform swaps that extracted significantly more value than should have been possible.

---

## Key File for Analysis

### `contracts/libraries/SwapMath.sol`

This is the primary file associated with the vulnerability.

The critical logic resides inside:

```solidity
computeSwapStep(...)
```

This function is responsible for:

* Processing swap calculations
* Computing next pool price
* Determining tick crossings
* Updating liquidity states

The exploit originated from incorrect rounding behavior during these calculations.

---


## Root Cause

The protocol assumed that a swap would not cross the next tick boundary under certain conditions.

However, due to rounding behavior during liquidity and price calculations:

```text
Expected:
nextPrice < targetPrice

Actual:
nextPrice > targetPrice
```

This violated an internal invariant of the protocol.

Consequently:

```text
Tick Position     → Updated
Liquidity Amount  → Unchanged
```

This mismatch enabled attackers to manipulate liquidity accounting and extract assets from affected pools.

---

## Vulnerability Flow

```text
Attacker
    │
    ▼
Manipulates Pool State
    │
    ▼
Crafted Swap Execution
    │
    ▼
Rounding Error Triggered
    │
    ▼
Tick Crossed Incorrectly
    │
    ▼
Liquidity Not Updated
    │
    ▼
Invalid Pool State Created
    │
    ▼
Asset Extraction
```

---

## Why This Vulnerability Matters

This incident demonstrates that:

* Smart contracts can be vulnerable even when there are no coding mistakes in the traditional sense.
* Financial invariants are as important as Solidity syntax correctness.
* Small rounding discrepancies can escalate into multi-million-dollar exploits.
* Complex AMM protocols require rigorous mathematical verification in addition to standard security audits.

---

## Learning Outcomes

After studying this case, readers should understand:

* Concentrated liquidity AMM architecture
* Tick-based liquidity systems
* Swap execution mechanics
* Mathematical precision risks in Solidity
* Rounding-related business logic vulnerabilities
* Importance of invariant validation in DeFi protocols

---

## References

* KyberSwap Post-Mortem Report
* BlockSec Exploit Analysis
* Phalcon Security Investigation
* KyberSwap Elastic Smart Contract Repository
