# Uniswap & Lendf.me (imBTC) Reentrancy Attack (2020)

## Overview

The Uniswap & Lendf.me (imBTC) incident was one of the earliest and most significant demonstrations of how ERC-777 token callbacks could introduce reentrancy vulnerabilities into decentralized finance (DeFi) protocols that assumed ERC-20 behavior. The attack exploited the interaction between the ERC-777 implementation of the imBTC token and smart contracts that performed external token transfers before completing internal state updates.

The attack was first demonstrated against **Uniswap V1**, where the exchange contract transferred Ether before completing the corresponding token transfer, allowing the ERC-777 callback mechanism to re-enter the exchange during execution. Shortly afterward, the same technique was used against **Lendf.me**, a lending protocol built on Compound-inspired architecture, resulting in the theft of approximately **$25 million** worth of assets. Most of the stolen funds were eventually returned after negotiations with the attacker.

Unlike traditional reentrancy attacks that rely on Ether transfers, this incident demonstrated that **token standards themselves can introduce reentrant execution**, requiring protocols to account for callback-based interactions when integrating new token implementations.

---

## Root Cause

The vulnerability resulted from violating the **Checks-Effects-Interactions (CEI)** design pattern.

Both protocols executed external token transfer operations before fully updating their internal accounting.

For standard ERC-20 tokens, this ordering was generally considered safe because token transfers do not execute arbitrary code.

However, the **ERC-777** standard introduces callback hooks (`tokensToSend` and `tokensReceived`) that allow recipient or sender contracts to execute arbitrary logic during a token transfer.

When the vulnerable contracts transferred **imBTC**, these callbacks allowed an attacker-controlled contract to re-enter protocol functions before balances and accounting variables had been updated.

As a result, multiple withdrawals or swaps could be executed while the protocol still believed the attacker possessed the original balance.

---

## Affected Components

### Uniswap V1

**Contract**

- `contracts/uniswap_exchange.vy`

**Vulnerable Functions**

- `tokenToEthInput()`
- `tokenToEthOutput()`

The exchange contract transferred Ether before completing the ERC-777 token transfer, enabling callback-based reentrancy.

---

### Lendf.me

**Contract**

- `contracts/MoneyMarket.sol`

**Vulnerable Functions**

- `withdraw()`
- `doTransferOut()`

The lending protocol transferred ERC-777 tokens before updating users' supply balances, allowing repeated withdrawals through recursive callback execution.

---

## Attack Flow

1. The attacker deposited or borrowed **imBTC**.
2. The protocol initiated a token transfer.
3. The ERC-777 token executed its callback hook.
4. The callback re-entered the vulnerable protocol.
5. Internal balances had not yet been updated.
6. Additional withdrawals or swaps were executed.
7. The process repeated recursively until funds were drained.

---

## Technical Impact

The attack demonstrated that:

- ERC-777 callbacks fundamentally change the assumptions made by protocols originally designed for ERC-20 tokens.
- External token transfers should always be treated as potentially reentrant operations.
- Internal accounting must always be updated before interacting with external contracts.
- Reentrancy guards provide an important additional layer of protection for functions performing external interactions.

---

## Lessons Learned

- Follow the **Checks-Effects-Interactions (CEI)** pattern.
- Update protocol state before external calls.
- Treat all external token transfers as potentially reentrant.
- Use `ReentrancyGuard` (or equivalent) for sensitive functions.
- Carefully evaluate assumptions when integrating new token standards.

---

## Vulnerability Classification

- Reentrancy
- ERC-777 Callback Reentrancy
- Improper Checks-Effects-Interactions Ordering
- Business Logic Vulnerability

---

## References

See the files in the `sources/` directory:

- `incident-report.md`
- `technical-analysis.md`
- `references.md`
