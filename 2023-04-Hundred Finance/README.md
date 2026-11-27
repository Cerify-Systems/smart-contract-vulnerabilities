# Hundred Finance — Exchange-Rate Manipulation / Donation Attack

> **Category:** Oracle / accounting manipulation (donation attack) in a Compound V2 fork
>
> **Date:** April 15, 2023
>
> **Chain:** Optimism (a related, historically drained deployment was also affected)
>
> **Loss:** ~$7.4 million USD
>
> **Attacker address:** `0x155DA45D374A286d383839b1eF27567A15E67528`

---

## 1. Summary

Hundred Finance is a multi-chain lending protocol forked from **Compound V2**. Like Compound, it issues an interest-bearing "hToken" (e.g. `hWBTC`) for every asset supplied to the protocol, and tracks an internal `exchangeRate` between the hToken and its underlying asset to value a user's collateral and redemption rights.

On April 15, 2023, an attacker exploited an **empty/near-empty hWBTC market** on Optimism by directly transferring ("donating") a large amount of WBTC to the hToken contract — bypassing the normal `mint()` accounting path. Because the contract's exchange-rate calculation reads the **raw token balance** of the contract rather than an internally tracked supply value, this donation inflated the exchange rate by orders of magnitude. With virtually no other hWBTC in circulation, the attacker — as sole holder of a few wei of hWBTC — could redeem/borrow against a valuation representing nearly the entire pool, draining $7.4M in assorted assets (WBTC, ETH, USDC, DAI, USDT, sUSD, FRAX, SNX) from the protocol.

A secondary **rounding/precision error** in the redeem logic worsened the impact, letting the attacker extract slightly more value than the manipulated rate alone allowed.

---

## 2. Background: How hTokens Work

