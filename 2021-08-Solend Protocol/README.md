# Solend Protocol — `UpdateReserveConfig` Account Validation Exploit (August 2021)

## Overview

| | |
|---|---|
| **Protocol** | Solend (Solana lending/borrowing protocol) |
| **Date** | August 2021 |
| **Vulnerability Class** | Improper account / authentication validation (missing relational account check) |
| **Root Instruction** | `UpdateReserveConfig` |
| **Loss** | ~$16,000 (USD) |
| **Status** | Patched |

Solend is an algorithmic, decentralized lending and borrowing protocol built on Solana, modeled after Aave/Compound but designed to take advantage of Solana's high throughput and low fees. In August 2021, an attacker exploited a flaw in Solend's `UpdateReserveConfig` instruction to rewrite the risk parameters of a legitimate, live reserve and profit from resulting wrongful liquidations.

---

## Background: Solana Account Model

Unlike EVM-based smart contracts, Solana programs don't automatically know which accounts belong to which piece of on-chain state. Every account referenced in an instruction is supplied explicitly by the client in the transaction, and it is the **program's own responsibility** to validate:

1. **Ownership** — is this account actually owned by my program?
2. **Signer status** — did the correct authority sign the transaction?
3. **Relational integrity** — does this account actually *belong to* / correctly *correspond with* the other accounts passed alongside it?

Solend's bug was a failure of validation category #3.

### Solend's data model (relevant to this bug)

