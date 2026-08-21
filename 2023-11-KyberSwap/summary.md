# summary.md — KyberSwap Elastic Exploit (November 23, 2023)

## What happened
KyberSwap Elastic is a concentrated liquidity automated market maker, similar in design to Uniswap V3, deployed across six blockchain networks. Liquidity providers could concentrate their funds within specific price ranges rather than spreading them across the entire price curve, which requires the protocol to track liquidity using discrete price points called ticks. An attacker discovered a rounding error in the contract responsible for calculating swap amounts and post-swap prices. Under a very precisely crafted set of conditions, this rounding error let the calculated price cross past a tick boundary in a way the code was never supposed to allow, which caused the pool's internal liquidity accounting to be counted twice. The attacker exploited this across multiple pools and multiple chains simultaneously, extracting an estimated $47 to $54.7 million within hours.

## When
- **November 22 to 23, 2023** — the exploit was executed across all six of KyberSwap Elastic's chain deployments in a coordinated sequence.
- Shortly after — KyberSwap advised all liquidity providers to withdraw their funds as a precaution.
- **November 30, 2023** — the attacker made contact with the KyberSwap team, reportedly demanding governance control of the protocol in exchange for returning funds.

## Where the vulnerable code lives
- `contracts/SwapMath.sol`, function `computeSwapStep` this is the core function responsible for calculating how much of a swap should be processed in the current price step and what the resulting price should be.
- The bug specifically traces through `computeSwapStep`'s calls to `calcReachAmount`, `estimateIncrementalLiquidity`, and `calcFinalPrice`, where rounding decisions compounded into a result that violated the function's own documented guarantee.

## Why it happened
`computeSwapStep`'s own code comments state the guarantee it is supposed to uphold: the resulting price after a swap step, `nextSqrtP`, should never exceed the target price, `targetSqrtP`. Under an extremely specific combination of pool liquidity and swap amount, values so precise that KyberSwap's own post-mortem describes them as "exceptionally high precision, making replication nearly impossible under normal circumstances," the rounding performed inside the function's helper calculations produced a `nextSqrtP` that landed on the wrong side of `targetSqrtP`. The calling `Pool.sol` contract's swap loop relied on this guarantee always holding true, and when it silently didn't, the contract's logic for updating active liquidity as a tick boundary is crossed ended up adding liquidity twice instead of once.

## What the fix was
- **Code-level fix:** correct the rounding logic in the affected calculations so that the `nextSqrtP <= targetSqrtP` guarantee is mathematically enforced under all input combinations, not just the ones covered by standard testing.
- **What the team actually did:** paused affected pools, published a detailed technical post-mortem naming the exact function and root cause, and worked to recover funds, including negotiations with the attacker after they made contact demanding governance control.

## Why this matters beyond 2023
This incident is frequently cited as one of the more sophisticated DeFi exploits of its year specifically because the bug was not a missing check or an obvious logic flaw. It was a genuine, deeply subtle rounding error inside carefully engineered fixed-point math, one that passed prior security audits. It is a strong reminder that mathematical correctness in smart contracts, especially in systems as intricate as concentrated liquidity AMMs, requires formal verification and exhaustive edge-case testing, not just careful manual review.
