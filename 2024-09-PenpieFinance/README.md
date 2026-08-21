# Penpie Finance (2024) — Modern Reentrancy Vulnerability Analysis

## Overview

This case study analyzes the September 2024 exploit of Penpie Finance, a yield aggregation protocol built on top of Pendle Finance. The attack resulted in losses of approximately $27 million and is considered one of the most significant examples of **Modern Reentrancy** in decentralized finance.

Unlike traditional reentrancy attacks that repeatedly invoke withdrawal functions, the Penpie exploit abused reward harvesting and accounting logic through interactions with an external market contract.

---

## Vulnerability Classification

**Category:** Reentrancy Vulnerability

**Subcategory:** Modern / Cross-Contract Reentrancy

**Year:** 2024

**Impact:** Unauthorized reward inflation and extraction of protocol funds

---

## Background

Penpie integrates with Pendle Finance to provide users with enhanced yield opportunities. To distribute rewards, Penpie periodically harvests rewards from Pendle markets and forwards them to reward distribution contracts.

The protocol relied on balance-difference accounting to determine the amount of rewards harvested from a market.

The general workflow was:

1. Record reward token balances before harvesting.
2. Call an external Pendle market contract.
3. Receive rewards.
4. Calculate harvested rewards using balance differences.
5. Distribute rewards to users.

The attack exploited the interaction between steps 2 and 4.

---

## Root Cause

The vulnerability originated from an external call made during reward harvesting:

```solidity
IPendleMarket(_market).redeemRewards(address(this));
```

The protocol assumed that reward balances would only change due to the expected reward redemption process.

However, because control was transferred to an external contract, a malicious market could manipulate execution flow before reward accounting was finalized.

As a result, reward calculations based on:

```text
Balance Before Harvest
        ↓
Redeem Rewards
        ↓
Balance After Harvest
        ↓
Reward Difference Calculation
```

could be manipulated to generate incorrect reward amounts.

---

## Relevant Contract

### Main Contract

**PendleStakingBaseUpg.sol**

This contract is responsible for:

* Harvesting rewards from Pendle markets
* Processing harvested rewards
* Calculating reward allocations
* Distributing rewards to reward pools

---

## Key Functions Studied

### 1. `batchHarvestMarketRewards()`

Public entry point used to initiate reward harvesting across multiple markets.

#### Responsibilities

* Accepts a list of Pendle markets
* Initiates batch reward harvesting
* Delegates execution to internal harvesting logic

#### Security Significance

This function serves as the entry point into the vulnerable reward harvesting workflow.

---

### 2. `_harvestBatchMarketRewards()`

Core reward harvesting implementation.

#### Responsibilities

* Retrieves reward token information
* Stores balances before harvesting
* Calls external market contracts
* Computes harvested rewards
* Distributes rewards

#### Security Significance

Contains the critical external interaction:

```solidity
IPendleMarket(_markets[i]).redeemRewards(address(this));
```

and subsequent reward accounting calculations.

This function represents the primary attack surface exploited during the incident.

---

### 3. `_harvestMarketRewards()`

Single-market reward harvesting implementation.

#### Responsibilities

* Harvest rewards from an individual market
* Track balance changes
* Calculate reward amounts
* Forward rewards to rewarders

#### Security Significance

Uses the same accounting methodology as the batch harvesting function and demonstrates the reward calculation model relied upon by the protocol.

---

## Attack Flow

```text
Attacker Creates Malicious Market
                ↓
Market Registered in Penpie
                ↓
Reward Harvest Initiated
                ↓
redeemRewards() Executed
                ↓
Control Passed to External Contract
                ↓
Reentrant Execution Triggered
                ↓
Reward Accounting Manipulated
                ↓
Excess Rewards Generated
                ↓
Protocol Funds Drained
```

---

## Security Lessons

### 1. External Calls Require Extreme Caution

Any interaction with an external contract introduces the possibility of unexpected execution paths.

### 2. Follow Checks-Effects-Interactions

Internal accounting updates should be completed before interacting with external contracts whenever possible.

### 3. Reentrancy Is No Longer Limited to Withdrawals

Modern DeFi protocols frequently involve:

* Reward harvesting
* Token conversions
* Cross-contract integrations
* Yield aggregation

All of these can introduce reentrancy risks.

### 4. Never Trust External Market Integrations

Even when interacting with seemingly legitimate protocol components, assumptions regarding execution flow must be carefully validated.

---

## Impact

* Approximately $27 million lost.
* Protocol operations temporarily halted.
* Emergency mitigation measures deployed.
* Additional validation and protection mechanisms introduced.

---

## Conclusion

The Penpie Finance exploit demonstrates how modern DeFi protocols can be vulnerable to sophisticated forms of reentrancy that do not resemble the classic DAO attack pattern.

Instead of repeatedly withdrawing funds, the attacker exploited reward harvesting and accounting logic through interactions with an external market contract. This incident highlights the importance of secure external integrations, rigorous accounting controls, and comprehensive reentrancy protection mechanisms in complex smart contract systems.

---

## References

* Penpie Finance Incident Reports
* Pendle Finance Documentation
* Security Research and Postmortem Analyses
* Verified Smart Contract Source Code
