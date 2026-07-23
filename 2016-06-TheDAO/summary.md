
## What happened
The DAO was a smart-contract-based investment fund on Ethereum. Thousands of people put ETH into it and got voting tokens in return. One built-in feature let a token holder "split" pull their fair share of ETH out into their own separate mini-DAO if they disagreed with the group's decisions. An attacker found a bug in the code behind that split feature, exploited it to repeatedly withdraw the same funds before the contract could update its own records, and drained roughly 3.6 million ETH (~$50-60 million at the time). The incident was so severe that the Ethereum community rewrote a piece of blockchain history to recover the funds a decision so controversial it split Ethereum into two separate blockchains: Ethereum (ETH) and Ethereum Classic (ETC).

## When
- **April 30, 2016** — The DAO launched, crowdsale began.
- **May 2016** — Over $150M raised, becoming one of the largest crowdfunds in history at the time. Security researchers had already flagged concerns about the code before the attack.
- **June 17, 2016** — The attack happened. Funds drained into an attacker-controlled "child DAO."
- **June 24-28, 2016** — Community attempted a "soft fork" fix, found it had its own exploitable flaw, abandoned it.

## Where the vulnerable code lives
- `contracts/DAO.sol` → function `splitDAO()`- this is where the bug actually is.
- `contracts/ManagedAccount.sol` → function `payOut()`-this is the actual line that sends ETH and lets the attacker's code jump back in.

## Why it happened 
The contract sent money to the caller *before* updating its own internal record of "this person has already been paid." Because the caller was itself a smart contract, receiving that money let the caller's own code run immediately — and that code simply asked for the same payout again, before the original record-keeping had caught up. This is called a reentrancy bug an external call re-enters the same (or a related) function before it's finished updating its state.

## What the fix was
- **The coding lesson:** always update your own internal state (balances, "already paid" flags) before sending money out never after. This principle is now called checks-effects-interactions, and it's one of the first rules taught in smart contract security today.
- **What actually happened in this specific case:** since the buggy contract was already permanently deployed, Ethereum's developers and mining majority executed a hard fork, an "irregular state change" that moved the at-risk funds into a neutral recovery contract so original investors could reclaim their ETH. This wasn't fixing the bug in place, it was a one-time community-decided rollback/redirect of specific balances at the protocol level.

## Why this matters beyond 2016
This is the incident that put "reentrancy" on the map as a vulnerability class. Nearly every major reentrancy hack since (bZx, Cream Finance, Fei Protocol, and many others) follows the exact same underlying mistake this contract made. Tools like OpenZeppelin's `ReentrancyGuard` modifier exist specifically because of lessons learned here.
