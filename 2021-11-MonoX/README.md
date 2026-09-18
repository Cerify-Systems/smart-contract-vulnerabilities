# MonoX Finance — Price Manipulation / Single-Sided AMM Accounting Exploit

## Overview

| | |
|---|---|
| **Protocol** | MonoX Finance (Monoswap AMM) |
| **Date of Incident** | November 30, 2021 |
| **Chains Affected** | Ethereum, Polygon |
| **Vulnerability Class** | Price manipulation via flawed AMM accounting logic (missing `tokenIn != tokenOut` check) |
| **Estimated Loss** | ~$31–34 million |
| **Audits Prior to Launch** | 3 audits (incl. Halborn, PeckShield) + testnet run + bug bounty |

MonoX is a DeFi protocol that introduced a **single-token liquidity pool** design, diverging from the traditional token-pair AMM model (e.g., Uniswap). Instead of pairing two real tokens in a pool, MonoX virtually paired every deposited token against an internal stablecoin, **vCASH**, letting liquidity providers deposit a single asset rather than a matched pair. The AMM (Monoswap) launched in October 2021 and was exploited about a month later.

---

## Background: Why the Design Made This Possible

In a standard two-sided AMM (x*y=k), price is derived directly from the ratio of two real token reserves, and there's no ambiguity about "tokenIn" vs "tokenOut" pricing because the pool itself enforces the invariant atomically.

MonoX's single-token model instead tracked **an independent price for each token** in the pool relative to vCASH, and every swap needed to:
1. Update the price of the token being sold (`tokenIn`)
2. Update the price of the token being bought (`tokenOut`)

These two updates were computed and applied **independently**, one after another, rather than as a single atomic invariant check. This separation is the structural root cause that made the exploit possible.

---

## The Vulnerability

The swap functions in `Monoswap.sol` — primarily:

- `swapExactTokenForToken`
- `_swapTokenForExactToken`

— never verified that `tokenIn` and `tokenOut` were **different tokens**. Internally, swaps relied on a token pricing routine (referred to across incident write-ups as `_updateTokenInfo` / the price-update logic invoked by `swapIn` / `swapOut` and `getAmountIn` / `getAmountOut`).

Normally:
- Selling a token → decreases that token's pool price.
- Buying a token → increases that token's pool price.

When `tokenIn == tokenOut` (i.e., a user "swaps" a token for itself), the contract still ran both updates — first decrementing the price for the sell side, then incrementing the price for the buy side, **on the same token**. Because the buy-side (`tokenOut`) update was applied **last**, it overwrote the sell-side (`tokenIn`) update instead of the two operations netting out to a no-op. Each same-token swap therefore produced a **net positive price increase** for that token, with no real economic trade taking place.

> *"The exploit was caused by a smart contract bug that allows the sold and bought token to be the same... Any price updates from swap from tokenIn and tokenOut were independently verified by the contract. With tokenOut being verified last, this caused a massive price appreciation of MONO."* — MonoX Team, post-mortem

A secondary bug compounded the attack: the liquidity-removal path (`removeLiquidity` → `_removeLiquidity`) did not verify that `msg.sender` was the actual owner of the liquidity being withdrawn, allowing the attacker to pull liquidity belonging to other users to help fund/seed the exploit.

---

## Attack Flow

1. **Seed capital** — The attacker swapped a small amount of WETH (~0.1 ETH) for MONO through Monoswap to obtain an initial MONO balance.
2. **Exploit the liquidity-removal flaw** — Using the unauthenticated `_removeLiquidity` path, the attacker withdrew liquidity that belonged to other addresses, pulling additional MONO/vCASH into their control.
3. **Self-swap loop** — The attacker repeatedly called `swapExactTokenForToken`, swapping **MONO for MONO** (i.e., `tokenIn == tokenOut == MONO`). Each call triggered the flawed price-update sequence, inflating MONO's internal pool price. This was repeated **55 times** in a tight, scripted sequence.
4. **Drain the pool** — With MONO's pool price now artificially astronomical, the attacker called `swapTokenForExactToken`, using a small quantity of MONO (now "worth" far more than reality) to buy out essentially all other real assets in MonoX's pools — WETH, WBTC, WMATIC/MATIC, USDC, USDT, LINK, GHST, DUCK, MIM, IMX, and others.
5. **Repeat on Polygon** — The identical attack contracts and calldata were deployed and replayed on the Polygon deployment of Monoswap (same codebase), doubling the damage.
6. **Fund movement** — Stolen assets were consolidated to attacker-controlled addresses and partially routed through mixers/tumblers.

