# BurgerSwap Hack (2021) — Reentrancy & AMM Invariant Manipulation

## Overview

BurgerSwap was a decentralized exchange (DEX) built on Binance Smart Chain (BSC) and inspired by the Uniswap V2 architecture. In May 2021, the protocol suffered a major exploit that resulted in approximately **$7.2 million** being stolen from multiple liquidity pools.

The attacker leveraged a combination of **flash loans**, **malicious token contracts**, and weaknesses in BurgerSwap's customized swap implementation to manipulate pool reserves and extract funds. The incident demonstrated how small modifications to proven AMM logic can introduce severe vulnerabilities.

---

## Incident Summary

| Field                  | Value                               |
| ---------------------- | ----------------------------------- |
| Protocol               | BurgerSwap                          |
| Date                   | May 2021                            |
| Blockchain             | Binance Smart Chain (BSC)           |
| Estimated Loss         | ~$7.2 Million                       |
| Vulnerability Category | Reentrancy / Invariant Manipulation |
| Attack Vector          | Flash Loan                          |
| Severity               | Critical                            |

---

## Background

Automated Market Makers (AMMs) such as Uniswap and BurgerSwap maintain liquidity pools using the constant-product formula:

```text
x * y = k
```

Where:

* `x` = reserve of token A
* `y` = reserve of token B
* `k` = constant product

The protocol assumes that after every valid swap operation, the value of `k` should remain constant or increase due to fees.

BurgerSwap introduced custom modifications to the original AMM implementation. These changes weakened some of the assumptions that protect liquidity pools from manipulation.

---

## Root Cause

The vulnerability existed within the swap execution logic implemented inside:

```text
contracts/DemaxPlatform.sol
```

Specifically, the protocol relied on reserve values that could be manipulated during complex swap operations involving attacker-controlled tokens.

The attacker was able to:

1. Obtain large capital through a flash loan.
2. Deploy a malicious token contract.
3. Create liquidity pairs involving the malicious token.
4. Trigger swap operations through BurgerSwap.
5. Manipulate reserve accounting during execution.
6. Extract more assets from liquidity pools than legitimately allowed.

As a result, the protocol transferred excessive funds to the attacker while reserve calculations became inconsistent.

---

## Vulnerable Contract

### Main Contract

```text
contracts/DemaxPlatform.sol
```

### Primary Function

```solidity
function _swap(
    uint256[] memory amounts,
    address[] memory path,
    address _to
)
```

This function is responsible for:

* Executing token swaps
* Managing multi-hop routes
* Interacting with liquidity pair contracts
* Validating reserve invariants

Because all swap operations eventually pass through `_swap()`, it became the central component involved in the exploit.

---

## Vulnerable Execution Flow

```text
User Swap Request
        │
        ▼
swapExactTokensForTokens()
        │
        ▼
_getAmountsOut()
        │
        ▼
_swap()
        │
        ▼
IDemaxPair.swap()
        │
        ▼
Reserve Updates
        │
        ▼
Token Transfer
```

The attacker manipulated this execution path using a malicious token and flash-loaned liquidity.

---

## Critical Code Section

Inside `_swap()`, BurgerSwap performs the actual token exchange:

```solidity
IDemaxPair(pair).swap(
    amount0Out,
    amount1Out,
    to,
    new bytes(0)
);
```

This external call transfers control to the liquidity pair contract.

Improper handling of reserve accounting around this process enabled the attacker to manipulate swap calculations and extract excess funds.

---

## Invariant Validation

After the incident, BurgerSwap introduced an additional validation step:

```solidity
uint kBefore = reserve0 * reserve1;

IDemaxPair(pair).swap(...);

uint kAfter = reserve0 * reserve1;

require(kBefore <= kAfter, "Burger K");
```

Purpose:

* Verify that liquidity pool reserves remain valid.
* Ensure the AMM invariant is not violated.
* Prevent reserve manipulation attacks.

This check became commonly known as the **"Burger K Check"**.

---

## Attack Walkthrough

### Step 1 — Flash Loan

The attacker borrowed a large amount of capital through a flash loan.

### Step 2 — Malicious Token Creation

A custom token contract was deployed to interact with BurgerSwap pools.

### Step 3 — Liquidity Pair Setup

Liquidity pairs involving the malicious token were created.

### Step 4 — Swap Manipulation

The attacker executed carefully crafted swap routes.

### Step 5 — Reserve Distortion

Reserve values became inconsistent during execution.

### Step 6 — Excess Asset Extraction

The protocol calculated incorrect outputs and transferred more assets than intended.

### Step 7 — Flash Loan Repayment

The flash loan was repaid within the same transaction.

### Step 8 — Profit Realization

The attacker retained the remaining assets as profit.

---

## Impact

The exploit affected multiple liquidity pools and resulted in losses estimated at approximately **$7.2 million**.

Consequences included:

* Liquidity depletion
* User fund losses
* Loss of protocol trust
* Emergency protocol response

---

## Why This Vulnerability Matters

The BurgerSwap exploit highlights several important smart contract security lessons:

### 1. Never Modify Proven AMM Logic Lightly

Protocols such as Uniswap have undergone extensive security review. Small modifications can introduce severe vulnerabilities.

### 2. Protect Critical Swap Paths

All swap execution paths should be carefully validated and audited.

### 3. Validate Pool Invariants

The constant-product relationship should always be preserved.

### 4. Assume External Calls Are Dangerous

Whenever control leaves the contract, attackers may attempt to manipulate execution flow.

### 5. Flash Loans Amplify Risk

Even small logic flaws can become catastrophic when attackers gain temporary access to massive liquidity.

---

## Files Recommended for Study

### Primary File

```text
contracts/DemaxPlatform.sol
```

### Functions to Analyze

```solidity
_swap()
```

```solidity
swapExactTokensForTokens()
```

```solidity
_getAmountsOut()
```

```solidity
_getAmountsIn()
```

### Additional Pair Contract

```text
contracts/DemaxPair.sol
```

Important function:

```solidity
swap()
```

This contract contains the reserve-update logic that works together with `_swap()`.

---

## Key Security Takeaways

* Follow the Checks-Effects-Interactions pattern.
* Validate AMM invariants after every swap.
* Audit any modification to established protocols.
* Treat flash loans as a standard attacker capability.
* Minimize trust in external token contracts.
* Thoroughly test reserve accounting under adversarial conditions.

---

## References

* BurgerSwap Official Repository
* Demax Platform Repository
* Binance Smart Chain Incident Reports
* Security Research and Post-Mortem Analyses
* AMM Security Research Papers

