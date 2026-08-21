# KyberSwap Elastic Exploit — November 23, 2023

**Incident type:** Rounding error in concentrated liquidity swap math, leading to double-counted pool liquidity (Solidity)
**Protocol:** KyberSwap Elastic, a concentrated liquidity AMM built on top of Uniswap V3's design, deployed across six chains
**Vulnerable contract:** `SwapMath.sol`, function `computeSwapStep`, part of the core `Pool.sol` swap flow
**Amount lost:** approximately $47–54.7 million across multiple chains, in a single coordinated attack

## Overview

KyberSwap Elastic let liquidity providers concentrate their funds within specific price ranges, tracked internally using a system of discrete price points called ticks. This makes trading more capital efficient than a traditional pooled AMM, but it comes at the cost of significantly more delicate math: every swap has to correctly track which ticks are being crossed and how much liquidity is active at each one.

On November 23, 2023, an attacker found a way to break one specific mathematical guarantee inside that system: a rounding error that, under an extremely precise and narrow set of conditions, allowed the calculated post-swap price to land on the wrong side of a tick boundary. That single broken guarantee cascaded into the pool's liquidity being counted twice, which the attacker then exploited to drain multiple pools across six blockchain networks within hours.

This is one of the more mathematically intricate incidents in this collection. Unlike a missing access-control check or a stale memory copy, this bug lived inside carefully constructed fixed-point arithmetic, and even KyberSwap's own pre-deployment audits did not catch it. It's an excellent example of how correctness in DeFi math is genuinely hard to verify by inspection alone, and why "the code looks right" is not the same as "the code is provably right."

## Why this incident is worth studying

- It shows that vulnerabilities are not always about forgetting a check or a `require` statement. Sometimes the bug is buried three function calls deep inside arithmetic that, on its face, looks completely deliberate and carefully engineered.
- It demonstrates how a single violated invariant, documented in the code's own comments as a guarantee that should always hold, can silently break a system's core assumptions elsewhere.
- It is a genuinely difficult bug to spot through manual review, which is itself an instructive data point about the limits of audits against adversarial, exhaustive search by an attacker.

## Folder guide

| File | What it covers |
|---|---|
| `summary.md` | Quick reference: when, where, why, the fix |
| `exploit.md` | Step-by-step mechanics of the rounding error and how it was weaponized |
| `fix.md` | What KyberSwap changed, and the broader lesson on invariant-breaking bugs |
| `contracts/SwapMath.sol` | The real, official vulnerable library, pulled directly from KyberSwap's GitHub, with the exact function and surrounding context annotated |
| `writeups/sources-index.md` | Every source referenced, including KyberSwap's own official post-mortem |

## The vulnerable guarantee, at a glance

`SwapMath.sol`'s own documentation states plainly: *"nextSqrtP should not exceed targetSqrtP."* Under a very specific combination of swap amount and pool state, that guarantee did not hold. See `exploit.md` for the full trace of how that single broken promise led to millions of dollars in double-counted liquidity being drained.
