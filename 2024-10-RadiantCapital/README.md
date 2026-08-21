# Radiant Capital October 2024 Exploit Analysis

## Overview

This repository presents a case study of the October 2024 Radiant Capital exploit, one of the most significant DeFi security incidents of 2024.

Unlike traditional smart contract exploits involving reentrancy, access control flaws, oracle manipulation, or business logic vulnerabilities, the Radiant Capital incident originated from a compromise of the protocol's governance and operational security infrastructure.

Attackers successfully obtained valid multisig approvals by compromising developer devices and manipulating the transaction-signing process. Using these approvals, they gained administrative control over critical protocol components and drained approximately $50 million from the protocol.

---

## Incident Summary

* **Protocol:** Radiant Capital
* **Date:** October 16, 2024
* **Category:** Governance / Multisig Compromise
* **Root Cause:** Malware-based signer compromise
* **Estimated Loss:** ~$50 Million
* **Networks Affected:** Arbitrum, BNB Chain

---

## Attack Flow

1. Multiple developer devices were infected with malware.
2. The malware manipulated Safe (Gnosis Safe) transaction signing.
3. Developers reviewed legitimate-looking transactions.
4. Malicious transactions were signed in the background.
5. Attackers collected sufficient multisig approvals.
6. Administrative control over protocol infrastructure was obtained.
7. Critical protocol components were upgraded or redirected.
8. User funds were drained from lending markets.

---

## Contract Associated With The Incident

### LendingPoolAddressesProvider.sol

Path:

```text
contracts/protocol/lendingpool/LendingPoolAddressesProvider.sol
```

This contract serves as the central registry and administrative control layer of the lending protocol.

Key responsibilities include:

* Managing core protocol component addresses
* Registering upgradeable implementations
* Managing oracle addresses
* Controlling configurator contracts
* Ownership and administrative operations

The contract itself was not vulnerable. However, administrative authority over this contract became the attacker's primary objective after obtaining valid multisig signatures.

---

## Important Functions

* `setAddress()`
* `setAddressAsProxy()`
* `setLendingPoolImpl()`
* `setLendingPoolConfiguratorImpl()`
* `setPriceOracle()`
* `transferOwnership()`

These functions demonstrate how protocol components are managed and upgraded through governance permissions.

---

## Security Lessons

* Smart contract audits cannot prevent signer compromise.
* Hardware wallets alone are insufficient against sophisticated malware.
* Multisig systems remain vulnerable if enough signers are compromised.
* Administrative contracts represent critical trust assumptions in DeFi architectures.
* Governance security is as important as smart contract security.

---

## References

* Radiant Capital Official Post-Mortem
* Radiant Capital Incident Updates
* Security Research Reports
* Public On-Chain Analysis
