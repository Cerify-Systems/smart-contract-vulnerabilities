# summary.md — GovernMental (March 2016)

## What happened
GovernMental was one of Ethereum's earliest Ponzi-style games. Participants sent ETH to join a shared jackpot. The rule: if 12 hours passed with no new participant joining, the last person to join won the entire pot. To pay out that winner, the contract's payout function looped through every participant recorded so far, clearing out their entries from the contract's internal arrays before releasing the funds.

As the game ran, the participant list grew. The gas required to loop through and clear that list grew right along with it. Eventually, the list became long enough that fully clearing it required more gas than a single Ethereum block could ever hold meaning the payout transaction could never successfully complete, no matter how much gas someone was willing to spend.

## When
- **March 2016**- GovernMental launched.
- Shortly after- the pot grew large enough (1,100 ETH) and the participant list long enough that the payout function became permanently uncallable.

## Where the vulnerable logic lives
The payout function's core flaw is structural: it requires iterating over an **unbounded, ever-growing array** (the full participant list) as a mandatory step before any funds can be released. There is no limit on how large that array can grow, and no way to pay out partial batches it's all-or-nothing.

## Why it happened
Ethereum transactions are capped by a maximum amount of gas that can be spent within a single block. Looping over an array costs gas proportional to the array's length the more entries, the more gas needed. GovernMental's payout function needed to loop over every participant to clear the game state before it could send the prize. Once the participant count grew large enough, the total gas cost of that loop exceeded the block gas limit itself. No transaction, regardless of how much gas the sender was willing to pay, can ever exceed a block's gas limit so the function became mathematically impossible to execute successfully, forever.

## What the "fix" would have been
There was no way to fix the already-deployed, already-stuck contract the funds remain locked to this day. The fix that matters here is a design lesson for future contracts:
- Never require a full loop over a growing, user-controlled list as a prerequisite for releasing funds.
- Use the "pull" payment pattern instead of "push" let each participant claim their own share individually (bounded, small, constant-gas operations), rather than the contract looping through everyone at once.
- If a loop over a list is unavoidable, cap the list size, or allow processing it in smaller batches across multiple transactions.

## Why this matters beyond 2016
This is one of the clearest, simplest illustrations of a **gas-limit denial-of-service** bug, a category distinct from reentrancy (control-flow hijacking) or memory/storage mismatches (stale data). It's also unusual among incidents in this repo because there was no attacker at all it's a pure self-inflicted design flaw that surfaced through completely normal, honest use of the contract.
