# Harmony Horizon Bridge Exploit — June 2022

## Overview

The Harmony Horizon Bridge was exploited on June 23, 2022, resulting in the theft of approximately $100 million in cryptocurrency assets.

The incident was not caused by a traditional Solidity logic vulnerability. The attacker compromised two private keys belonging to the bridge's five multisig owners. Since the bridge required only two of five signatures to authorize transactions, control of two keys was sufficient to execute unauthorized withdrawals.

## Incident Details

- Date: June 23, 2022
- Loss: Approximately $100 million
- Target: Harmony Horizon Bridge
- Chains: Ethereum / Harmony / BNB Chain
- Attack Type: Multisig key compromise
- Multisig Configuration: 2-of-5
- Main Bridge Manager: ERC20EthManager
- Main Authorization Contract: MultiSigWallet
- Compiler: Solidity 0.5.17

## Root Cause

The bridge relied on a 2-of-5 multisignature wallet to authorize withdrawals from the Ethereum-side bridge manager.

Two signer private keys were compromised. The attacker used the two keys to satisfy the required confirmation threshold and execute transactions that called the bridge's token unlock functionality.

The smart contracts behaved according to their programmed rules. The failure was primarily in private-key security and the authorization threshold used to protect a large amount of bridge assets.

## Attack Flow

1. Two multisig signer private keys were compromised.
2. The attacker used the first key to submit a malicious transaction.
3. The first signer was automatically recorded as a confirmation.
4. The second compromised signer confirmed the transaction.
5. The 2-of-5 threshold was reached.
6. The multisig executed the transaction.
7. ERC20EthManager unlocked bridge assets.
8. The attacker repeated the process for multiple assets.

## Key Contracts

- MultiSigWallet
- ERC20EthManager

## Vulnerability Classification

- Multisig Key Compromise
- Insufficient Authorization Threshold
- Bridge Security Failure
- Operational / Key Management Failure

## Impact

Approximately $100 million in assets were stolen, including ETH, BNB, USDT, USDC, DAI and WBTC.

## Prevention

- Increase multisig signing threshold.
- Use independent and secure key-management infrastructure.
- Use hardware wallets or HSMs.
- Add timelocks for large withdrawals.
- Implement withdrawal limits and circuit breakers.
- Add independent cross-chain proof verification where possible.

## References

See `sources/references.md`.