# Furucombo Exploit (February 2021)

## Overview

Furucombo is a DeFi transaction batching protocol that enables users to combine multiple decentralized finance operations into a single transaction. On **27 February 2021**, the protocol suffered a major exploit that resulted in the theft of approximately **$14 million USD** worth of user assets.
Unlike many DeFi exploits caused by arithmetic errors or reentrancy, the Furucombo incident resulted from a **logic flaw in the protocol's proxy architecture**. The exploit allowed an attacker to execute arbitrary malicious logic by abusing the interaction between the Proxy contract, handler contracts, and the registry.

## Incident Information

- **Protocol:** Furucombo
- **Blockchain:** Ethereum
- **Date:** 27 February 2021
- **Loss:** Approximately $14 million USD
- **Attack Type:** Smart Contract Logic Vulnerability
- **Primary Vulnerable Contract:** `Proxy.sol`

## Background

Furucombo executes user actions through a central **Proxy** contract. Instead of interacting directly with DeFi protocols, users submit a sequence of operations (called combos) to the Proxy, which delegates execution to registered handler contracts.
This modular architecture allows complex DeFi strategies to be executed efficiently while keeping protocol integrations separated into individual handlers.

## Root Cause

The exploit originated from insufficient validation of delegated handler execution.

The Proxy contract trusted registered handlers and executed them using Solidity's `delegatecall`. By abusing the registry and handler execution flow, an attacker was able to execute malicious logic that granted unauthorized token approvals from the Proxy contract.
Once approvals were obtained, the attacker transferred assets from users who had previously interacted with Furucombo.

## Attack Overview

The attacker:

1. Exploited the handler validation mechanism.
2. Executed malicious code through the Proxy contract.
3. Obtained unlimited token approvals.
4. Used the granted approvals to transfer tokens from affected users.
5. Drained approximately $14 million in crypto assets.

## Financial Impact

The exploit resulted in approximately **$14 million USD** in stolen assets.Affected users included those who had previously deposited or approved tokens through the Furucombo protocol. The protocol paused operations immediately after detecting the exploit and later compensated many affected users.

## Vulnerable Contract

```
contracts/
└── Proxy.sol
```

The vulnerable contract is responsible for:

- Executing user transaction batches.
- Delegating execution to handler contracts.
- Managing callback execution.
- Performing post-processing of assets.

## Structure

```
2021-02-Furucombo/
├── contracts/
│   └── Proxy.sol
├── README.md
├── exploit.md
├── fix.md
└── writeups/
    └── sources.md
```