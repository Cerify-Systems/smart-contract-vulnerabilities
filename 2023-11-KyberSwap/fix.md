# fix.md — What Actually Fixed This

## 1. The code-level fix
The core lesson is narrower and more mathematical than most incidents in this collection: any function that documents an invariant, a guarantee about its own output, such as `SwapMath.sol`'s stated promise that `nextSqrtP` should never exceed `targetSqrtP`, needs that guarantee to be either mathematically provable across its entire input space, or explicitly checked and defended against at runtime rather than simply assumed by every function that calls it. The fix involved correcting the rounding logic inside the affected helper functions so the invariant genuinely holds under all possible input combinations, not just the ones exercised by standard test suites.

A more defensive-programming version of this same fix, applicable more broadly, is to never let a downstream contract silently trust an upstream invariant without also checking it directly. If `Pool.sol`'s swap loop had explicitly asserted that `nextSqrtP` never exceeded `targetSqrtP` at the point of use, rather than trusting that `SwapMath.sol` would always uphold that promise, the transaction would have reverted instead of silently proceeding with corrupted liquidity accounting.

## 2. What the team actually did in response
- **Immediate:** advised all liquidity providers across all six affected chains to withdraw their funds as soon as the exploit was identified.
- **Investigation and disclosure:** published a detailed, technical post-mortem naming the exact function, the exact rounding condition, and a full timeline of the attacker's on-chain actions.
- **Negotiation:** the attacker made contact days later, reportedly demanding governance control of the protocol in exchange for returning stolen funds, an unusual and escalated situation compared to most exploit aftermaths in this collection.
- **Fix deployment:** corrected the rounding logic in the swap math library ahead of any future relaunch of affected pools.

## Why this incident matters as a teaching example
Most vulnerabilities in this collection can be explained, and prevented, through coding discipline: check before you act, update state before you send money, don't trust a single manipulable data source. KyberSwap is a useful counterexample, showing a category of bug that coding discipline alone cannot fully guard against, subtle mathematical errors inside carefully engineered fixed-point arithmetic. The broader lesson for any team building similarly math-heavy contracts is that formal verification tooling, exhaustive property-based testing across the full range of possible inputs, and independent mathematical review are meaningfully different from, and complementary to, a standard line-by-line security audit.
