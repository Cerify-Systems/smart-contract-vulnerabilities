# Wormhole Bridge Exploit — February 2, 2022

---

## Overview

| | |
|---|---|
| **Date** | February 2, 2022, ~5:58 PM UTC |
| **Protocol** | Wormhole (cross-chain token bridge, Solana ↔ Ethereum) |
| **Chain affected** | Solana program |
| **Vulnerability class** | Missing account validation / improper signature verification |
| **Loss** | ~120,000 wrapped ETH (wETH), ≈ **$320–326 million** |
| **Status** | Funds replenished in full by Jump Crypto within days; no user losses realized |

Wormhole is a "lock-and-mint" bridge: a user locks a token on the source chain (e.g., ETH on Ethereum), and Wormhole mints a wrapped equivalent (wETH) on the destination chain (Solana). Minting is only supposed to happen after Wormhole's off-chain "Guardian" network has cryptographically signed a message (a VAA — Validator Action Approval) attesting that the deposit really happened. The Solana program is the component responsible for checking those signatures before honoring a mint request — and that check is exactly what failed.

---

## Attack Flow

1. **Setup.** The attacker prepared a spoofed account that mimicked Solana's built-in `Sysvar1nstructions` account — the sysvar Solana programs normally use to introspect other instructions in the same transaction.
2. **Bypass signature verification.** The attacker called Wormhole's `verify_signatures` instruction, but instead of passing the real Instructions sysvar, they passed their fake account loaded with fabricated data designed to look like a successful prior call to the `Secp256k1` signature-verification program.
3. **Forge a "verified" signature set.** Because the check for whether Secp256k1 had actually run never validated *which* account it was reading, the forged data was accepted as proof that legitimate guardian signatures existed.
4. **Create a fraudulent VAA.** With a bogus "verified" `SignatureSet` in hand, the attacker called `post_vaa`, producing a Validator Action Approval that claimed 120,000 ETH had been legitimately deposited on the Ethereum side — no real deposit had occurred.
5. **Mint on Solana.** The attacker called `complete_wrapped`, which trusted the fraudulent VAA and minted 120,000 wETH directly into the attacker's own Solana account.
6. **Cash out.** The attacker swapped a portion of the minted wETH and bridged roughly 93,750 ETH back across to Ethereum, where it sat in a wallet.

```
verify_signatures (fed a fake "Instructions sysvar")
        │
        ▼
load_instruction_at()  ──▶ trusts fake account, "confirms" Secp256k1 ran
        │
        ▼
SignatureSet marked as verified (fraudulently)
        │
        ▼
post_vaa()  ──▶ accepts the forged VAA as authentic
        │
        ▼
complete_wrapped()  ──▶ mints 120,000 wETH to attacker
```

---

## Why This Vulnerability Happened (Root Cause)

The root cause was a **missing account validation**, compounded by **use of a deprecated, unsafe API**:

- Solana programs receive an *array* of accounts with each instruction call. It is the program's own responsibility to check that each account passed in is actually the account it claims to be (by address) — Solana itself does not enforce this.
- Wormhole's `verify_signatures` function needed to confirm the Secp256k1 native program had run earlier in the same transaction. To do this, it called `load_instruction_at`, an instruction-introspection helper that reads from whatever account is passed in as the "Instructions sysvar" — **without checking that this account's address actually equals the real `Sysvar1nstructions` address.**
- A safer version of this function, `load_instruction_at_checked`, already existed and did perform that address check — but the deployed Wormhole code still used the older, unchecked variant.
- Because the program trusted the account's *position/role* in the call rather than verifying its *identity*, an attacker-supplied fake account was indistinguishable from the real sysvar as far as the program logic was concerned. This is a textbook **account confusion / missing signer-or-owner check** bug, a very common category in Solana program exploits.

**A darkly ironic contributing factor:** a fix for this exact issue had already been committed to Wormhole's public GitHub repository before the attack — it simply hadn't been deployed to mainnet yet. Because Wormhole's code was open source, it's widely believed the attacker discovered the bug by diffing the unreleased patch against the live deployed version.

---

## The Real-World Contract & Function

Wormhole's Solana bridge program is open source, and the vulnerable code is publicly visible at the pre-fix commit.

- **Repository (official):** https://github.com/wormhole-foundation/wormhole
- **Vulnerable file (pre-fix commit `ca509f2d73c0780e8516ffdfcaf90b38ab6db203`):**
  https://github.com/wormhole-foundation/wormhole/blob/ca509f2d73c0780e8516ffdfcaf90b38ab6db203/solana/bridge/program/src/api/verify_signature.rs
