# Onyx Protocol — Lending Market Manipulation Incident

## Overview

| | |
|---|---|
| **Protocol** | Onyx Protocol (Compound V2 fork, supports ERC-20 + NFT collateral) |
| **Vulnerability Class** | Empty Market / Exchange-Rate Manipulation (Donation Attack) |
| **Incident 1 Date** | October 26 – November 1, 2023 |
| **Incident 1 Loss** | ~$2.1M |
| **Incident 2 Date** | September 27, 2024 |
| **Incident 2 Loss** | ~$3.8M |
| **Root Cause** | Unseeded (`totalSupply == 0`) market allows exchange-rate manipulation via direct token donation |
| **Contract** | `OToken.sol` |
| **Faulty Function** | `exchangeRateStoredInternal()` (exploited via `mintFresh()` / `redeemFresh()`) |

---

## Description

Onyx Protocol is a decentralized lending platform on Ethereum, forked from **Compound V2**, that lets users supply collateral (ERC-20 tokens, and uniquely, NFTs) and borrow against it. Like Compound, Onyx represents each supplied asset as an interest-bearing `oToken`, whose value relative to the underlying asset is tracked by an **exchange rate**.

Onyx was exploited **twice** — in October/November 2023 and again in September 2024 — using fundamentally the **same class of vulnerability**: manipulating the exchange rate of a newly deployed, empty (zero-liquidity) lending market to fraudulently inflate the attacker's apparent collateral value, borrow disproportionately from other liquid markets, and drain protocol funds.

---

## The Vulnerability — Why It Happened

The exchange rate for an `oToken` market is computed as:

```
exchangeRate = (totalCash + totalBorrows − totalReserves) / totalSupply
```

When a **brand-new market is deployed**, `totalSupply == 0`. The contract explicitly falls back to a fixed `initialExchangeRateMantissa` in this state:

```solidity
function exchangeRateStoredInternal() internal view returns (MathError, uint) {
    uint _totalSupply = totalSupply;
    if (_totalSupply == 0) {
        // exchangeRate = initialExchangeRate
        return (MathError.NO_ERROR, initialExchangeRateMantissa);
    } else {
        uint totalCash = getCashPrior();
        ...
        (mathErr, exchangeRate) = getExp(cashPlusBorrowsMinusReserves, _totalSupply);
        ...
        return (MathError.NO_ERROR, exchangeRate.mantissa);
    }
}
```

The critical flaw: **`totalCash` (`getCashPrior()`) simply reads the contract's raw token balance** — it does **not** distinguish between funds that entered through a legitimate `mint()` call and funds sent via a **direct ERC-20 transfer ("donation")** straight to the contract address. Meanwhile `totalSupply` only increases inside `mintFresh()`.

This mismatch is exploitable the moment a market has zero (or near-zero) supply:

1. The market has no minimum-liquidity/"dead shares" safeguard, so `totalSupply` can be pushed from `0` to a tiny nonzero value (e.g. `2`) at the attacker's discretion.
2. Because `totalCash` counts *any* tokens sitting in the contract, an attacker can inflate it arbitrarily via a plain transfer before that first mint is finalized.
3. The exchange rate formula then divides a huge `totalCash` by a tiny `totalSupply`, producing an extreme, attacker-controlled exchange rate.
4. This manipulated exchange rate is read by the **Comptroller** (via `getAccountSnapshot`) to value the attacker's collateral for borrowing power across *other, liquid* Onyx markets.
5. Truncating integer division in `redeemFresh()` (`mulScalarTruncate`, `divScalarByExpTruncate`) rounds in the attacker's favor at these extreme values, letting them redeem back their original collateral while leaving the borrowed markets short — the bad debt that drains the protocol.

This is a well-documented Compound V2 fork weakness (an "empty pool attack") previously seen in Hundred Finance (~$7M, April 2023) and Midas Capital.

---

## Attack Flow

### Incident 1 — oPEPE Market (Nov 1, 2023, ~$2.1M)

```
1. Governance Proposal (OIP-22) passes → new oPEPE market deployed with ZERO initial liquidity.
2. Attacker monitors the proposal; executes it themselves, then attacks ~1 minute later.
3. Attacker "donates" PEPE tokens directly to the oPEPE contract
   → inflates totalCash without incrementing totalSupply.
4. Attacker mints a tiny amount of oPEPE
   → totalSupply flips 0 → 2 (a near-zero value).
5. exchangeRateStoredInternal() now computes an enormous, manipulated exchange rate
   (totalCash ≈ 2,520,870,348,093,423,681,390,050,791,471 relative to totalSupply = 2).
6. Comptroller values attacker's oPEPE collateral using this bogus rate
   → attacker borrows large amounts from Onyx's OTHER, genuinely liquid markets (ETH, stablecoins, etc.).
7. Attacker redeems their oPEPE, exploiting rounding/truncation errors to reclaim
   essentially all their original donated collateral.
8. Result: liquid markets are left holding bad debt; attacker walks away with borrowed assets.
9. Funds laundered: 1,140 ETH routed through Tornado Cash; remainder to associated addresses.
```

