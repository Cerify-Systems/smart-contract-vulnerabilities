# SmartBillions Lottery Hack (October 2017)

## Overview

| | |
|---|---|
| **Project** | SmartBillions — "the first fully decentralized and transparent lottery" on Ethereum |
| **Date** | October 4–5, 2017 (during a public hackathon) |
| **Vulnerability Type** | Insufficient On-Chain Randomness / Stale `blockhash` Assumption |
| **Loss** | ~400 ETH (~$120,000 at the time) |
| **Status** | Contract hacked twice within 2 days of the hackathon opening; SmartBillions team suspended the event |

SmartBillions ran a public bug-bounty "hackathon" ahead of its ICO, offering a 1,500 ETH prize pool to anyone who could break the smart contract before it went live with real investor funds. The event backfired almost immediately — attackers found and exploited a randomness flaw and drained ETH from the contract before the team could pull the plug.

---

## Description

SmartBillions was a bet-on-a-number lottery contract. Players placed a bet at a given block, and the contract computed the "winning number" using **`blockhash()`** of a specific Ethereum block tied to that bet.

The flaw lay in a well-known but frequently overlooked EVM limitation:

> The EVM only retains the `blockhash` of the **most recent 256 blocks**. If a contract calls `blockhash(n)` for a block `n` that is older than 256 blocks in the past, the call does **not** revert or error — it silently returns `bytes32(0)`.

SmartBillions used this stale/zeroed block hash as if it were legitimate entropy, and fed it directly into the prize-calculation logic. Once a bet's reference block fell outside the 256-block window, the "random" result became a **known constant (`0`)** instead of a real hash — completely eliminating the unpredictability the lottery depended on.

---

## Why This Vulnerability Happened (Root Cause)

1. **On-chain data was treated as a secure randomness source.** `block.blockhash`, like `block.timestamp` and `block.difficulty`, is publicly visible, deterministic, and — in this case — even goes to zero outside a fixed window. None of these are cryptographically secure sources of entropy.
2. **No bounds/validity check on the hash value.** The contract never checked whether `blockhash()` had returned a "real" hash vs. the fallback zero value before using it to compute a payout.
3. **The payout function trusted user-controlled timing.** Because a player calls the "claim winnings" function whenever *they* choose, an attacker can simply wait for a favorable — and in this case, guaranteed — state (>256 blocks) before triggering settlement. The contract had no mechanism to force settlement promptly or to invalidate stale bets safely.
4. **A backup mechanism existed but did not close the gap.** The code contains an `else` branch that tries to source a hash from a secondary storage mechanism (`getHash()` / `hashFirst`) for bets older than 256 blocks — an apparent attempt to patch this exact issue — but the fallback path could still resolve to a predictable/invalid value, leaving the underlying weakness (relying on chain data instead of verifiable off-chain randomness) intact.

---

## Attack Flow

1. **Bet placement** — The attacker calls the betting function and places a wager, which records the current `block.number` as `player.blockNum` for that bet.
2. **Wait it out** — Instead of claiming the result normally (within the 256-block window, when `blockhash` would still return a real, unpredictable hash), the attacker deliberately **does nothing** and lets more than 256 blocks pass (roughly ~1 hour on Ethereum mainnet at the time).
3. **Guaranteed stale hash** — Once `block.number >= player.blockNum + 256`, any call to `block.blockhash(player.blockNum)` returns `bytes32(0)` — a value the attacker knew in advance, before ever placing the bet.
4. **Trigger settlement** — The attacker calls the payout/`won()` function. The contract computes the "winning number" from the zeroed hash, producing a fixed, predictable outcome (effectively `000000`).
5. **Claim the jackpot** — Because the attacker's bet was structured to match this predictable outcome, the contract pays out as if they had won a genuine random draw.
6. **Repeat** — The same technique was reproducible, which is how **two separate individuals** were able to extract ETH from the contract before the team intervened.

This is a textbook example of the **"Entropy Illusion"** — the mistaken belief that block-derived values are unpredictable or unmanipulable, when in fact they're either publicly computable in advance, minable by validators, or (as here) deterministically zero once a retention window expires.

---

## The Real-World Contract

