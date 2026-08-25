# FairWin Ponzi — Access Control & Admin-Privilege Flaw (September 2019)

## Table of Contents
- [Summary](#summary)
- [Background](#background)
- [The Real-World Contract](#the-real-world-contract)
- [Vulnerability Description](#vulnerability-description)
- [Faulty / Sensitive Functions](#faulty--sensitive-functions)
- [Attack Flow — Why This Happened](#attack-flow--why-this-happened)
- [Loss Incurred & Impact](#loss-incurred--impact)
- [Timeline of Disclosure](#timeline-of-disclosure)
- [The Fix](#the-fix)
- [Lessons for Solidity Developers](#lessons-for-solidity-developers)
- [References](#references)

---

## Summary

| | |
|---|---|
| **Name** | FairWin |
| **Category** | Ethereum gambling dApp / undisclosed Ponzi scheme |
| **Vulnerability Type** | Insecure admin privileges, missing access control, front-runnable state binding |
| **Disclosure Date** | September 26–29, 2019 |
| **Collapse Date** | September 30, 2019 |
| **Contract Address** | `0x01eacc3ae59ee7fbbc191d63e8e1ccfdac11628c` |
| **Total ETH received (lifetime)** | ~687,598 ETH (~$125,000,000 at intake) |
| **ETH drained/lost in final collapse** | ~40,000–50,000 ETH (~$8M+ at the time) |
| **Root Cause** | Owner-controlled payout logic + a public state-mutating function with no access control (`remedy`) + front-runnable invite-code binding |

FairWin was marketed as a "fair," provably-random Ethereum gambling game but functioned as a pyramid/Ponzi scheme, paying early depositors with the deposits of later ones. At its peak it accounted for over **60% of all gas usage on the Ethereum network**. Independent researchers found that the contract's payout and balance-crediting logic were entirely gated behind the contract owner (or a handful of hardcoded addresses), and that one public function had **no access control whatsoever**. When this was disclosed publicly, the contract's balance was drained to zero within four days — either by users racing to withdraw, or by the admins themselves front-running the exodus.

---

## Background

FairWin (fairwin.me) surfaced in September 2019 as an unusually gas-hungry contract on Ethereum. Researchers Philippe Castonguay (Horizon Games) and Daniel Luca (ConsenSys Diligence) began investigating after noticing the contract was responsible for an outsized share of network gas consumption and had suspicious characteristics of a Ponzi scheme (the project's "team" photos were later found to be stolen from unrelated public figures).

An **earlier version** of the FairWin contract had already been drained once, for 2,662 ETH on **July 27, 2019**, by Daniel Luca — not maliciously, but as a proof that a public `sendFeeToAdmin(amount)` function let anyone siphon contract funds to a hardcoded admin address. FairWin's team redeployed a patched version on **July 29, 2019** (the version referenced throughout this document) that made this function `private` — but the underlying trust model (owner/admin controls who gets paid and when) was never fixed.

---

## The Real-World Contract

- **Etherscan:** https://etherscan.io/address/0x01eacc3ae59ee7fbbc191d63e8e1ccfdac11628c
- **Verified source (GitHub Gist mirror, published by Clément Lesaege during disclosure):**
  https://gist.github.com/clesaege/815d2e2eb2bcac96be732af0bfc81ac1
- **Compiler:** `pragma solidity ^0.4.24;`
- **Deployed / re-verified:** July 29, 2019

The contract stores each participant in a `User` struct (`freeAmount`, `freezeAmount`, `rechargeAmount`, `inviteAmonut`, `bonusAmount`, etc.) inside `mapping(address => User) userMapping`, tracks every deposit in an `Invest[] invests` array, and links referral/invite codes to addresses via `mapping(string => address) addressMapping`.

```solidity
contract FairWin {
    uint ethWei = 1 ether;
    address private owner;
    uint private actStu = 0;

    struct User {
        address userAddress;
        uint freeAmount;       // withdrawable balance
        uint freezeAmount;     // locked/staked balance
        ...
        bool isVaild;
    }

    struct Invest {
        address userAddress;
        uint inputAmount;
        ...
    }

    mapping (address => User) userMapping;
    mapping (string => address) addressMapping;   // inviteCode -> address
    mapping (uint => address) indexMapping;
    Invest[] invests;
    ...
}
```

---

## Vulnerability Description

Three distinct weaknesses combined to make user funds unsafe, all rooted in **who is allowed to change contract state, and how that state maps to withdrawable ETH**:

### 1. Owner-gated payout logic ("insecure admin privileges")
The only functions that increment a user's `freeAmount` (the balance `userWithDraw()` actually pays out) or push ETH directly to a user are:
- `countShareAndRecommendedAward()` — `onlyOwner`
- `sendAward()` — `onlyOwner`
- `countRecommend()` — gated to `owner` **or one of six hardcoded addresses**

All three take admin-supplied `startLength`/`endLength` index ranges into `invests[]` / `indexMapping[]`. This means the **owner personally decides which users, and in what order, get processed and paid** — there is no guarantee or on-chain enforcement that every depositor is eventually included. An admin (or anyone who obtained one of the six hardcoded keys) could simply stop calling these functions for ordinary users while continuing to route the shrinking ETH balance toward favored addresses.

### 2. A public state-mutating function with no access control
```solidity
function remedy(address userAddress, uint freezeAmount, string inviteCode,
                 string beInvitedCode, uint freeAmount, uint times) public {
    require(actStu == 0, "this action was closed");
    ...
    userMapping[userAddress] = user;   // arbitrary balance write
}
```
`remedy()` is declared `public` with **no `onlyOwner` modifier and no `msg.sender` check** — the sole guard is `actStu == 0`, a flag the owner can flip via `closeAct()`, but which defaults to open. Any external account could call `remedy()` directly and credit itself (or any address) with an arbitrary `freeAmount`/`freezeAmount`, then withdraw it through `userWithDraw()`. This is a textbook missing-access-control bug on a function whose name ("remedy") suggests it was meant only for internal admin corrections.

### 3. Front-runnable invite-code binding
```solidity
address userAddressCode = addressMapping[inviteCode];
if (userAddressCode == 0x0000000000000000000000000000000000000000) {
    addressMapping[inviteCode] = userAddress;
}
```
Present in both `invest()` and `remedy()`. Invite codes are bound to whichever address uses them **first** — a purely mempool-observable race. An attacker could watch a victim's pending `invest()` transaction, resubmit the same invite code with a higher gas price, and capture the referral binding (and any commission logic tied to it) for themselves. Clément Lesaege's public Reddit disclosure focused primarily on this exploit path.

### 4. (Historical) Public fund-drain function
The version deployed before July 29, 2019 had:
```solidity
function sendFeeToAdmin(uint amount) public { ... } // no access control
```
which let *anyone* trigger a transfer of contract balance to a hardcoded admin address — this is how the original 2,662 ETH drain occurred. The July 29 redeploy scoped it down to `private`, called only internally from `invest()`:
```solidity
function sendFeetoAdmin(uint amount) private {
    address adminAddress = 0x854D359A586244c9E02B57a3770a4dC21Ffcaa8d;
    adminAddress.transfer(amount/25);   // 4% skim on every deposit
}
```
This fixed the *public* drain vector but preserved a hardcoded, non-user-consented 4% fee on every deposit routed to an address the users had no visibility into or control over.

> **Note on "unbounded array gas-limit DoS":** Public write-ups on this incident (Castonguay's Medium retrospective, Lesaege's Reddit disclosure, contemporaneous press coverage from The Block / CryptoGlobe / Crypto.news) do **not** document a confirmed exploit where a growing `invests[]` array was used to intentionally push a function past the block gas limit and lock out withdrawals. `userWithDraw()` itself is O(1) and does not iterate over the array. What **is** documented is that FairWin's contract, due to generally poor coding practices and heavy per-deposit computation, was responsible for an outsized and growing share of Ethereum's total gas usage (60%+ at its peak) — a network-cost/inefficiency problem distinct from a proven gas-limit DoS attack. This distinction is called out here for accuracy.

---

## Faulty / Sensitive Functions

| Function | Visibility | Access Control | Issue |
|---|---|---|---|
| `remedy(...)` | `public` | **None** (only `actStu == 0`) | Anyone can mint arbitrary withdrawable balance to any address |
| `invest(...)` | `public payable` | None (by design — deposit entrypoint) | Contains front-runnable invite-code binding |
| `countShareAndRecommendedAward(...)` | `external` | `onlyOwner` | Owner chooses which index range of deposits gets rewarded |
| `sendAward(...)` | `external` | `onlyOwner` | Owner chooses which index range of users gets paid out; controls fund egress |
| `countRecommend(...)` | `public` | `owner` **or** 6 hardcoded addresses | Multiple privileged actors beyond the declared owner |
| `execute(...)` | `private` | N/A | Recursive referral payout walk, invoked by the above |
| `sendFeetoAdmin(uint amount)` | `private` (was `public` pre-7/29) | Internal only (post-fix) | Hardcoded 4% skim to admin address on every deposit |
| `userWithDraw(address)` | `public` | `msg.sender == userAddress` | Pays out only what `freeAmount` says — and `freeAmount` is only ever set by the functions above |
| `isEnoughBalance(uint)` | `private view` | N/A | Silently pays out less than owed once contract balance runs low, masking insolvency |

---

## Attack Flow — Why This Happened

```
 1. Users deposit ETH via invest(), between 1–15 ETH, providing an
    invite/referral code.
        │
        ▼
 2. Deposits are recorded in the `invests[]` array and `userMapping`,
    but NOT immediately withdrawable — freeAmount stays 0 initially.
        │
        ▼
 3. Only the OWNER (via sendAward / countShareAndRecommendedAward /
    countRecommend) can walk the invests[] / indexMapping[] arrays
    and credit freeAmount to specific users, based on admin-chosen
    index ranges.
        │
        ▼
 4. Because payout is entirely owner-discretionary, and remedy()
    additionally allows *anyone* to self-credit freeAmount with zero
    access control, the system has no on-chain guarantee that
    deposits are honored fairly, in order, or at all.
        │
        ▼
 5. Researchers privately investigate (Sept 11–25, 2019), confirm the
    front-running bug and the admin's unilateral control over payouts,
    and attempt (and fail) to get FairWin's team / exchange partners
    (Huobi) to respond.
        │
        ▼
 6. Public disclosure on Sept 26, 2019, with the contract holding
    ~50,000 ETH (~$8M). This triggers a mass rush of legitimate users
    trying to withdraw via userWithDraw(), racing the admins who
    retain full control over who gets processed and paid.
        │
        ▼
 7. Because isEnoughBalance() silently degrades payouts once the
    contract balance runs low, and the admin fully controls the
    ordering of payout batches, later/unprocessed users are left with
    nothing once the balance hits zero.
        │
        ▼
 8. By Sept 30, 2019 (4 days later), the contract balance is 0.
    ~40–50k ETH that was present at disclosure never reaches ordinary
    depositors.
```

**Root cause in one sentence:** FairWin never gave users an unconditional, code-enforced right to their deposits — every payout path ran through owner-controlled, index-range-gated functions, and one of the "internal correction" functions (`remedy`) additionally had no access control at all, meaning the system was insecure both *by design* (admin discretion) and *by bug* (missing modifier).

---

## Loss Incurred & Impact

- **Total ETH ever received by the contract:** ~687,598 ETH (~**$125,000,000**) over its lifetime.
- **ETH present at time of public disclosure (Sept 26, 2019):** ~50,000 ETH (~$8M).
- **ETH remaining by Sept 30, 2019 (collapse):** **0 ETH** — drained over 4 days.
- **Effective user loss:** tens of thousands of ETH belonging to depositors who deposited late or were not prioritized in admin-controlled payout batches; commonly cited as **~40,000 ETH (~$8M+ at the time)** lost by users who could not withdraw in time.
- **Network impact:** FairWin was responsible for over **60% of Ethereum's gas usage** at its peak (per ETH Gas Station data cited by researchers), and is believed to have contributed to Ethereum miners raising the block gas limit in September 2019 to relieve congestion widely (mis)attributed at the time to Tether's Omni→ERC-20 migration.
- **Reputational impact:** Highlighted the risks of unaudited, closed-source-team gambling/Ponzi dApps targeting non-technical users (FairWin was disproportionately promoted in Chinese-language crypto communities), and the danger of "audited"/"secure" marketing claims made by project teams with no independent verification (FairWin's own site claimed the code had been "securely authenticated" even after disclosure).

---

## Timeline of Disclosure

| Date (2019) | Event |
|---|---|
| Jul 27 | Earlier contract version drained of 2,662 ETH via public `sendFeeToAdmin` — done by a ConsenSys Diligence researcher (Daniel Luca) to demonstrate the bug, not maliciously |
| Jul 29 | Patched contract redeployed; `sendFeeToAdmin` made `private`; underlying admin-discretion design unchanged |
| Sep 11 | Researchers first investigate FairWin due to abnormal gas usage |
| Sep 12 | Original July hack traced back to Daniel Luca; contact made |
| Sep 15 | Front-running (invite-code race) exploit identified |
| Sep 15–25 | Private coordination among researchers (Castonguay, Luca, Green, Denley, Matiiasevych, Wolever, Monahan, and others); attempts to contact FairWin's team and exchange partners (Huobi) go largely unanswered |
| Sep 26 | Public disclosure of vulnerabilities (without full technical detail); contract holds ~50,000 ETH |
| Sep 29 | Clément Lesaege publishes full technical disclosure on Reddit; contract down to ~19,000 ETH |
| Sep 30 | Contract balance reaches 0 ETH; FairWin collapses |

---

## The Fix

**There was no protocol-level fix for the deployed contract** — FairWin was not upgradeable, had no proxy pattern, and the team did not meaningfully respond to disclosure beyond publicly denying the vulnerabilities and posting a follow-up promotional video. The "fix," such as it was, occurred in two forms:

1. **Partial self-remediation between contract versions (July 2019):** the team changed `sendFeeToAdmin` from `public` to `private` after the first drain, closing that specific public-fund-drain vector. This did **not** address `remedy()`'s missing access control, the owner-gated payout design, or the invite-code front-running issue — all of which remained exploitable through to the contract's collapse.
2. **Community/user-driven mitigation:** the only effective "fix" was public disclosure itself — researchers pushed users to withdraw immediately and stop depositing, which is what drained the contract to zero over four days. This was damage limitation, not a code fix.

### What a proper fix would have required
- Add `onlyOwner` (or better: remove entirely, or replace with a transparent, rate-limited, non-discretionary claim mechanism) on `remedy()`.
- Replace owner-controlled, admin-batched payout (`sendAward`, `countShareAndRecommendedAward`, `countRecommend`) with a **pull-based, user-initiated claim function** where payout amount is deterministically computable on-chain from deposit history, with no admin gating on *who* gets processed.
- Bind invite codes using a commit-reveal scheme (or simply not gate rewards on first-come address binding) to remove the front-running incentive.
- Use a time-locked, multisig-controlled, and publicly disclosed fee address instead of a silent hardcoded skim.
- Independent third-party audit before holding user funds, with the audit report published — not just claimed.

---

## Lessons for Solidity Developers

- **Never leave a state-mutating `public`/`external` function without an explicit access-control modifier** — `remedy()` is the canonical example of what happens when a function is written for "internal/admin use" but the modifier is forgotten.
- **Avoid designs where fund release depends on discretionary, admin-batched processing.** If an owner can choose *which* users get paid and *when*, the contract is a trust-based custodial system, not a trustless one, regardless of what the marketing claims.
- **Don't bind economically meaningful state (referral codes, whitelist slots, etc.) to "first caller wins" without protecting against front-running** (commit-reveal, or accept the tx sender identity is public in the mempool).
- **A "fix" that removes one specific exploit path does not make a contract safe** if the broader trust/authorization model is still unsound — FairWin patched the July drain but left the fundamental admin-discretion problem in place, which is what ultimately killed it.
- **Marketing claims of "audited" or "secure" mean nothing without a public, attributable audit report.** FairWin claimed its code was "securely authenticated" even after independent researchers disclosed multiple critical bugs.

---

## References

- Philippe Castonguay, *"The Collapse of FairWin's ~$125m Ponzi Scheme"*, Medium, Oct 1, 2019.
  https://medium.com/@PhABC/the-collapse-of-fairwins-125m-ponzi-scheme-61a66b273420
- Clément Lesaege, verified contract source mirror (GitHub Gist), Sept 27, 2019.
  https://gist.github.com/clesaege/815d2e2eb2bcac96be732af0bfc81ac1
- FairWin contract on Etherscan.
  https://etherscan.io/address/0x01eacc3ae59ee7fbbc191d63e8e1ccfdac11628c
- Clément Lesaege, Reddit vulnerability disclosure post ("Vulnerability Disclosure: FairWin Frontrunning..."), r/ethereum, Sept 29, 2019.
- *"Ethereum developers find 'critical vulnerabilities' in 'Ponzi scheme' FairWin"*, The Block, Sept 27, 2019.
  https://www.theblock.co/linked/41307/ethereum-developers-find-critical-vulnerabilities-in-ponzi-scheme-fairwin
- *"Ethereum Dev Reports Critical Vulnerabilities in Gambling App FairWin"*, CryptoGlobe, Sept 30, 2019.
  https://www.cryptoglobe.com/latest/2019/09/ethereum-dev-reports-critical-vulnerabilities-in-gambling-app-fairwin/
- *"FairWin Responds to Accusations of Ethereum-Consuming 'Ponzi Scheme'"*, Crypto.news, Sept 30, 2019.
  https://crypto.news/fairwin-ethereum-consuming-ponzi-scheme/
- *"Alleged ETH Ponzi Scheme FairWin May Have Snuck Off With User Funds"*, CryptoGlobe.
  https://www.cryptoglobe.com/latest/2019/10/alleged-eth-ponzi-scheme-fairwin-may-have-snuck-off-with-user-funds/
- Daniel Luca, *Karl* — the contract-monitoring tool used to first identify the original 2019-07-27 exploit.
  https://github.com/cleanunicorn/karl