- **`LendingMarket`** — represents one market instance and stores an `owner` pubkey (the market's authority).
- **`Reserve`** — one per supported asset (e.g., SOL, USDC), storing a `lending_market` field that points back to the `LendingMarket` it belongs to. It also stores config values such as `liquidation_threshold` and `liquidation_bonus`.
- **`UpdateReserveConfig`** — an instruction meant to let a market's legitimate owner modify a reserve's risk configuration.

Anyone can permissionlessly call `InitLendingMarket` to create a brand-new market and become its owner — market creation itself requires no special privilege.

---

## The Vulnerability

The vulnerable `UpdateReserveConfig` handler took, among others, these accounts:

- `reserve` — the target reserve to update
- `lending_market` — claimed to be the market that owns the reserve
- `lending_market_owner` (signer) — claimed to be that market's authority

The validation logic performed roughly:

- ✅ Checked `lending_market_owner` signed the transaction
- ✅ Checked `lending_market_owner.key == lending_market.owner`
- ❌ **Did NOT check** that `reserve.lending_market == lending_market.key()`

In other words, the program confirmed the signer legitimately owned *some* lending market — but never confirmed it was *the specific* lending market the target reserve actually belonged to. Ownership was authenticated in isolation, without validating the relationship between the two accounts being combined in the same instruction.

---

## Attack Flow

1. **Create a fake market.** The attacker called `InitLendingMarket` to create their own, brand-new `LendingMarket` account, setting themselves as `owner`. This is a fully permissionless action.
2. **Mix real and fake accounts.** The attacker called `UpdateReserveConfig`, supplying:
   - the **real**, live Solend `reserve` account (holding genuine user deposits/borrows)
   - their **own attacker-controlled** `lending_market` account (not the market the reserve actually belonged to)
   - themselves as the signing "owner"
3. **Validation passes incorrectly.** Since the program only checked "does the signer own the supplied market" — and never "does the supplied market own the supplied reserve" — the check succeeded. The attacker did, after all, legitimately own the fake market they had just created.
4. **Malicious parameter rewrite.** This let the attacker overwrite the real reserve's risk parameters, notably the **liquidation threshold** and **liquidation bonus**, setting them to attacker-favorable values (e.g., making positions liquidatable prematurely, or making liquidation bonuses abnormally generous).
5. **Extraction via liquidation.** The attacker then performed liquidations against real borrower positions using the manipulated parameters, extracting value that would not have been available under the correct risk configuration.
6. **Detection & response.** The Solend team identified and halted the exploit before further damage occurred.

### Why this happened — root cause

This is a textbook instance of a broader Solana anti-pattern: **validating an account in isolation instead of validating its relationship to other accounts referenced in the same instruction.** The instruction correctly authenticated *"is this signer an owner of a market"* but never verified *"is this market the one this specific reserve actually belongs to."* Because Solana's runtime does not enforce any implicit linkage between accounts passed into an instruction, this relational check has to be explicitly written by the developer — and it was missing here.

---

## Impact & Loss

- **Financial loss:** Approximately **$16,000 (USD)** was extracted through wrongful/incorrect liquidations enabled by the manipulated reserve parameters.
- **Trust/operational impact:** While the dollar amount was comparatively small next to other DeFi exploits of the era, the incident exposed a systemic class of bug (cross-account validation gaps) in Solana lending logic — directly relevant given Solend forked its core lending program from the Solana Labs `token-lending` reference implementation, meaning any other protocol using that base code could have carried the same flaw.
- **Protocol response:** Solend halted the exploit path and shipped a patch adding the missing relational check.

---

## The Fix

The patched instruction now validates the reserve-to-market relationship **before** trusting any authority derived from the supplied market account:

```rust
let mut reserve = Box::new(Reserve::unpack(&reserve_info.data.borrow())?);
if reserve_info.owner != program_id {
    msg!("Reserve provided is not owned by the lending program");
    return Err(LendingError::InvalidAccountOwner.into());
}

// The critical fix: confirm the supplied lending_market is the ACTUAL
// market this reserve belongs to — not just *a* market the signer owns.
if &reserve.lending_market != lending_market_info.key {
    msg!("Reserve lending market does not match the lending market provided");
    return Err(LendingError::InvalidAccountInput.into());
}

let lending_market = Box::new(LendingMarket::unpack(&lending_market_info.data.borrow())?);
// ... only after this point is authority (owner / risk_authority) checked
```

By requiring `reserve.lending_market == lending_market_info.key()` up front, an attacker's freshly created, self-owned market can no longer be substituted in to pass authority checks against a reserve it doesn't actually control. This pattern — asserting relational/ownership links between every pair of interacting accounts — is now standard practice across Solana program audits, and frameworks like Anchor bake in equivalent protection via `has_one` constraints (though native/non-Anchor programs, as much of early Solend was, must add these checks manually).

---

## Real-World Contract & Function References

- **Repository:** [`solendprotocol/solana-program-library`](https://github.com/solendprotocol/solana-program-library) — Solend's fork of the Solana Labs `token-lending` program.
- **Relevant source file:** `token-lending/program/src/processor.rs`
- **Vulnerable / fixed function:** `process_update_reserve_config` (dispatched via the `UpdateReserveConfig` instruction variant in `instruction.rs`)
- **Key validation line (the fix):**
  ```rust
  if &reserve.lending_market != lending_market_info.key { ... }
  ```
- **Underlying reference implementation:** Solana Labs' original [`spl-token-lending`](https://github.com/solana-labs/solana-program-library/tree/master/token-lending) program, which Solend forked and extended.
- **Audit reference (Solend):** `token-lending/audit` directory in the Solend repo, referenced by exchange listing pages (e.g., KuCoin) as the audited source path.

> **Note:** The `main`/`master` branch of the repository today reflects the **patched** code. The actual vulnerable snapshot from August 2021 would need to be located in the commit history prior to the fix being merged, not in current HEAD.

---

## Lessons Learned

1. **Never validate an account in isolation.** Every account passed into a Solana instruction should be checked not only for ownership and signer status, but also for its *relationship* to every other account it's used alongside in that same instruction.
2. **Authority checks must be scoped to the specific resource being modified.** "This signer owns *a* valid market" is a fundamentally different (and weaker) claim than "this signer owns *the* market that owns *this* reserve." Confusing the two opens the door to substitution attacks.
3. **Permissionless account creation is a double-edged sword.** Because anyone can create a new `LendingMarket` at will, any instruction that trusts data read from a client-supplied market account must independently verify that account is the *correct* one for the operation — not merely a validly structured one.
4. **Forked reference code inherits reference code's bugs.** Since Solend forked Solana Labs' `token-lending` program, this class of gap was a shared risk across any protocol built from the same base — reinforcing the need for independent audits even when starting from "battle-tested" reference implementations.
5. **This bug class recurs across the Solana ecosystem.** Similar missing relational/ownership checks between accounts have appeared in other Solana DeFi incidents (e.g., Cashio, Nirvana Finance), which is why "does account A actually belong to account B, not just to *a* valid B" is now a standard audit checklist item for Solana programs.
6. **Defense in depth via frameworks.** Anchor-based Solana programs can reduce (though not eliminate) this risk class using declarative `has_one` constraints, which auto-generate the equivalent relational check — but native Rust programs must implement and test these checks manually, as Solend's early codebase did.

---

## Summary

The Solend `UpdateReserveConfig` incident is a canonical example of an **account confusion / missing relational validation** vulnerability on Solana. By permissionlessly creating their own lending market and pairing it with a legitimate protocol reserve in a single instruction call, an attacker bypassed authority checks that verified ownership in isolation rather than validating the actual link between the two accounts. The result was unauthorized modification of liquidation parameters and ~$16K extracted via wrongful liquidations, remediated by adding an explicit `reserve.lending_market == lending_market.key()` check ahead of any authority-based logic.