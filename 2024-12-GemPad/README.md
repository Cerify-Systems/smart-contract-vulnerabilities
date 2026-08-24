# GemPad Reentrancy Vulnerability — Incident Report & Technical Analysis

> **Vulnerability Class:** Reentrancy (CWE-841 / SWC-107)
> **Date of Exploit:** December 17, 2024
> **Estimated Loss:** ~$1.9M – $2.2M USD

---

## Table of Contents

- [Overview](#overview)
- [Incident Summary](#incident-summary)
- [Timeline](#timeline)
- [Affected Contract](#affected-contract)
- [Root Cause Analysis](#root-cause-analysis)
- [Deep Dive: `collectFees()` Function](#deep-dive-collectfees-function)
- [Attack Flow](#attack-flow)
- [Impact](#impact)
- [Remediation](#remediation)
- [References](#references)
- [Lessons Learned](#lessons-learned)

---

## Overview

**GemPad** is a multichain, no-code smart-contract deployment/launchpad platform operating on **Ethereum, BNB Chain, and Base**. It allows projects to create tokens and lock their **LP (liquidity-provider) tokens** through a dedicated locker contract (`GempadLock`) to build investor trust (locked liquidity signals reduced rug-pull risk).

On **December 17, 2024**, an attacker exploited a **reentrancy vulnerability** in the `collectFees()` function of `GempadLock.sol`, draining locked liquidity across all three supported chains. The flaw existed despite the contract having undergone **two separate third-party audits** (Cyberscope and SolidProof).

---

## Incident Summary

| Field | Detail |
|---|---|
| **Protocol** | GemPad (no-code launchpad / LP locker) |
| **Vulnerability Type** | Reentrancy (missing `nonReentrant` guard) |
| **Vulnerable Function** | `collectFees(uint256 lockId)` |
| **Chains Affected** | Ethereum, BNB Chain (BSC), Base |
| **Projects Impacted** | 27 of ~3,000 projects using GemPad's locker |
| **Estimated Loss** | $1.9M (Halborn, Rekt.news) – $2.2M (OKLink, Cyberscope) |
| **Auditors (pre-incident)** | Cyberscope, SolidProof |
| **Proxy Contract (Ethereum)** | `0x10B5F02956d242aB770605D59B7D27E51E45774C` |
| **Attribution** | Unattributed; funds largely routed through Tornado Cash |

---

## Timeline

| Date | Event |
|---|---|
| **Jan 2024** | Initial SolidProof audit of GemPad locker contracts completed. |
| **~Nov 2024** | Contract reportedly modified at the request of another auditor, deviating from the "frozen codebase" best practice — after the original audit had already signed off. |
| **Dec 17, 2024** | Attacker exploits the reentrancy flaw in `collectFees()` across Ethereum, BSC, and Base, draining locked LP value. |
| **Dec 17–18, 2024** | Security monitors (BlockSec, Hexagate) flag anomalous activity; GemPad and partner firms (CertiK, Cyberscope, SolidProof, Assure DeFi, Hackdra, Contract Wolf, Octavia) respond to contain and investigate. |
| **Dec 20, 2024** | Public incident reports published (Rekt.news, OKLink, community post-mortems). |
| **Post-incident** | GemPad reportedly patches the locker contract via its upgradeable proxy, adding a `nonReentrant` modifier to `collectFees()` (see [Remediation](#remediation)). |

---

## Affected Contract

The publicly exploited contract is deployed behind an **EIP-1967 Transparent Upgradeable Proxy**:

- **Proxy (Ethereum):** `0x10B5F02956d242aB770605D59B7D27E51E45774C` — labeled "GemPad Lock" on Etherscan
- **Implementation contract:** `GempadLock.sol` (logic contract holding all business logic, including `collectFees`)

> **Note:** GemPad's locker is deployed identically (or near-identically) on Ethereum, BNB Chain, and Base, which is why the same vulnerability could be exploited across all three networks in a single incident window.

### Contract Structure (relevant excerpt)

```solidity
contract GempadLock is
    IGempadLock,
    IERC721Receiver,
    Initializable,
    OwnableUpgradeable
{
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    struct Lock {
        uint256 id;
        address token;
        address owner;
        uint256 amount;
        uint40 lockDate;
        uint40 tgeDate;
        uint24 tgeBps;
        uint40 cycle;
        uint24 cycleBps;
        uint256 unlockedAmount;
        string description;
        address nftManager;
        uint256 nftId;
    }

    Lock[] private _locks;
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status = NOT_ENTERED;
    ...
```

The locker supports both **ERC-20 LP tokens (Uniswap V2-style)** and **Uniswap V3 NFT-based liquidity positions** (via `INonfungiblePositionManager`). `collectFees()` specifically handles fee collection for the **V3 NFT-based locks**.

---

## Root Cause Analysis

The vulnerability follows the classic **Checks-Effects-Interactions (CEI) violation** pattern — the same root cause behind the 2016 DAO hack.

### What went wrong (pre-patch state)

1. `collectFees()` is called by the owner of an LP lock to claim accumulated trading fees from their locked Uniswap V3 position.
2. The function makes an **external call** to Uniswap's `NonfungiblePositionManager.collect()`, instructing it to send fee tokens to `userLock.owner`.
3. If either token in the LP pair is a **malicious, attacker-deployed token** with a hostile callback (a custom `transfer()`/hook invoked during the fee payout), execution control is handed to attacker-controlled code **mid-transaction**.
4. At the time of the exploit, **`collectFees()` had no reentrancy guard.** The attacker's callback could re-enter `GempadLock` (calling back into `collectFees()` or other state-mutating functions sharing the same `_locks` / `cumulativeLockInfo` storage) **before the original call context completed**.
5. By looping this re-entrant call, the attacker could repeatedly trigger fee/liquidity extraction tied to the same lock position, draining value **far exceeding** what was legitimately owed — reports describe pulling out several times the originally locked amount.

### Why the audits missed it

- SolidProof stated the contract was **modified after their audit was finalized**, at the request of a different auditor — breaking the "frozen codebase" assumption that audit sign-offs rely on.
- Reentrancy risk in `collectFees()` is easy to overlook when the function *appears* to only move value to the legitimate lock owner (`userLock.owner`) — the exploitability hinges on the **attacker controlling one side of the LP pair's token contract**, which isn't always in scope for a purely code-level review without deeper token-composability threat modeling.

---

## Deep Dive: `collectFees()` Function

### Current (patched) source

```solidity
function collectFees(
    uint256 lockId
) external isLockOwner(lockId) validLockLPv3(lockId) nonReentrant {
    Lock storage userLock = _locks[lockId];
    // set amount0Max and amount1Max to uint256.max to collect all fees
    // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
    INonfungiblePositionManager.CollectParams
        memory params = INonfungiblePositionManager.CollectParams({
            tokenId: userLock.nftId,
            recipient: userLock.owner,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
     INonfungiblePositionManager(
        userLock.nftManager
    ).collect(params);        
}
```

### Line-by-line breakdown

| Line | Analysis |
|---|---|
| `external isLockOwner(lockId) validLockLPv3(lockId) nonReentrant` | Modifiers: caller must own the lock, the lock must be a valid V3 LP lock, and — **critically** — `nonReentrant` now guards the function. **This modifier was absent at the time of the December 2024 exploit.** |
| `Lock storage userLock = _locks[lockId];` | Loads the lock record by reference; `userLock.nftManager` and `userLock.nftId` identify the Uniswap V3 position. |
| `CollectParams({ tokenId: ..., recipient: userLock.owner, amount0Max: type(uint128).max, amount1Max: type(uint128).max })` | Requests **maximum possible fee withdrawal** for the position, sent directly to `userLock.owner` — i.e., **the caller, if they are the lock owner**. |
| `INonfungiblePositionManager(userLock.nftManager).collect(params);` | **The external call.** This hands execution to Uniswap's position manager, which in turn transfers `token0`/`token1` fee amounts to `recipient`. If either token has attacker-controlled transfer logic, **this is the reentrancy entry point.** |

### The reentrancy guard that fixes it

```solidity
uint256 private constant NOT_ENTERED = 1;
uint256 private constant ENTERED = 2;
uint256 private _status = NOT_ENTERED;

error ReentrancyGuardReentrantCall();

modifier nonReentrant() {
    _nonReentrantBefore();
    _;
    _nonReentrantAfter();
}

function _nonReentrantBefore() private {
    if (_status == ENTERED) {
        revert ReentrancyGuardReentrantCall();
    }
    _status = ENTERED;
}

function _nonReentrantAfter() private {
    _status = NOT_ENTERED;
}
```

This is a standard OpenZeppelin-style mutex: `_status` is flipped to `ENTERED` **before** the function body executes, and any nested call into another `nonReentrant`-guarded function during that window immediately reverts. **This is exactly the control that was missing from `collectFees()` pre-exploit** — without it, the external `.collect()` call could be interrupted by attacker code that re-entered the contract before `_status` (or any other lock bookkeeping) was updated.

### Reconstructed vulnerable version (illustrative)

For educational comparison, the exploited version most likely looked like this — identical logic, **minus** the guard:

```solidity
// VULNERABLE (pre-patch) — illustrative reconstruction
function collectFees(
    uint256 lockId
) external isLockOwner(lockId) validLockLPv3(lockId) {
    // ^ no `nonReentrant` modifier
    Lock storage userLock = _locks[lockId];
    INonfungiblePositionManager.CollectParams
        memory params = INonfungiblePositionManager.CollectParams({
            tokenId: userLock.nftId,
            recipient: userLock.owner,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
    INonfungiblePositionManager(
        userLock.nftManager
    ).collect(params);
    // No reentrancy lock protecting this external call —
    // attacker-controlled token logic can re-enter here.
}
```

---

## Attack Flow

```
1. Attacker deploys a malicious ERC-20 token with a hostile transfer()/hook.
2. Attacker pairs the malicious token with a legitimate token and
   creates/locks a Uniswap V3 LP position via GempadLock, becoming
   userLock.owner for that lock.
3. Attacker calls collectFees(lockId).
4. GempadLock calls NonfungiblePositionManager.collect(), which
   attempts to pay out fee tokens to userLock.owner (the attacker).
5. Payout of the malicious token triggers the attacker's hostile
   transfer()/hook logic.
6. Inside that hook, the attacker re-enters GempadLock (e.g., calls
   collectFees() again, or another state-mutating lock function)
   BEFORE the original call/state has settled — because no
   reentrancy guard exists yet.
7. This is looped, extracting value repeatedly from the same
   underlying position/lock accounting.
8. Attacker swaps extracted assets to ETH/BNB and routes funds
   through Tornado Cash.
9. Repeated across Ethereum, BNB Chain, and Base against the same
   flawed contract template — hitting 27 separate projects.
```

---

## Impact

| Metric | Value |
|---|---|
| **Total estimated loss** | $1.9M – $2.2M (figures vary by source/methodology) |
| **Chains affected** | Ethereum, BNB Chain, Base |
| **Projects affected** | 27 of ~3,000 GemPad-hosted projects |
| **Notable affected projects** | Munch Protocol, AnonFi, BPay (among others) |
| **Fund destination** | Predominantly laundered via Tornado Cash |

Because the flaw lived in a **shared, templated locker contract** used across many independent token projects, a single vulnerability class produced losses spread across dozens of unrelated teams and their communities — illustrating the systemic risk of no-code/template-based smart contract platforms.

---

## Remediation

Based on the current source code, GemPad's fix (deployed via the upgradeable proxy pattern) was to add:

1. A **`nonReentrant` modifier** to `collectFees()` (and consistently applied across other state-mutating functions: `multipleLock`, `multipleVestingLock`, `lockLpV3`, `unlock`, `editLock`, `increaseLiquidityCurrentRange`, `decreaseLiquidityCurrentRange`, `editLockDescription`, `editProjectTokenMetaData`).
2. A standard **mutex-based reentrancy guard** (`_status` / `NOT_ENTERED` / `ENTERED`) implemented directly in the contract rather than relying solely on external call ordering.

This is consistent with the broader industry-standard fix for this vulnerability class: **guard any function containing an external call that could transfer control to attacker-influenced code**, especially where that call precedes or is interleaved with state updates.

---

## References

- Halborn — *Explained: The GemPad Hack (December 2024)*
  https://www.halborn.com/blog/post/explained-the-gempad-hack-december-2024
- CryptoRank — *The Gem Pad token launchpad has been exploited for $2M on multiple chains*
  https://cryptorank.io/news/feed/07a70-gem-pad-token-launchpad-exploited-2m
- Audita.io — *Gempad Reentrancy Exploit 17 Dec 2024: Pre-Existing Contract Templates*
  https://audita.io/blog-articles/gempad-reentrancy-exploit-dec-17th-2024
- The Holy Coins — *GemPad Exploit: Up to $2.2M Lost in DeFi Reentrancy Vulnerability*
  https://theholycoins.com/blog/gempad-exploit-up-to-usd2-2-million-lost-to-reentrancy-vulnerability-27-projects-impacted-a
- Quadriga Initiative — *Dec 2024 - GemPad Reentrancy Exploit In Lock Contract - $2.2m*
  https://quadrigainitiative.com/casestudy/gempadreentrancyexploitinlockcontract.php
- Coinmonks (Medium) — *$66.6M Stolen Through Crypto Crimes — Top 5 Hacks of December 2024*
  https://medium.com/coinmonks/66-6m-stolen-through-crypto-crimes-top-5-hacks-of-december-2024-77a3e579845f
- pcaversaccio — *A Historical Collection of Reentrancy Attacks* (GitHub)
  https://github.com/pcaversaccio/reentrancy-attacks
- SolidProof — Audit Report Reference (`Gempad_LockV2`)
  https://github.com/solidproof/Projects/blob/main/Projects/2024/Gempad_LockV2/SmartContract_Audit_Solidproof_Gempad_LockV2.pdf
- On-chain verified contract — Etherscan
  `https://etherscan.io/address/0x10B5F02956d242aB770605D59B7D27E51E45774C`

---

## Lessons Learned

1. **A `nonReentrant` modifier is not optional on any function containing an external call that can transfer control to untrusted code** — even fee-collection or "read-adjacent" functions that seem lower-risk than direct withdrawals.
2. **External calls to standardized DeFi primitives (like Uniswap's `NonfungiblePositionManager`) are still attack surfaces** when the underlying tokens involved are attacker-chosen — the trust boundary isn't the primitive itself, it's the token contracts it interacts with.
3. **Post-audit code changes invalidate the audit.** SolidProof's own statement that the contract was modified after their sign-off — at another auditor's request — is a critical process failure. Any change to a smart contract after an audit should trigger, at minimum, a **diff-scoped re-review** before mainnet deployment.
4. **Shared/templated contract architecture multiplies blast radius.** Because GemPad's locker was deployed identically across many projects and three chains, one logic flaw became a **multi-chain, multi-project** incident rather than an isolated one. Template-based platforms should treat any core contract vulnerability as automatically "critical + wide-scope."
5. **Two audits are not a guarantee.** Both Cyberscope and SolidProof reviewed related contracts, yet the flaw shipped to production — underscoring that audits reduce but do not eliminate risk, and that **on-chain monitoring** (which is what ultimately caught this exploit in progress, via BlockSec/Hexagate) remains a necessary complementary control.
6. **Checks-Effects-Interactions (CEI) discipline must be enforced everywhere, not just in "obvious" withdrawal paths.** Reentrancy bugs frequently hide in secondary or "convenience" functions (like fee collection) rather than the primary deposit/withdraw flows that reviewers scrutinize most heavily.
7. **Upgradeable proxy patterns enable fast remediation** — GemPad's ability to patch `collectFees()` post-incident (adding the guard shown in this repo) via its EIP-1967 proxy demonstrates the value of upgradeability for incident response, though it also means historical Etherscan snapshots must be interpreted carefully (current source ≠ source live during the exploit).