- **Vulnerable function:** `verify_signatures` (in `verify_signature.rs`), specifically its use of the deprecated `load_instruction_at` call to check that Secp256k1 had run
- **Downstream functions in the exploit chain:** `post_vaa` and `complete_wrapped`, both of which trusted the outcome of `verify_signatures` without an independent check

> Note: because the fix was later merged into the same repository's main branch, comparing the pre-fix commit above against the current `main` branch is a good way to see the exact diff that closed the hole.

---

## Loss & Impact

- **Direct loss:** ~120,000 wETH minted fraudulently, valued at roughly **$320–326 million** at the time — among the largest DeFi exploits ever recorded, and at the time the largest hack involving a Solana-connected protocol.
- **Market impact:** Wormhole's Solana program was temporarily halted while the team assessed the damage; wETH's peg was put at risk since it was now under-collateralized relative to real locked ETH on Ethereum.
- **Ecosystem impact:** Because Wormhole was (and remains) one of the most widely used bridges connecting Solana to the rest of DeFi, the exploit raised broader questions about bridge security models generally, not just this one implementation.
- **Financial resolution:** Jump Crypto (parent company of Jump Trading, and a primary backer of Wormhole/Certus One) replenished the full 120,000 ETH within about a day, fully covering the gap so that no bridge users lost funds. This was a unique outcome — most DeFi hacks of this size are never fully made whole.

---

## The Fix

- Replace the deprecated, unchecked `load_instruction_at` call with `load_instruction_at_checked`, which validates that the account passed in as the Instructions sysvar actually matches Solana's real `Sysvar1nstructions` address before trusting any data read from it.
- More broadly, this incident helped popularize the practice (now standard guidance for Solana program audits) of explicitly validating **every** account passed into an instruction — by address, owner, and/or signer status — rather than assuming an account is what its parameter name or position implies.

---

## Lessons Learned

1. **Never trust an account by position alone.** Solana's account-based model means any account can be passed into any slot in an instruction call. Programs must explicitly verify identity (address, owner program, signer flag) for every account they rely on, especially security-critical sysvars.
2. **Deprecated ≠ removed.** `load_instruction_at` remained callable for backward compatibility even after a safer replacement existed. Deprecated but still-functional APIs are a recurring source of real-world vulnerabilities — deprecation warnings need to be treated as action items, not just documentation notes.
3. **Open source cuts both ways.** Publishing fixes to a public repo before deploying them to production can hand attackers a roadmap. Security-critical patches for live, high-value contracts benefit from coordinated/private disclosure and rapid deployment windows, not silent public commits sitting unreleased.
4. **Signature verification is only as strong as its weakest delegation hop.** The trust chain here (`post_vaa` → `verify_signatures` → `Secp256k1` via sysvar introspection) had several hops; the failure of just one link (the sysvar identity check) undermined the entire chain. Multi-step trust delegation needs validation at every hop, not just the first or last.
5. **Insurance/backstop capital matters.** Jump Crypto's willingness and ability to make the bridge whole is a rare exception in DeFi hack history. It highlights the value (and cost) of having a well-capitalized backstop for critical infrastructure like bridges, which by design concentrate enormous value behind a single program's logic.
6. **Bridges are high-value, high-complexity targets.** Cross-chain bridges combine complex multi-chain state, custom cryptographic verification, and large pooled value — a combination that has made bridges (Wormhole, Ronin, Nomad, Harmony Horizon, and others) some of the most exploited categories of contracts in crypto history.

---

## References

- Wormhole GitHub repository: https://github.com/wormhole-foundation/wormhole
- Vulnerable file at pre-fix commit: https://github.com/wormhole-foundation/wormhole/blob/ca509f2d73c0780e8516ffdfcaf90b38ab6db203/solana/bridge/program/src/api/verify_signature.rs
- Halborn — "Explained: The Wormhole Hack (February 2022)": https://www.halborn.com/blog/post/explained-the-wormhole-hack-february-2022
- Kudelski Security — "Quick Analysis of the Wormhole Attack": https://kudelskisecurity.com/research/quick-analysis-of-the-wormhole-attack
- Merkle Science — "Hack Track: Analysis of the Wormhole Token Bridge Exploit": https://www.merklescience.com/blog/hack-track-analysis-of-wormhole-token-bridge-exploit
- Immunebytes — "Wormhole Bridge Hack – Feb 2, 2022 – Detailed Hack Analysis": https://immunebytes.com/blog/wormhole-bridge-hack-feb-2-2022-detailed-hack-analysis/
- MixBytes — "Bridge Bugs Overview": https://mixbytes.io/blog/bridge-bugs-overview