**Attacker address:** `0xEcbE385F78041895c311070F344b55BfAa953258`
**Fund consolidation address:** `0x8f6a86f3ab015f4d03ddb13abb02710e6d7ab31b`

**Transactions:**
- Ethereum: [`0x9f14d093a2349de08f02fc0fb018dadb449351d0cdb7d0738ff69cc6fef5f299`](https://etherscan.io/tx/0x9f14d093a2349de08f02fc0fb018dadb449351d0cdb7d0738ff69cc6fef5f299)
- Polygon: [`0x5a03b9c03eedcb9ec6e70c6841eaa4976a732d050a6218969e39483bb3004d5d`](https://polygonscan.com/tx/0x5a03b9c03eedcb9ec6e70c6841eaa4976a732d050a6218969e39483bb3004d5d)

---

## Why the Vulnerability Happened (Root Cause Summary)

1. **Novel accounting model, insufficient invariant enforcement** — MonoX's single-token/virtual-pair design required separate, sequential price updates per token instead of a single atomic pool invariant (as in x*y=k). This created a window where order-of-operations mattered.
2. **Missing input validation** — No check that `tokenIn != tokenOut` in the swap entry points, an assumption implicitly relied upon elsewhere in the pricing math but never enforced.
3. **Non-idempotent update logic** — The "sell" and "buy" price-update steps were not designed to be safe when applied to the same token in the same transaction; the second write silently clobbered the first instead of netting to zero.
4. **Audit blind spot** — Three separate audits, a live testnet period, and a bug bounty program failed to catch this because the bug wasn't a classic vulnerability pattern (reentrancy, overflow, access control in the traditional sense) — it was a domain-specific logic flaw unique to MonoX's custom AMM accounting design, which is harder for generic audit checklists to surface.
5. **Secondary access-control gap** — The liquidity-removal function also lacked an ownership check on the caller, which is a more conventional (but still critical) access-control bug that helped enable/fund the attack.

---

## Smart Contract & Function References

- **Deployed contract (Etherscan, verified source):**
  `0x3860...` — Monoswap core contract (see Etherscan for full verified source):
  https://etherscan.io/address/0x38608B6dD2dc2fDF3328BB37AaA0982856621456#code

- **GitHub mirror of the verified contract source:**
  https://github.com/bao1018/Monoswap/blob/master/Monoswap.sol

- **Faulty functions:**
  - `swapExactTokenForToken` — entry point exploited directly via repeated MONO→MONO self-swaps.
  - `_swapTokenForExactToken` — shared the same missing `tokenIn != tokenOut` validation; used to drain other pool assets once MONO's price was inflated.
  - Internal price-update / pricing helpers (`swapIn`, `swapOut`, `getAmountIn`, `getAmountOut`, and the internal token-info update routine referred to as `_updateTokenInfo` in incident analyses) — where the overwrite occurred.
  - `_removeLiquidity` / `removeLiquidity` — missing ownership check on liquidity withdrawal (secondary vulnerability).

---

## Financial Impact

Total losses were estimated at **~$31–34 million** across both chains, including approximately:

| Asset | Approx. Amount |
|---|---|
| WETH | ~3,900 WETH (~$18.2M) |
| WMATIC / MATIC | ~5.7M MATIC (~$10.5–19.4M across Polygon) |
| WBTC | ~36.1 WBTC (~$2M) |
| USDC | ~$8.2M |
| USDT | ~$9.1M |
| LINK | ~1,200 LINK (~$31K) |
| GHST (Aavegotchi) | ~3,100 GHST |
| DUCK | ~5.1M DUCK |
| MIM | ~4,100 MIM |
| IMX (Immutable X) | ~274 IMX |
| MONO | ~143,400 MONO |

### Broader Impact
- MonoX's protocol was **paused immediately** after detection.
- The team attempted on-chain communication with the attacker, offering a bounty/return arrangement — with partial success in negotiations reported afterward.
- The incident occurred **just days after MonoX celebrated surpassing $30M in Total Value Locked (TVL)**, amplifying reputational damage.
- It happened in the same week as several other major DeFi hacks (e.g., BadgerDAO two days later), fueling broader industry scrutiny of 2021 as a record year for DeFi exploits (Elliptic estimated ~$12B in cumulative DeFi theft/fraud by that point in 2021).
- Raised industry-wide questions about the limits of smart contract audits for **protocol-specific economic/accounting logic**, as opposed to well-known vulnerability classes.

---

## The Fix

Following the exploit, MonoX took the following remediation steps:

1. **Immediate contract pause** — Trading and liquidity operations on Monoswap were halted on both Ethereum and Polygon to stop further draining.
2. **Root-cause patch** — The core fix addressed the missing validation by ensuring swap functions explicitly reject or safely handle the case where `tokenIn == tokenOut`, and/or by restructuring the price-update logic so that sell-side and buy-side updates cannot be applied to the same token asset in a way that overwrites rather than nets out.
3. **Access-control fix** — The liquidity-removal path was corrected to verify that the caller is the legitimate owner of the liquidity position before allowing withdrawal.
4. **Expanded security posture going forward:**
   - Additional, more rigorous testing before relaunch.
   - Partnership with **Immunefi** for an ongoing, scaling bug bounty program tied to TVL growth.
   - Plans to scale TVL more gradually and seek better insurance coverage for pooled funds.
   - Commitment to relaunch only after further security review by external partners.
5. **User compensation plan** — MonoX proposed repaying affected users over time, with a contingency **debt token (dMONO)** to be issued for outstanding compensation if funds were not recovered by a stated deadline (Jan 3, 2022), redeemable via a dedicated vault.

---

## Lessons Learned

1. **Validate token identity assumptions explicitly.** Any function accepting two token parameters (`tokenIn`/`tokenOut`) that are assumed to differ must enforce that assumption on-chain — never rely on implicit caller intent.
2. **Design price/state updates to be idempotent and order-independent.** Sequential, mutually dependent state updates (sell price, then buy price) are fragile; prefer atomic invariant checks (like constant-product `x*y=k`) that are mathematically self-consistent regardless of call order or edge-case inputs.
3. **Novel AMM designs need novel threat modeling.** Departing from well-audited, battle-tested AMM patterns (e.g., Uniswap V2/V3) introduces new attack surfaces that generic audit checklists and standard vulnerability scanners are not tuned to catch. Custom economic logic warrants dedicated economic/game-theoretic security review, not just code-level audits.
4. **Multiple audits are necessary but not sufficient.** Three audits plus a bug bounty still missed this bug — audits reduce but do not eliminate risk, especially for protocol-specific logic flaws rather than well-known vulnerability classes.
5. **Access control must be enforced at every fund-moving entry point.** The secondary `_removeLiquidity` bug reinforces that ownership/authorization checks must be present on every function that moves or withdraws user funds, not just the "main" attack surface.
6. **Same-block/same-transaction repeatable actions deserve extra scrutiny.** The ability to call the same swap function dozens of times in one attack sequence to compound a small logic error into a massive price distortion highlights the need for rate-limiting, circuit breakers, or invariant checks resistant to repeated exploitation within a short window.
7. **Post-incident transparency matters.** MonoX's detailed public post-mortem and compensation plan, while not undoing the loss, are considered a relatively good example of incident response communication in the DeFi hack landscape.

---

## References

- MonoX Team, ["Exploit: Post Mortem"](https://medium.com/monoswap/exploit-post-mortem-33921a779b43) — Medium
- SlowMist, ["Detailed Analysis of the $31 Million MonoX Protocol Hack"](https://slowmist.medium.com/detailed-analysis-of-the-31-million-monox-protocol-hack-574d8c44a9c8) — Medium
- Optimaginating, ["A Full Analysis of the MonoX Attack"](https://optimaginating.medium.com/a-full-analysis-of-the-monox-attack-ed41e4a6b254) — Medium
- ImmuneBytes, ["MonoX Hack Incident — Nov 30, 2021 — Detailed Analysis"](https://immunebytes.com/blog/monox-hack-incident-nov-30-2021-detailed-analysis/)
- Vidma Security, ["The MonoX Meltdown: Unraveling the $31 Million Smart Contract Hack"](https://www.vidma.io/blog/the-monox-meltdown-unraveling-the-31-million-smart-contract-hack)
- Coinspeaker, ["DeFi Hack: $31 Million Stolen from MonoX Platform on Polygon and Ethereum"](https://www.coinspeaker.com/defi-hack-31m-monox-polygon-eth/)
- Sophos, ["Cryptocurrency Startup Fails to Subtract Before Adding, Loses $31M"](https://www.sophos.com/en-us/blog/cryptocurrency-startup-fails-to-subtract-before-adding-loses-31m)
- Quadriga Initiative, ["Nov 2021 - MonoX Software Bug - $31m (Global)"](https://www.quadrigainitiative.com/hackfraudscam/monoxsoftwarebug.php)
- GitHub mirror of the exploited contract: [bao1018/Monoswap](https://github.com/bao1018/Monoswap/blob/master/Monoswap.sol)
- Verified deployed contract: [Etherscan](https://etherscan.io/address/0x38608B6dD2dc2fDF3328BB37AaA0982856621456#code)