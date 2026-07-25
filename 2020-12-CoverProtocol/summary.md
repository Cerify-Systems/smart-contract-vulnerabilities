# summary.md- Cover Protocol Hack (December 28, 2020)

## What happened
Cover Protocol was a DeFi insurance platform. To reward people who provided liquidity, it ran a "shield mining" program through a contract called `Blacksmith`, users staked Balancer Pool Tokens (BPT) and earned COVER tokens in return. A bug in `Blacksmith.sol`'s `deposit()` function let attackers trick the contract into minting an essentially unlimited number of COVER tokens, which they then sold on the open market. The COVER token price collapsed within hours as a result.

## When
- **December 28, 2020, ~12:02 PM UTC**- first exploit transaction mints ~40 quintillion (40 × 10^18) COVER tokens.
- Same day the core team (alerted by a non-dev team member, since developers were asleep) wakes up, removes minting rights from `Blacksmith`, and works with Yearn Finance partners (Emiliano Bonassi) to confirm and reproduce the bug.
- Same day a white-hat actor known as "Grap Finance" independently exploits the same bug, mints and sells COVER, then burns the minted tokens and returns the resulting ETH to the team effectively donating back most of the extractable value before a malicious actor could take it all.

## Where the vulnerable code lives
- `Blacksmith.sol` function `deposit()` -this is where the bug actually is.
- `updatePool()` — the function whose *correct* storage update is what makes the bug possible (it updates the real data, but not the stale memory copy already in use).

## Why it happened
Solidity lets you copy a `storage` variable (permanent, on-chain data) into a `memory` variable (temporary, cheaper-to-access working copy) to save gas. The bug `deposit()` copied a `pool` struct into memory, then called `updatePool()`, which correctly updated the real storage version of that same pool but the earlier memory copy is a **separate, disconnected copy**, not a live reference, so it never reflected that update. The rest of `deposit()` kept using the outdated memory values to calculate how many reward tokens a user should be excluded from receiving (`rewardWriteoff`), and that stale calculation could be manipulated to make the contract believe it owed a user an enormous reward.

## What the fix was
- **Code-level fix:** re-read the pool from storage (or reorder the logic) after `updatePool()` runs, so calculations always use the freshest data never rely on a memory copy taken before a storage-modifying call.
- **What the team actually did:** immediately revoked `Blacksmith`'s minting permissions (redirected them to a dummy contract), worked with Yearn Finance to confirm the exploit, and issued a new COVER token via a "shield mining" relaunch with the bug fixed, alongside a compensation plan for affected users funded partly by the returned white-hat funds.

## Why this matters beyond 2020
This is a clean, canonical example of a **memory vs. storage bug** a Solidity-specific footgun that doesn't exist in most other languages, since most languages don't force developers to think explicitly about "is this a live reference or a disconnected copy?". 
