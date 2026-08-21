# The DAO Hack (June 2016)

## Overview

The DAO (Decentralized Autonomous Organization) was one of the earliest and largest decentralized investment funds built on the Ethereum blockchain. In June 2016, it suffered a major exploit due to a **reentrancy vulnerability** in one of its smart contracts. The attacker repeatedly called the withdrawal function before the contract could update the user's balance, allowing funds to be withdrawn multiple times in a single transaction.

The attack resulted in the theft of approximately **3.6 million ETH**, making it one of the most significant smart contract exploits in blockchain history.

## Incident Details

- **Protocol:** The DAO
- **Date:** June 2016
- **Vulnerability Type:** Reentrancy
- **Estimated Loss:** ~3.6 Million ETH
- **Blockchain:** Ethereum

## Root Cause

The vulnerable contract transferred Ether to the caller before updating the user's internal balance. Since the recipient contract's fallback function was executed during the transfer, it could recursively call the withdrawal function multiple times before the balance was reduced.

Simplified vulnerable flow:

1. User requests withdrawal.
2. Contract sends Ether to the user.
3. User's fallback function executes.
4. Fallback calls the withdrawal function again.
5. Balance has not yet been updated, allowing repeated withdrawals.

## Impact

- Approximately 3.6 million ETH was drained.
- The exploit led to a heated debate within the Ethereum community.
- Ethereum performed a **hard fork** to recover the stolen funds.
- A minority of the community continued on the original chain, now known as **Ethereum Classic (ETC)**.

## Fix and Prevention

The primary mitigation is to follow the **Checks-Effects-Interactions** pattern:

1. Perform validation checks.
2. Update the contract's internal state.
3. Interact with external contracts only after state changes.