### Incident 2 — Second Exploit (Sept 27, 2024, ~$3.8M)

```
1. Governance again creates a new, unfunded market (VUSD/oETH-style) — the "mint & burn
   dead shares" mitigation recommended after Incident 1 was still not implemented.
2. Attacker uses a Balancer flash loan to fund the attack.
3. Attacker mints and redeems the new oToken in tiny quantities to destabilize
   the market's exchange rate — same core mechanism as Incident 1.
4. In parallel, attacker exploits a SEPARATE bug in the NFTLiquidation contract,
   which failed to properly validate untrusted user input, allowing manipulation
   of the self-liquidation reward calculation.
5. Combined exploitation drains VUSD, XCN, WBTC, DAI, and USDT across multiple markets.
6. Result: ~$3.8M stolen; Onyx shuts down its Ethereum lending market via
   emergency governance proposal OIP-46 the same day.
```

---

## Smart Contract Reference

**Repository:** [Onyx-Protocol/onyx-protocol](https://github.com/Onyx-Protocol/onyx-protocol)
**Contract:** `contracts/OToken.sol`
**License / base:** Fork of [compound-finance/compound-protocol](https://github.com/compound-finance/compound-protocol) — `CToken.sol`

### Faulty function

```solidity
/**
 * @notice Calculates the exchange rate from the underlying to the OToken
 * @dev This function does not accrue interest before calculating the exchange rate
 * @return (error code, calculated exchange rate scaled by 1e18)
 */
function exchangeRateStoredInternal() internal view returns (MathError, uint) {
    uint _totalSupply = totalSupply;
    if (_totalSupply == 0) {
        /*
         * If there are no tokens minted:
         *  exchangeRate = initialExchangeRate
         */
        return (MathError.NO_ERROR, initialExchangeRateMantissa);
    } else {
        /*
         * Otherwise:
         *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
         */
        uint totalCash = getCashPrior();
        uint cashPlusBorrowsMinusReserves;
        Exp memory exchangeRate;
        MathError mathErr;

        (mathErr, cashPlusBorrowsMinusReserves) = addThenSubUInt(totalCash, totalBorrows, totalReserves);
        if (mathErr != MathError.NO_ERROR) {
            return (mathErr, 0);
        }

        (mathErr, exchangeRate) = getExp(cashPlusBorrowsMinusReserves, _totalSupply);
        if (mathErr != MathError.NO_ERROR) {
            return (mathErr, 0);
        }

        return (MathError.NO_ERROR, exchangeRate.mantissa);
    }
}
```

### Supporting functions in the exploit chain

| Function | Role in the exploit |
|---|---|
| `getCashPrior()` | Returns raw token balance of the contract — does **not** distinguish donated funds from minted funds |
| `mintFresh(minter, mintAmount)` | Reads the manipulated exchange rate via `exchangeRateStoredInternal()` to calculate `mintTokens`; flips `totalSupply` from 0 to a tiny value |
| `redeemFresh(redeemer, redeemTokensIn, redeemAmountIn)` | Uses the same manipulated rate; truncating math (`mulScalarTruncate`, `divScalarByExpTruncate`) rounds in the attacker's favor |
| `getAccountSnapshot(account)` | Called by the Comptroller for collateral/borrow-power checks; propagates the manipulated exchange rate protocol-wide |
| `seizeInternal(...)` | Also relies on `exchangeRateStoredInternal()` for liquidation seizure accounting |

---

## Financial Loss & Impact

| Metric | Incident 1 (Nov 2023) | Incident 2 (Sept 2024) |
|---|---|---|
| Loss amount | ~$2.1M | ~$3.8M |
| Assets drained | ETH (via Tornado Cash) and other pooled assets | VUSD (4.1M), XCN (7.35M), WBTC (0.23), DAI ($5K), USDT ($50K) |
| TVL before → after | $2.9M → $392K (−87%) | Materially worsened an already-damaged protocol |
| Secondary damage | ~250 ETH additional loss from panic withdrawals / reputational damage | Full shutdown of Ethereum lending market |
| Governance response | Acknowledged CertiK's prior warning; no fix implemented | Emergency proposal OIP-46, passed unanimously, executed within days |
| Protocol outcome | Continued operating (unfixed) | Relaunched as a closed, permissioned product — "Onyx Core" |

**Broader impact:** Both incidents underscored systemic risk across the Compound V2 fork ecosystem — the same bug class had already hit Hundred Finance (~$7M) and later affected other forks (Midas Capital, Sonne Finance). Onyx's failure to remediate after the first hack directly enabled the second, larger loss.

---

## The Fix

### What was recommended (and initially ignored)

CertiK's original audit flagged this exact issue **before** Incident 1 and recommended:
> Add a mechanism to mint fresh, permanently-locked "dead shares" (a small nonzero `totalSupply`) at market deployment time, so `totalSupply` can never be manipulated from a true zero state.

The Onyx team **acknowledged the finding but chose not to act on it**, which directly enabled Incident 1, and — since the fix still wasn't applied — Incident 2 as well.

### The standard remediation pattern (post-incident best practice)

For Compound V2-style forks, the accepted fix is:

1. **Seed every new market on deployment**: mint a small number of oTokens to a burn address (e.g. `address(0)` or a locked contract) immediately after market creation, guaranteeing `totalSupply > 0` before any external party can interact with the market.
2. **Initially set the collateral factor to zero** for a newly created market, only raising it after sufficient organic liquidity has been supplied — preventing the market from being usable as borrowing collateral while still fragile.
3. **Track internal accounting separately from raw balance** — i.e., don't let `getCashPrior()` (raw `balanceOf(address(this))`) be the sole source of truth for `totalCash`; reconcile it against tracked deposits so direct "donation" transfers can't silently inflate exchange-rate inputs.
4. **Governance process hardening**: require higher quorum/participation and a security review checklist before any new-market proposal (like OIP-22) can execute, since both incidents involved low-participation proposals executed and then immediately attacked by the same or a related address.

### What Onyx actually did

Following Incident 2, Onyx did **not** patch and continue the same lending markets. Instead, governance passed **OIP-46 ("Relaunch Onyx Core")**, which:
- Shut down the vulnerable Ethereum-based open lending market entirely.
- Reimbursed affected lenders.
- Relaunched as **Onyx Core**, a closed-ended, permissioned lending protocol supporting wrapped NFTs, RWAs, and crypto assets — architecturally avoiding permissionless creation of unseeded markets.

---

## Lessons Learnt

1. **Never deploy a lending market with zero initial liquidity.** An empty market is a manipulable market — this is now a well-known anti-pattern for any Compound V2-derived protocol.
2. **Known vulnerabilities in forked code are not optional to fix.** Onyx inherited Compound V2's code (and its risks) but did not inherit the operational discipline to patch a flaw its own auditor had already identified.
3. **Donation attacks are a fundamental risk wherever `balanceOf(this)` is trusted as accounting state.** Raw token balance should never be conflated with internally tracked deposits.
4. **Low-participation governance is an attack surface.** Proposals that create new markets or economic parameters should require meaningful quorum and a mandatory security checklist, especially since attackers in both incidents were able to anticipate and immediately act on newly passed proposals.
5. **A single unresolved audit finding can cost millions twice.** Post-incident remediation must be enforced, not merely acknowledged — "we know about it" is not a fix.
6. **Systemic fork risk requires ecosystem-wide vigilance.** Because many DeFi protocols share the same underlying Compound V2 codebase, a vulnerability disclosed in one fork (e.g., Hundred Finance in April 2023) should trigger an immediate audit and patch across all sibling forks — not be treated as an isolated incident.

---

## References

- [CertiK — Post Mortem: Onyx Protocol](https://www.certik.com/blog/post-mortem-onyx-protocol)
- [DL News — Hacker drains $2.1m through memecoin lending market on Onyx Protocol](https://www.dlnews.com/articles/defi/hacker-drains-funds-through-pepe-market-on-onyx-protocol/)
- [Merkle Science — Onyx Protocol Hack: Flow of Funds Analysis](https://www.merklescience.com/blog/onyx-protocol-hack-flow-of-funds-analysis)
- [Hacken — Onyx Protocol Hack Explained: A Deeper Dive Into $2.1M Exploit](https://hacken.io/discover/onyx-protocol-hack/)
- [Halborn — Explained: The Onyx Protocol Hack (September 2024)](https://www.halborn.com/blog/post/explained-the-onyx-protocol-hack-september-2024)
- [MetaTrust Labs — How Onyx's Governance and Vulnerabilities Became Hackers' Golden Shovels](https://medium.com/@MetatrustL/metatrust-how-onyxs-governance-and-vulnerabilities-became-hackers-golden-shovels-2e16420940ce)
- [FinanceFeeds — DeFi protocol Onyx to relaunch after $3.8 million](https://financefeeds.com/defi-protocol-onyx-to-relaunch-after-3-8-million/)
- [CTOL Digital Solutions — DeFi Disaster: Onyx Protocol Loses $3.8 Million in Second Hack](https://www.ctol.digital/news/defi-disaster-onyx-protocol-loses-3-8-million-second-hack-known-vulnerability/)
- [Onyx-Protocol/onyx-protocol — GitHub Repository](https://github.com/Onyx-Protocol/onyx-protocol)
- [compound-finance/compound-protocol — CToken.sol (upstream reference implementation)](https://github.com/compound-finance/compound-protocol/blob/master/contracts/CToken.sol)

