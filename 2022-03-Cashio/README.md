# Cashio Hack (March 2022) — Infinite Mint via Missing Account Validation

## Overview

| | |
|---|---|
| **Protocol** | Cashio (`$CASH`) — decentralized stablecoin on Solana |
| **Date** | March 23, 2022, ~08:15–09:00 UTC |
| **Vulnerability class** | Missing account validation → fake account injection → infinite mint |
| **Loss** | ~$48–52.8M |
| **Audit status** | Unaudited |
| **Root cause file** | [`programs/brrr/src/saber.rs`](https://github.com/cashioapp/cashio/blob/master/programs/brrr/src/saber.rs) |

Cashio was a decentralized stablecoin fully backed by interest-bearing Saber USD liquidity provider (LP) tokens. It used **Arrow Protocol** to stake LP tokens for yield and **Crate Protocol**-style logic to mint `$CASH` against that collateral. An attacker exploited a gap in Cashio's collateral-validation logic to mint roughly **2 billion `$CASH`** tokens against fake, worthless collateral, then swapped the counterfeit tokens for real stablecoins before the protocol could react.

---

## Description of the Issue

To mint `$CASH`, a user deposits collateral (Saber LP tokens routed through an Arrow vendor account). Before minting, Cashio's `brrr` program runs a chain of account-validation checks meant to prove that:

1. the supplied **bank** account actually corresponds to the collateral being deposited,
2. the **crate/collateral token accounts** match the expected mint, and
3. the underlying **Saber swap / Arrow** accounts are the genuine ones tied to that collateral.

Two `Validate` implementations carry this logic: `BrrrCommon::validate()` and `SaberSwapAccounts::validate()`. The second of these — the one that verifies the Saber/Arrow side of the collateral — checks several fields (`vendor_miner.mint`, `pool_mint`, and both token reserves) but **never checks that `self.arrow.mint` matches the mint the protocol actually expects.** Every check present in the function is internally consistent — but internally consistent with whatever fake accounts the attacker supplies, since nothing anchors any of them back to a protocol-trusted source of truth.

This is a textbook Solana **fake account / missing ownership-chain validation** bug: Anchor/Solana programs must explicitly verify every account's identity, owner, and mint — the runtime does not do this for you. Skip one link in that chain, and an attacker can hand the program an account of the *right shape* but the *wrong provenance*.

---

## Attack Flow

1. **Attacker mints a worthless token.** They create their own SPL mint and fund it with a large supply (reports cite ~2,000,000,000 units) of a token with zero real value.
2. **Attacker forges a fake bank.** Cashio's bank-verification check (in `BrrrCommon::validate()`) only requires that the supplied bank's mint match the collateral's mint — so the attacker creates a brand-new "bank" account whose mint is their own fake token. This trivially satisfies `assert_keys_eq!(self.bank.crate_mint, self.crate_mint)` and related checks, since the attacker controls both sides.
3. **Attacker forges a fake Arrow / Saber-swap account.** They call `deposit_vendor()`-style flows to create a fake Arrow vendor account and a fake Saber swap structure wired up to their own worthless mint.
4. **`SaberSwapAccounts::validate()` passes anyway.** Because this function checks internal consistency (pool mint ↔ reserves ↔ vendor miner mint) but never validates `arrow.mint` against a protocol-trusted mint, the forged structure sails through.
5. **`print_cash` mints real `$CASH` against fake collateral.** With every validation check green, the attacker calls the mint instruction using their worthless token as "collateral" and receives ~2 billion real `$CASH`.
6. **Cash-out.** The attacker swapped part of the minted `$CASH` for Saber USDT-USDC LP tokens and redeemed/swapped the rest through Saber for UST and USDC, then bridged a large share off Solana (reportedly via Wormhole) before the team could freeze activity.
7. **Peg collapse.** `$CASH`'s price crashed from $1 to roughly $0.00005 as the fraudulent supply flooded the market and collateral backing evaporated.

The attacker also left a message embedded in a transaction claiming that "accounts with less than 100k have been returned" and the rest "donated to charity" — a claim that was never independently verified.

---

## The Faulty Function

**File:** [`programs/brrr/src/saber.rs`](https://github.com/cashioapp/cashio/blob/master/programs/brrr/src/saber.rs) (Cashio `brrr` program, Anchor/Rust)

```rust
impl<'info> Validate<'info> for SaberSwapAccounts<'info> {
    fn validate(&self) -> Result<()> {
        assert_keys_eq!(self.arrow.vendor_miner.mint, self.pool_mint);
        assert_keys_eq!(self.saber_swap.pool_mint, self.pool_mint);
        assert_keys_eq!(self.saber_swap.token_a.reserves, self.reserve_a);
        assert_keys_eq!(self.saber_swap.token_b.reserves, self.reserve_b);
        Ok(())
    }
}
```

**What's missing:** there is no assertion tying `self.arrow.mint` (the actual collateral mint of the Arrow vendor account) back to an expected, protocol-trusted mint. All four checks present validate relationships *between the supplied accounts themselves* — none of them validate that the supplied accounts are the *legitimate* ones in the first place.

This combines with the related, equally under-constrained check in `BrrrCommon::validate()` (in the same program), which trusted `self.collateral.mint == self.saber_swap.arrow.mint` without independently anchoring `arrow.mint` to anything the protocol controls:

```rust
impl<'info> Validate<'info> for BrrrCommon<'info> {
    fn validate(&self) -> Result<()> {
        assert_keys_eq!(self.bank, self.collateral.bank);
        assert_keys_eq!(self.bank.crate_mint, self.crate_mint);
        assert_keys_eq!(self.crate_token, self.crate_collateral_tokens.owner);
        assert_keys_eq!(self.crate_mint, self.crate_token.mint);
        assert_keys_eq!(self.crate_collateral_tokens.mint, self.collateral.mint);
        // saber swap
        self.saber_swap.validate()?;
        assert_keys_eq!(self.collateral.mint, self.saber_swap.arrow.mint);
        Ok(())
    }
}
```

Together, these two functions formed a closed loop of self-consistent checks that an attacker could satisfy entirely with self-created (fake) accounts.

---

## Real-World Contract / Program References

- **Cashio monorepo:** https://github.com/cashioapp/cashio
- **Vulnerable file:** https://github.com/cashioapp/cashio/blob/master/programs/brrr/src/saber.rs
- **`brrr` program** — handles printing/burning of `$CASH` using Saber LP Arrows as collateral (the program containing the bug)
- **`bankman` program** — allowlists which collateral tokens/banks are legitimate (the layer that *should* have anchored the mint check but didn't fully close the gap)
- **Exploit workshop / PoC environment:** https://github.com/NaryaAI/cashio-exploit-workshop — a local Anchor test environment for reproducing the bug in `poc/src/main.rs`

### On-chain artifacts (Solana / Solscan)

| Item | Address |
|---|---|
| `$CASH` token mint | `CASHVDm2wsJXfhj6VWxb7GiMdoLc17Du7paH4bNr5woT` |
| Fake LP token minted by attacker | `GoSK6XvdKquQwVYokYz8sKhFgkJAYwjq4i8ttjeukBmp` |
| Fake Arrow-vendor token minted | `GCnK63zpqfGwpmikGBWRSMJLGLW8dsW97N4VAXKaUSSC` |

Look these up on [Solscan](https://solscan.io) or [Solana Explorer](https://explorer.solana.com) — Solana doesn't have an Etherscan-style "verified source" tab, so the on-chain program bytecode has to be cross-referenced manually against the GitHub source.

---

## Loss and Impact

- **Funds stolen:** approximately **$48–52.8 million**, depending on which downstream swaps/bridges are counted.
- **Tokens minted:** ~**2,000,000,000 `$CASH`** created from nothing.
- **Peg collapse:** `$CASH` fell from $1.00 to roughly **$0.00005** — effectively zero — destroying the token's usability and any remaining holder value.
- **TVL collapse:** Cashio's total value locked reportedly fell from ~$28.8M to under $600K within a day of the exploit.
- **Trust/ecosystem impact:** Cashio was one of several high-profile 2022 Solana "fake account" exploits (alongside Wormhole and others), intensifying scrutiny of Solana/Anchor programs' account-validation practices and contributing to a broader wave of DeFi security research on this exact bug class.
- **Project outcome:** Cashio never recovered; the protocol effectively shut down following the incident.

---

## The Fix

The core fix is conceptually simple, even though the actual patch details were never widely publicized (Cashio ceased active operation shortly after the hack): **add the missing mint-provenance check.**

Concretely, `SaberSwapAccounts::validate()` needed an additional assertion binding `self.arrow.mint` to a value the protocol itself controls and trusts — for example, validating it against a `bankman`-registered allowlisted mint, or against the `crate_collateral_tokens.mint` established earlier in `BrrrCommon::validate()`, rather than only checking relationships between attacker-suppliable accounts. In pseudocode, something like:

```rust
// Missing check that should have been added:
assert_keys_eq!(self.arrow.mint, self.expected_collateral_mint);
```

More broadly, the structural fix that the ecosystem converged on afterward is:

- **Never trust an account's internal fields until the account itself has been verified against a program-derived address (PDA) or an allowlist the protocol owns.**
- Every `Validate` function must trace a complete, unbroken chain from a trusted root (e.g., a PDA seeded by the program, or a registry account the program itself created) down to every leaf account used in a sensitive instruction — a single unchecked "sibling equals sibling" comparison isn't enough if both siblings can be attacker-supplied.
- Adopt automated tooling (e.g., Sec3/Soteria, Ottersec, or Anchor's own account-constraint macros like `has_one`, `seeds`, `constraint =`) to catch missing constraints at compile/audit time.
- **Get audited before mainnet deployment with real collateral** — Cashio was explicitly unaudited, and this exact bug class (fake account substitution) was already known in the Solana security community at the time.

---

## Lessons Learned

1. **Validate the full provenance chain, not just internal consistency.** Checking that account A's field equals account B's field is meaningless if both A and B can be created by the attacker. Every check needs at least one leg anchored to something the protocol itself derived or owns (a PDA, a hardcoded program ID, an allowlist entry).
2. **"Looks right" isn't "is right" on Solana.** Anchor's type system verifies account *discriminators* and *ownership by a program*, but it does not automatically verify that the *content* (e.g., a `mint` field) matches business logic expectations — that's the developer's job, on every single field that matters.
3. **Composability multiplies attack surface.** Cashio's design chained three protocols together (Cashio → Arrow → Saber). Each integration point is a place where trust assumptions can silently break down; the vulnerability lived exactly at one of these seams.
4. **Unaudited ≠ acceptable for real-money protocols.** Multiple essential checks were missing from an otherwise heavily-checked codebase — the kind of gap a focused audit or thorough fuzz/property-testing pass is specifically designed to catch.
5. **Monitoring and circuit breakers matter.** There was a real-world delay between the exploit starting and the team's public warning to stop minting — faster on-chain anomaly detection (e.g., alerting on abnormal mint volume) could have limited the damage.
6. **This bug class recurred across Solana in 2022.** Wormhole and other protocols suffered conceptually similar "fake account" exploits in the same period, underscoring that this wasn't a one-off mistake but a systemic risk pattern for early Anchor-based programs.

---

## References

- Ackee Blockchain — [2022 Solana Hacks Explained: Cashio](https://ackee.xyz/blog/2022-solana-hacks-explained-cashio/)
- CertiK — [Cashio App Incident Analysis](https://www.certik.com/resources/blog/cashio-app-incident-analysis)
- Halborn — [Explained: The Cashio Hack (March 2022)](https://www.halborn.com/blog/post/explained-the-cashio-hack-march-2022)
- Decrypt — [Solana Stablecoin Project Cashio Plummets to Zero After Multi-Million Dollar Hack](https://decrypt.co/95772/solana-stablecoin-project-cashio-plummets-zero-multi-million-dollar-hack)
- AMBCrypto — [Decoding the if, but, and so of 'Cashio Hack'](https://ambcrypto.com/decoding-the-if-but-and-so-of-cashio-hack/)
- Sec3 (formerly Soteria) — [Solana Vulnerability Research & Blog](https://sec3.dev/blog)
- Cashio source code — https://github.com/cashioapp/cashio
- Exploit reproduction workshop — https://github.com/NaryaAI/cashio-exploit-workshop
- Unofficial post-mortem by Samczsun (Paradigm) — referenced via Twitter/X, March 2022