- **Repository:** [github.com/SmartBillions/SmartBillions](https://github.com/SmartBillions/SmartBillions)
- **Vulnerable file:** [`SmartBillions.sol`](https://github.com/SmartBillions/SmartBillions/blob/master/SmartBillions.sol)
- **Attacker's winning address (per SmartBillions' own hackathon writeup):** `0x6245c1804f7fceb305a60bbb5cb6e18f939edb69` (see Etherscan)

### The Faulty Logic

The unsafe pattern appears in both the payout path and the read-only preview function that mirrors it:

```solidity
if (block.number < player.blockNum + 256) {
    hash = uint24(block.blockhash(player.blockNum));
    prize = betPrize(player, uint24(hash));
} else {
    if (hashFirst > 0) {
        // lottery is open even before swap space (hashes) is ready,
        // but player must collect results within 256 blocks after run
        hash = getHash(player.blockNum);
        if (hash == 0x1000000) { // load hash failed :-(
            LogLate(msg.sender, player.blockNum, block.number);
            bets[msg.sender] = Bet({value: 0, betHash: 0, blockNum: 1});
            return();
        } else {
            prize = betPrize(player, uint24(hash));
        }
    }
    ...
}
```

**Functions involved:**

| Function | Role in the exploit |
|---|---|
| `won()` (payout function) | Computes and pays out the prize using `block.blockhash(player.blockNum)`, or the stale/fallback hash once outside the 256-block window. This is the function attackers ultimately called to cash out. |
| `betOf(address _who)` | A `constant`/view function that mirrors the exact same flawed hash logic to preview whether a bet won — confirming the predictable outcome before the attacker ever called `won()`. |
| `getHash(player.blockNum)` | Secondary/fallback hash source for bets older than 256 blocks; intended as a patch, but did not fully eliminate predictable/invalid hash outcomes. |

---

## Loss & Impact

- **Financial loss:** Approximately **400 ETH**, valued at roughly **$120,000** at October 2017 prices, drained by **two separate attackers** within about 48 hours of the hackathon launching.
- **Event fallout:** SmartBillions had explicitly invited hackers to break the contract via a 1,500 ETH bug-bounty hackathon ahead of its planned ICO (scheduled for October 16, 2017). The team was forced to **halt the hackathon early** once the exploit was discovered and funds were withdrawn.
- **Reputational impact:** Despite the loss, the team publicly framed the outcome positively — since the flaw surfaced during a controlled hackathon rather than after the ICO with real investor deposits at stake — and announced plans to revise the contract and relaunch a second hackathon round with the same 1,500 ETH prize.
- **Industry impact:** The incident became (and remains) a widely cited case study in smart-contract security write-ups and CTF-style challenges (e.g., "Capture the Ether") illustrating why on-chain block data must never be used as a randomness source for anything of financial value.

---

## The Fix

The general remediation pattern adopted by the industry after incidents like this — and the direction SmartBillions itself pursued in its contract revision — includes:

1. **Never derive randomness from block properties alone.** `blockhash`, `block.timestamp`, `block.difficulty`/`block.prevrandao`, and similar values are either predictable, attacker-influenceable, or (as demonstrated here) go to zero outside a fixed retention window.
2. **Enforce a strict, bounded settlement window.** If a hash-based scheme is used at all, payouts referencing an out-of-range or zeroed hash should be explicitly **rejected/reverted**, and the bet **refunded**, rather than silently resolved using an invalid value.
3. **Use verifiable off-chain randomness.** The modern standard is an oracle-based verifiable random function — most commonly **Chainlink VRF** — which provides cryptographically provable randomness that cannot be predicted or manipulated by users or miners/validators before it's revealed on-chain.
4. **Commit–reveal schemes as an alternative.** Where an oracle isn't available, a two-phase commit–reveal design (with economic penalties for non-reveal) can reduce — though not fully eliminate — manipulation risk, and is a weaker fallback compared to VRF-style solutions.
5. **Fail-closed, not fail-open, on missing data.** Any code path that *can* receive a zero/default/stale value (like the `blockhash` fallback in this contract) should treat that as an invalid state and halt, rather than treat the default value as a legitimate result to act on.

---

## References

- GitHub — Source repository: [github.com/SmartBillions/SmartBillions](https://github.com/SmartBillions/SmartBillions)
- GitHub — Vulnerable contract file: [SmartBillions.sol](https://github.com/SmartBillions/SmartBillions/blob/master/SmartBillions.sol)
- SmartBillions (Medium) — [Hackathon Announcement & Post-Mortem: "Smart Contract hacked with $120,000!"](https://medium.com/@SmartBillions/smartbillions-hackathon-smart-contract-hacked-with-120-000-b62a66b34268)
- CalvinAyre — ["$500K hack challenge backfires on blockchain lottery SmartBillions"](https://calvinayre.com/2017/10/13/bitcoin/500k-hack-challenge-backfires-blockchain-lottery-smartbillions)
- crypto.news — ["The Blockchain Lottery SmartBillions Was Hacked for $120,000"](https://crypto.news/blockchain-lottery-smartbillions-hacked-for-120000/)
- Medium (0xD4v3) — ["Road To Security — Topic 6 — Entropy Illusion (Part 2)"](https://medium.com/@0xD4v3/road-to-security-topic-6-entropy-illusion-part-2-6ec85b4008a2)
- Medium (Coinmonks) — ["Smart Contract Exploits Part 1 — Featuring Capture the Ether (Lotteries)"](https://medium.com/coinmonks/smart-contract-exploits-part-1-featuring-capture-the-ether-lotteries-8a061ad491b) — explains the same `blockhash` 256-block limitation via the "Capture the Ether" CTF lottery challenges.

