# Parity Library Wallet Bug (November 2017)

## Overview

This directory documents the **Parity Library Wallet Bug**, one of the most significant smart contract incidents in Ethereum history.

On **7 November 2017**, an attacker accidentally (or intentionally) initialized the shared `WalletLibrary` contract, became its owner, and then invoked its `kill()` function. This executed `suicide()` (`selfdestruct` in modern Solidity), permanently removing the library contract from the blockchain.

Because thousands of deployed Parity multisig wallets delegated their execution to this shared library using `delegatecall`, destroying the library rendered all dependent wallets unusable and permanently froze approximately **513,774 ETH**.

---

## Vulnerability

The vulnerability resulted from the shared library contract remaining **uninitialized** after deployment.

The library exposed the following initialization function:

```solidity
initWallet(...)
```

Since ownership had never been established, anyone could call this function and become the owner.

Once ownership was obtained, the attacker invoked

```solidity
kill(address)
```

which internally executed

```solidity
suicide(_to);
```

destroying the shared library.

---

## Root Cause

- Shared library contract deployed without initialization.
- Ownership could be claimed by any user.
- Library contained a privileged `kill()` function.
- Thousands of wallet contracts depended on the same library through `delegatecall`.

---

## Impact

- Approximately **513,774 ETH** frozen.
- Thousands of multisignature wallets permanently disabled.
- One of the largest smart contract failures in Ethereum history.

---

## Contracts

The historical Solidity source code used in this archive is stored in:

```
contracts/enhanced-wallet.sol
```

The file contains:

- Wallet
- WalletLibrary
- WalletEvents
- WalletAbi

---

## References

See the `sources/` directory.

## Note

This directory archives the historical vulnerable Solidity source code for educational and research purposes. The code is preserved as close to the original version as possible and has not been modified to remove the vulnerability.