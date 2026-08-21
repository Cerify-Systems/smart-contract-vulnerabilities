# Euler Finance (2023) — Business Logic Vulnerability

## Overview

**Protocol:** Euler Finance
**Incident Date:** March 13, 2023
**Vulnerability Type:** Business Logic Flaw (Missing Health Check)
**Estimated Loss:** ~$197 Million
**Blockchain:** Ethereum

Euler Finance suffered one of the largest DeFi exploits in 2023 due to a business logic vulnerability in its lending protocol. Unlike traditional smart contract vulnerabilities such as reentrancy or integer overflows, this exploit originated from an unintended interaction between protocol features. Specifically, a newly introduced function allowed users to reduce their collateral without verifying whether their borrowing position remained sufficiently collateralized.

The attacker leveraged this flaw to create an undercollateralized position and then profit from the protocol's liquidation mechanism, resulting in approximately $197 million in losses.

---

# Vulnerability Summary

The root cause of the exploit was the absence of a post-operation liquidity check within the `donateToReserves()` function.

The function was designed to allow users to donate their eTokens (collateral tokens) to Euler's reserve pool. However, when a user donated collateral, the protocol reduced the user's collateral balance without validating whether the account still satisfied collateral requirements for outstanding debt.

As a result:

1. A borrower could intentionally decrease their collateral.
2. The account could become severely undercollateralized.
3. The position would become eligible for liquidation.
4. The attacker could liquidate the position using another controlled account.
5. The liquidation reward exceeded the value lost through the donation process.

This enabled profitable self-liquidation and allowed the attacker to extract funds from the protocol.

---

# Attack Flow

```text
Flash Loan
    │
    ▼
Deposit Assets into Euler
    │
    ▼
Borrow Against Collateral
    │
    ▼
Call donateToReserves()
    │
    ▼
Collateral Reduced
(No Health Check Performed)
    │
    ▼
Position Becomes Undercollateralized
    │
    ▼
Self-Liquidation Using Another Account
    │
    ▼
Receive Liquidation Bonus
    │
    ▼
Protocol Loss
```

---

# Root Cause Analysis

The vulnerability was not caused by incorrect arithmetic, faulty access control, or a Solidity-specific issue.

The primary issue was:

> The protocol allowed collateral reduction without validating account solvency after the operation.

In lending protocols, any action that decreases collateral should trigger a health-factor or liquidity verification. The absence of such validation enabled attackers to create positions that should never have been permitted by the protocol.

---

# Affected Components

## 1. EToken.sol

**Repository Path**

```text
contracts/modules/EToken.sol
```

### Relevant Function

```solidity
donateToReserves()
```

### Why It Matters

This function is the core location of the vulnerability.

Its purpose is to transfer a user's eTokens into protocol reserves. During execution, the user's collateral balance is reduced and reserve balances are increased.

The issue is that the function did not perform a post-operation liquidity check to verify that the account remained sufficiently collateralized after the collateral reduction.

### Presentation Focus

When explaining this file:

* Explain what eTokens represent.
* Explain how collateral is reduced.
* Highlight that collateral reduction occurs successfully.
* Show that no account health verification follows the operation.
* Connect this omission to the creation of an undercollateralized position.

---

## 2. Liquidation.sol

**Repository Path**

```text
contracts/modules/Liquidation.sol
```

### Relevant Functions

```solidity
liquidate()
```

and associated liquidation-discount calculations.

### Why It Matters

This file was not vulnerable by itself.

However, it contains the liquidation mechanism that the attacker exploited after creating an unhealthy position through `donateToReserves()`.

The liquidation system behaved exactly as intended, rewarding liquidators for resolving risky positions. The attacker simply manipulated the protocol into creating such a position and then collected the liquidation reward through a controlled account.

---

# Repository

Repository:

```text
https://github.com/euler-xyz/euler-contracts
```

---

# Security Lessons Learned

1. Every collateral-reducing operation must trigger a solvency check.
2. New protocol features should be analyzed for interactions with existing mechanisms.
3. Liquidation incentives can become attack vectors when account health validation is missing.
4. Business logic vulnerabilities can be as severe as traditional smart contract bugs.
5. Comprehensive security reviews must include economic and protocol-level attack scenarios.

---

# Key Takeaway

The Euler Finance exploit demonstrates that smart contracts can be technically correct while still being vulnerable due to flawed protocol logic. The `donateToReserves()` function allowed collateral reduction without verifying account health, enabling attackers to create liquidatable positions and exploit the protocol's liquidation incentives for profit. The vulnerability ultimately arose from a missing business-rule validation rather than a flaw in Solidity itself.
