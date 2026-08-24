# summary.md — Belt Finance Hack (May 29, 2021)

## What happened
Belt Finance is a Binance Smart Chain protocol offering a stableswap AMM combined with multi strategy yield optimization. Its V2 vaults spread deposited BUSD across several yield generating strategies at once, including Venus and Ellipsis, each with a target allocation. Deposits went to the most undersubscribed strategy and withdrawals came from the most oversubscribed one, keeping the vault balanced over time.

To calculate how much a single vault share was worth, the protocol relied on the state of one specific strategy, the Ellipsis 3eps pool, and assumed the rest of the strategies were proportionally balanced with it. An attacker broke that assumption on purpose using a flash loan, made a single strategy look far more valuable than it actually was, then withdrew from it at the inflated price. They repeated the same sequence eight times for a combined profit of roughly 6.23 million BUSD.

## When
- **May 29, 2021, around 19:09 UTC** — the attack executed across eight repeated transactions in quick succession.
- Same day — Belt Finance paused deposits and withdrawals, confirmed the vulnerability, and began work on both a patch and a compensation plan.

## Where the vulnerable logic lives
The bug lived in Belt V2's multi strategy vault share valuation logic, specifically the function responsible for calculating the vault's total value and, from that, the value of a single share. That function trusted the Ellipsis strategy's pool state as representative of the whole vault, rather than summing or verifying each strategy's actual, independent balance.

## Why it happened
Belt's team assumed that under normal conditions, all strategies within a multi strategy vault would remain roughly balanced with each other, so checking just one strategy's pool would be a cheap, accurate enough proxy for the value of the whole vault. Flash loans break this kind of assumption by letting anyone temporarily acquire enormous capital within a single transaction, more than enough to drastically unbalance a pool for just long enough to manipulate a calculation, then repay the loan before the transaction ends. The attacker used a large flash loan funded deposit to push the Venus strategy out of balance, then swapped BUSD for USDT on Ellipsis to distort the pool the valuation function actually checked, causing the vault to overestimate the value of Venus shares before the attacker withdrew from Venus at that inflated price.

## What the fix was
- **Code level fix:** value each strategy independently based on its own real balance rather than deriving the whole vault's value from a single strategy's pool state. Any valuation logic that depends on a pool balance that can move within a single transaction needs to either use a manipulation resistant price source or explicitly account for the possibility of temporary, flash loan funded imbalance.
- **What the team actually did:** paused deposits and withdrawals as soon as the attack was detected, confirmed and patched the vulnerability, and announced a compensation plan for affected BeltBUSD and 4Belt pool users, funded in part by protocol reserves.

## Why this matters beyond 2021
This incident sits in the broader family of price or valuation manipulation bugs, distinct from reentrancy or memory versus storage mismatches. It is a strong example of why relying on any single, moment in time on chain price or balance reading, especially one that can be temporarily distorted with borrowed capital, is a fragile foundation for financial calculations. The same underlying lesson, do not trust a single manipulable data point as a stand in for ground truth, shows up across a huge share of DeFi hacks from this era.
