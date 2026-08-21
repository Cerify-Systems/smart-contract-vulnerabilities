
The seven affected pools and the attack sequence are documented in the Rari post-mortem and independent analyses. :contentReference[oaicite:10]{index=10}

---

# `sources/source-code-analysis.md`

```md
# Source Code Analysis — Rari Fuse Reentrancy

## 1. Vulnerable Execution Path

The vulnerable execution path was:

borrow()
    ↓
borrowFresh()
    ↓
doTransferOut()
    ↓
attacker callback
    ↓
exitMarket()
    ↓
collateral withdrawal

## 2. ETH Transfer

The Fuse CEther implementation used a low-level call to transfer ETH.

Conceptually:

```solidity
(bool success, ) = to.call.value(amount)("");
require(success);