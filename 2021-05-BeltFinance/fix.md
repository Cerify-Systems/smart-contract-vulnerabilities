# fix.md — What Actually Fixed This

## 1. The code level fix
Value each strategy in a multi strategy vault independently, based on that strategy's own actual, verifiable balance, rather than deriving the value of the entire vault from a single strategy's pool state. If checking every strategy individually is too gas expensive, at minimum avoid trusting any single pool balance that can be meaningfully shifted within one transaction using borrowed capital such as a flash loan.

Broader principle worth carrying into any future contract review: any calculation that determines how much money moves should be checked against the question, can this specific input be temporarily distorted within a single transaction, and if the input is a pool balance, a spot price, or anything else that flash loans can move, the answer is usually yes.

## 2. What the team actually did in response
- **Immediate:** paused deposits and withdrawals across the affected vaults as soon as the attack was detected.
- **Investigation and disclosure:** published a detailed incident report explaining the exact sequence of the flash loan, the Ellipsis pool manipulation, and the resulting valuation error.
- **Patch:** fixed the valuation logic so it no longer relies on a single strategy's pool state as a proxy for the whole vault.
- **Compensation:** announced a compensation plan for BeltBUSD and 4Belt pool users who bore losses, funded in part from protocol reserves, alongside resuming deposits and withdrawals once the patch was live.

## Why this incident matters as a teaching example
This is a strong complementary example alongside reentrancy or memory versus storage bugs because it shows a third distinct root cause category, a valuation formula that trusted a single, manipulable data source as representative of a larger, multi part system. It is also a clean illustration of why flash loans, while a legitimate and useful DeFi primitive on their own, dramatically raise the stakes of any assumption a contract makes about what a normal, honest user's balance or trading pattern looks like within a single transaction.