- Hundred Finance is a **Compound V2 fork**: for every underlying asset market, a corresponding `hToken` (analogous to Compound's `cToken`) is deployed.
- Users `mint()` hTokens by depositing the underlying asset; hTokens accrue value over time as borrowers pay interest.
- The `exchangeRate` between hToken and underlying asset determines:
  - How much underlying asset a user gets back when they `redeem()` hTokens.
  - How much **collateral value** a hToken balance represents when a user borrows against it.
- The formula (inherited directly from Compound V2's `CToken.sol`) is:

```solidity
exchangeRate = (getCashPrior() + totalBorrows - totalReserves) / totalSupply
```

- `getCashPrior()` simply returns the underlying token's **raw ERC-20 balance** of the hToken contract:

```solidity
function getCashPrior() virtual internal view returns (uint) {
    return EIP20Interface(underlying).balanceOf(address(this));
}
```

This is the crux of the vulnerability: `cash` is *not* an internally accounted value updated only through `mint`/`redeem`/`borrow`/`repay` — it is whatever the underlying token's `balanceOf()` reports for the contract at that moment. Anyone can inflate it with a plain `transfer()`.

---

## 3. Why This Vulnerability Happened (Root Cause)

Two conditions combined to make the exploit possible:

1. **Untrusted balance-based accounting (the donation vector).**
   `getCashPrior()` trusts `underlying.balanceOf(address(this))`. A direct token transfer to the contract — which does **not** go through `mint()` and therefore does not mint any corresponding hTokens — still counts as "cash" in the exchange-rate formula. This lets anyone unilaterally inflate the numerator of `exchangeRate` without increasing `totalSupply` (the denominator).

2. **An empty/low-liquidity market amplifies the effect.**
   Hundred Finance had set up **two hWBTC contracts** on Optimism — the actively used one, and a second that was effectively unused/near-empty (near-zero `totalSupply`). A market with a tiny `totalSupply` means even a modest donation produces an *enormous* proportional jump in `exchangeRate`, since the same numerator increase is divided by an almost-zero denominator. The attacker was the market's dominant (effectively only) hToken holder, so they alone captured the inflated valuation.

3. **A rounding/precision bug compounded the damage.**
   The function used to redeem underlying tokens (`redeemUnderlying`, inherited from the same Compound V2 codebase) contained a precision-loss issue: converting a requested underlying-token amount back into the hToken amount to burn rounded down instead of up in some cases, letting the attacker redeem more value than they should have been debited for.

This flaw is **structural to the Compound V2 codebase design**, not specific to a Hundred Finance customization — Hundred Finance itself publicly warned other Compound V2 forks about it after the incident, and the same donation-based exchange-rate manipulation pattern was later observed hitting other forks (e.g., Midas, Onyx, Sonne Finance, and others through 2023).

---

## 4. Attack Flow (Step by Step)

1. **Funding / obfuscation.** The attacker withdrew ETH from Tornado Cash on April 11 and April 14, 2023, bridged funds to Optimism, and converted some to WBTC to fund the attack.
2. **Target selection.** The attacker identified that the hWBTC market(s) on Hundred Finance's Optimism deployment had little to no active lending/borrowing — i.e., near-zero `totalSupply` of hWBTC.
3. **Flash loan.** The attacker took a flash loan of 500 WBTC (from Aave V3).
4. **Reset the market.** The attacker redeemed any previously-acquired hWBTC, resetting hWBTC's `totalSupply` to 0 to start from a clean, easily manipulable state.
5. **Mint a small hWBTC position.** Deposited 4 WBTC via `mint()`, receiving 200 hWBTC.
6. **Burn almost the entire position.** Called `redeem()` on 199.99999998 hWBTC, leaving `totalSupply` at just **2 wei of hWBTC**, while the attacker retained the rights associated with that WBTC.
7. **Donate the flash-loaned WBTC.** Transferred ~500.3 WBTC **directly** to the hWBTC contract via a plain ERC-20 `transfer()` (not `mint()`). Because `getCashPrior()` reads raw balance, `cash` jumped to ~500.3 WBTC while `totalSupply` remained at 2 wei — inflating `exchangeRate` by roughly two orders of magnitude.
8. **Borrow against inflated collateral.** Using the now-massively-overvalued hWBTC as collateral, the attacker borrowed heavily from other markets — e.g., 1021.91 ETH from the hETH market.
9. **Redeem residual hWBTC at the inflated rate,** exploiting the `redeemUnderlying` rounding error to extract slightly more WBTC than the manipulated exchange rate alone would allow (attacker redeemed ~500.3 WBTC while the protocol only deducted ~1 hBTC instead of the ~2 hBTC the math called for — a ~50% precision loss in the protocol's favor of the attacker).
10. **Repeat across markets.** The attacker liquidated the remaining dust hWBTC (resetting `totalSupply` to 0 again) and repeated the same donation-and-borrow pattern to drain other Hundred Finance markets — including both a legacy Optimism deployment (with older user funds) and the current one — via two coordinated "master" attack contracts.
11. **Repay flash loan and exit.** The attacker repaid the Aave flash loan and bridged the stolen assets (500.3 WBTC, 1021.91 ETH, and stablecoins) to Ethereum, where a large portion was swapped for USDT/USDC or deposited into Curve, contributing to a ~50% crash in the HND governance token price.

**Total loss:** ~$7.4M, comprising roughly 0.058 WBTC, 20,854 SNX, 1,265,978 USDC, 842,788 DAI, 1,113,430 USDT, 865,142 sUSD, 457,286 FRAX, and 1,030 ETH across the affected markets.

---

## 5. Smart Contract & Vulnerable Function References

Hundred Finance did not maintain a single canonical GitHub repository for its deployed hToken market contracts — like most Compound V2 forks, each market was deployed and verified individually on-chain (e.g. on Optimistic Etherscan / Arbiscan), inheriting logic from the open-source Compound V2 codebase.

| Item | Reference |
|---|---|
| Vulnerable base logic (`CToken.sol`) | https://github.com/compound-finance/compound-protocol/blob/master/contracts/CToken.sol |
| Faulty function #1 — trusts raw balance | `getCashPrior()` in `CToken.sol` |
| Faulty function #2 — uses `getCashPrior()` in exchange-rate math | `exchangeRateStoredInternal()` in `CToken.sol` |
| Faulty function #3 — rounding/precision bug | `redeemUnderlying()` in `CToken.sol` |
| Hundred Finance developer docs (hToken deployment process) | https://github.com/hundred-finance/hundred-dev |
| Hundred Finance org repos (interface, migration tooling, etc.) | https://github.com/hundred-finance |
| Attacker address (Optimism / Ethereum) | `0x155DA45D374A286d383839b1eF27567A15E67528` |

> Note: A separate, earlier Hundred Finance incident (March 2022, Gnosis Chain reentrancy attack, ~$6.2M loss) has its own PoC in Immunefi's template repo (`HundredFinanceHack.sol`). That is a **different vulnerability class** (reentrancy via ERC-677 `onTokenTransfer` callback), not the April 2023 donation/exchange-rate attack described here — the two are easy to conflate since they hit the same protocol.

---

## 6. Impact

- **Direct financial loss:** ~$7.4 million drained across multiple asset markets (WBTC, ETH, SNX, USDC, DAI, USDT, sUSD, FRAX).
- **Governance token crash:** HND token price fell approximately 46–50% following the attack, as the attacker's swaps and general market panic hit liquidity.
- **Repeat-victim reputational damage:** This was Hundred Finance's **third** major security incident (after a February 2022 Meter-related loss of $3.3M and a March 2022 Gnosis Chain reentrancy loss of $6.2M alongside Agave DAO), pushing its cumulative disclosed losses to roughly $16.9M+ at the time.
- **Ecosystem-wide risk exposure:** Because the flaw was in inherited Compound V2 logic rather than Hundred-specific code, Hundred Finance publicly urged all Compound V2 forks to review their deployments, and the "empty market donation" pattern was subsequently seen affecting other forks later in 2023.
- **User trust and recovery:** Hundred Finance attempted on-chain negotiation with the attacker (offering a bounty and a no-questions-asked return of funds) and posted a $500,000 reward for information leading to identification/arrest of the attacker; full recovery of user funds was not guaranteed and the protocol's usage and TVL fell sharply afterward.

---

## 7. The Fix

Following the incident, the general mitigations adopted by Hundred Finance and recommended industry-wide for Compound V2-style forks were:

1. **Seed every new market with a minimum non-zero liquidity/`totalSupply` at deployment**, so `exchangeRate` cannot be manipulated by donations when `totalSupply` is nearly zero. This closes off the "empty market" precondition that let a modest donation produce a massive proportional swing in exchange rate.
2. **Avoid relying purely on raw `balanceOf()` for `cash`,** or otherwise guard against unsolicited direct transfers being treated as legitimate deposits — e.g., by reconciling expected vs. actual balances, or requiring deposits to always route through `mint()`-tracked accounting.
3. **Fix the rounding direction in redemption math** so that the protocol never rounds in the user's favor when converting between hToken and underlying amounts (round against the user, not against the protocol) — closing the precision-loss gap exploited in `redeemUnderlying()`.
4. **Freeze/pause and permission the deployment of new markets carefully** — disused or "empty" markets (like the second unused hWBTC deployment on Optimism) should not remain live and borrowable if they aren't intended for use; unused markets are a systemic risk surface.
5. **Circulate the vulnerability disclosure to other forks.** Hundred Finance published a post-mortem and reached out to other Compound V2-based protocols warning them of the general (non-Hundred-specific) flaw, since the root cause lived in widely-forked base code.
6. **Third-party protocols that later hardened against this class of bug** typically added explicit checks that `totalSupply == 0` markets cannot be minted into asymmetrically, or added a virtual/offset balance (similar to Uniswap V2's minimum liquidity lock) to prevent first-depositor/empty-market exchange-rate attacks entirely.

No on-chain funds were recovered from the attacker at the time of the public post-mortem; the response was primarily architectural (market safeguards) and social (bounty + disclosure to other protocols) rather than a retroactive protocol patch to the drained markets themselves.

---

## 8. Lessons Learned

1. **Never let raw ERC-20 `balanceOf()` be the sole source of truth for internal accounting.** If a value used in a financial calculation (like an exchange rate) can be moved by *anyone* via a plain transfer, it can be manipulated — this is the classic "donation attack" pattern also seen in ERC-4626 vault "inflation attacks."
2. **Empty or low-liquidity markets are uniquely dangerous.** Any pricing/accounting formula with `totalSupply` (or an equivalent small denominator) in the denominator is vulnerable to extreme manipulation when that denominator is close to zero. New markets should be seeded with minimum liquidity before being made borrowable/usable as collateral.
3. **Precision/rounding direction matters — always round in the protocol's favor**, never the user's, especially in redemption and repayment paths.
4. **Fork inherited risk along with inherited code.** Because Hundred Finance forked Compound V2 largely as-is, it inherited a flaw present in the base code; forking a "battle-tested, audited" protocol does not exempt a project from re-auditing for its own specific deployment context (e.g., which markets are seeded, which are left empty).
5. **Unused/duplicate contract deployments are attack surface, not dead weight.** The existence of a second, forgotten hWBTC market was a key enabler — infrastructure that is deployed but not actively monitored/used should be decommissioned or locked down.
6. **Audits are a point-in-time signal, not a guarantee.** Hundred Finance had been audited (WhiteHatDAO, Feb 2022) prior to this incident; the vulnerable pattern was not caught, underscoring that audits do not eliminate systemic classes of bugs — especially ones only exposed by unusual deployment/liquidity states.
7. **Repeat incidents compound reputational and financial damage.** This was Hundred Finance's third major hack; consistent post-incident hardening (not just patching the specific exploited path) is essential to avoid recurring losses.
8. **Responsible, prompt cross-protocol disclosure helps the wider ecosystem.** Once the root cause was understood as a general flaw in widely-forked base code, proactively warning other forks likely prevented additional exploits industry-wide.

---

## 9. References

- Halborn — [Explained: The Hundred Finance Hack (April 2023)](https://www.halborn.com/blog/post/explained-the-hundred-finance-hack-april-2023)
- REKT — [Hundred Finance — REKT 2](https://rekt.news/hundred-rekt2)
- Decrypt — [Hacker Exploits Hundred Finance Protocol In $7.4 Million Heist](https://decrypt.co/136918/hacker-exploits-hundred-finance-protocol-in-7-4-million-heist)
- BlockApex — [Hundred Finance Hack Analysis](https://blockapex.io/hundred-finance-hack-analysis/)
- BlockSec — [#6: Hundred Finance Incident: Catalyzing the Wave of Precision-Related Exploits in Vulnerable Forked Protocols](https://blocksec.com/blog/6-hundred-finance-incident-catalyzing-the-wave-of-precision-related-exploits-in-vulnerable-forked-protocols)
- Numen Cyber — [Hundred Finance Exploited for $7 Million in Latest Attack](https://www.numencyber.com/hundred-finance-exploit-7-million/)
- CryptoTimes — [Hundred Finance Hacked for Over $7 Million](https://www.cryptotimes.io/2023/04/17/hundred-finance-hacked-for-over-7-million/)
- BeInCrypto — [DeFi Protocol Hundred Finance Hacked For $7M](https://beincrypto.com/hundred-finance-hacked-for-7m/)
- Quadriga Initiative Wiki — [Hundred Finance WBTC Optimism Exploit](https://quadrigainitiative.com/cryptocurrencyhackscamfraudwiki/index.php?title=Hundred_Finance_WBTC_Optimism_Exploit)
- Hundred Finance — [Official Post-Mortem (Medium, April 22, 2023)](https://blog.hundred.finance/15-04-23-hundred-finance-hack-post-mortem-d895b618cf33)
- Compound Protocol — [`CToken.sol` source](https://github.com/compound-finance/compound-protocol/blob/master/contracts/CToken.sol)
- Hundred Finance — [Developer docs / hToken deployment repo](https://github.com/hundred-finance/hundred-dev)

