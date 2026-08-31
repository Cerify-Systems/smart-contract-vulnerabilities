# Incident Report

## Summary

The Uniswap & Lendf.me (imBTC) attack occurred in April 2020 and demonstrated how integrating ERC-777 tokens into protocols designed around ERC-20 assumptions could introduce severe reentrancy vulnerabilities.

The attack first targeted Uniswap V1, where the exchange contract transferred Ether before completing the corresponding token transfer. Since the traded token (imBTC) implemented the ERC-777 standard, token transfer callbacks allowed an attacker-controlled contract to re-enter the exchange before execution completed.

The same technique was later applied to Lendf.me, a decentralized lending protocol built on Compound-inspired architecture. During withdrawals, the protocol transferred ERC-777 tokens before updating users' balances, allowing repeated withdrawals through recursive callback execution.

Approximately $25 million worth of assets were drained from Lendf.me. Most of the funds were later returned after negotiations with the attacker.

---

## Timeline

- **April 18, 2020** – ERC-777 reentrancy demonstrated against Uniswap V1.
- **April 19, 2020** – Lendf.me exploited using the same ERC-777 callback mechanism.
- Lendf.me suspended protocol operations.
- The attacker later returned the majority of stolen funds.

---

## Impact

- Approximately $25 million stolen.
- Temporary shutdown of the Lendf.me lending platform.
- Demonstrated that ERC-777 callback hooks could break assumptions made by DeFi protocols originally designed for ERC-20 tokens.
- Led to increased adoption of reentrancy protection mechanisms across DeFi protocols.

---

## Root Cause

The vulnerable contracts performed external token transfers before updating internal accounting.

Because ERC-777 token transfers execute callback hooks, attacker-controlled contracts could re-enter vulnerable functions before balances were updated.

The attack resulted from violating the Checks-Effects-Interactions (CEI) pattern rather than from a flaw in Solidity itself.