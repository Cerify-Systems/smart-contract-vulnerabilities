# Fomo3D Block-Stuffing / MEV DoS Attack (August 2018)

## Overview

| Field | Detail |
|---|---|
| **Target** | Fomo3D — Ethereum "last man standing" jackpot game |
| **Date** | August 22, 2018 (Round 1) — repeated in Rounds 2 & 3 |
| **Vulnerability Type** | EVM Block Gas Limit Exploitation / Economic Front-Running (Denial of Service) |
| **Classification** | SWC-128 (DoS with Block Gas Limit) + SWC-116 (Block Timestamp / Time Dependence) |
| **Loss** | ~10,469 ETH jackpot claimed (~$10.4M at contemporary valuation) |
| **Root Cause** | Design assumed fair, guaranteed transaction inclusion; did not account for miner gas-price ordering or block gas limits |

---

## What Fomo3D Was

Fomo3D was a decentralized "exit scam"-style game. Players purchased "keys" with ETH, which:

1. Added funds to a shared jackpot pot.
2. Extended a countdown timer by **30 seconds**.
3. Made the buyer the new "last buyer."

When the countdown reached **zero**, the *last person to have bought a key* won the majority of the pot. The mechanic incentivized players to buy a key at the last possible moment, creating a natural race condition at the end of every round.

---

## The Vulnerability — What Was the Actual Issue

This was **not** a bug in Solidity logic. There was no reentrancy, integer overflow, or broken access control in the contract itself. The flaw was a **flawed economic/design assumption**:

> The game assumed that transaction submission and network access were "fair" — i.e., that any player racing to be "last" had an equal chance of getting their transaction mined before the timer expired.

This assumption ignored two fundamental properties of the Ethereum base layer:

- **Block gas limit**: each block can only hold a finite amount of total gas.
- **Miner transaction ordering**: miners prioritize transactions by gas price (highest-paying transactions get included first).

Because the payout logic depended purely on *whoever's transaction lands last on-chain before the timer expires*, and Ethereum does not guarantee fair or timely inclusion of any specific transaction, the game's fairness model broke down under adversarial, well-funded conditions.

---

## Attack Flow

1. **Position as last buyer** — The attacker submitted a normal key-purchase transaction, becoming the current "last buyer" and starting/refreshing the 30-second countdown.
2. **Flood the network** — Immediately after, the attacker fired off dozens of self-to-self (or junk) transactions with deliberately **very high gas prices** and **high gas limits**.
3. **Monopolize block space** — Because miners order transactions by gas price to maximize their own fees, these high-paying junk transactions filled up the *entire* gas capacity of consecutive blocks, crowding out every other pending transaction — including legitimate `buyCore` key-purchase calls from other players.
4. **Sustain the stuffing** — The attacker repeated this for roughly **10–13 consecutive blocks** (~150–195 seconds at ~15s/block), which was more than enough to outlast the 30-second timer window, since no other player's key-purchase transaction could reach the contract in time.
5. **Timer expires, attacker wins** — With no competing purchases able to land on-chain, the round's countdown hit zero while the attacker was still the last registered buyer, and the contract paid out the jackpot to them.

This pattern was later confirmed to have repeated in **Round 2** and **Round 3** of the game, with different addresses executing the same block-stuffing strategy.

---

## Why This Was Profitable (Attack Economics)

Block-stuffing attacks are only rational when:

```
Cost of stuffing N blocks with high-gas junk txs  <  Expected jackpot payout
```

Fomo3D's payouts were enormous (multi-million-dollar pots), while the cost to stuff ~10–13 blocks with high gas-price transactions was only a few hundred to low-thousands of dollars in gas fees. This asymmetry made the attack trivially profitable and essentially guaranteed to be attempted by rational actors as each round neared its end.

---

## Smart Contract & Function References

The actual verified Fomo3D contract source (as pulled from Etherscan) is mirrored publicly on GitHub:

- **Contract source (Etherscan mirror):** https://github.com/foreachsky/Fomo3D-1
- **Primary file:** `FoMo3Dlong.sol`

### Key functions involved

| Function | Role in the exploit |
|---|---|
| `buyCore` | Entry point for a key purchase; this is the function every player — including the attacker and the crowded-out victims — needed to reach in time. |
| `core` | Internal function called by `buyCore`; updates the pot, key count, and **extends the round's end timestamp** (`round_.end`) by 30 seconds per purchase. |
| `determinePID` | Resolves/registers the player ID tied to the purchasing address during `core` execution. |
| Round timer logic (`round_.end` update inside `core`) | The actual "last buyer wins" state — trivial to read/predict, but with no protection against an attacker denying others access to the mempool/blockspace needed to update it. |

None of these functions were logically "broken" — the exploit lived entirely at the **network/mempool layer**, outside the contract's control.

---

## Loss & Impact

- **Direct loss:** ~10,469 ETH (~$10.4M at the time) paid out to the attacker as the Round 1 jackpot — funds that came from other players' key purchases, not newly minted value.
- **Network impact:** For several minutes during each round-ending stuffing event, the attacker's junk transactions congested the Ethereum mempool, delaying **unrelated** transactions from other users/dApps who were competing for the same block space — a negative externality imposed on the entire network, not just Fomo3D players.
- **Precedent impact:** Fomo3D became one of the most cited real-world case studies for **block gas limit DoS** and **time-dependence** vulnerabilities in smart contract security literature (SWC Registry, ConsenSys best practices, multiple academic surveys), directly shaping how auditors evaluate time-boxed, winner-takes-all contract logic.
- **Repeat exploitation:** The same technique was successfully repeated in Rounds 2 and 3 by different actors, showing the vulnerability was systemic to the design, not a one-off fluke.

---

## The Fix / Mitigations

Because the root cause was a **design-level trust assumption** rather than a code bug, there was no single "patch" that retroactively fixed the deployed Fomo3D contract — the game's fundamental win condition was inherently exploitable as designed. The fixes that emerged were **preventive design patterns** adopted industry-wide for future contracts with time-boxed or "be first/last" mechanics:

1. **Avoid single-transaction "race to be last/first" designs.** Any mechanic where the sole determinant of a large payout is "whoever's transaction lands last/first before a deadline" is inherently gameable via block-stuffing or front-running.
2. **Commit-reveal schemes.** Decouple the *intent* to participate from the *timing advantage* — e.g., require players to commit a hashed action in advance and reveal it later, so last-moment gas-price wars can't determine the outcome.
3. **Randomized / VRF-based winner selection** instead of purely order-dependent logic, removing the incentive to manipulate transaction ordering at all.
4. **Rate-limit or cap the timer-extension mechanic**, or use fixed, non-extendable deadlines based on block number ranges with a grace/lockout period immune to last-second stuffing.
5. **Off-chain ordering / Layer-2 or batch-auction mechanisms** (e.g., frequent batch auctions used later in DeFi) that don't reward pure transaction-priority games.
6. **General auditing guidance (post-incident):** the SWC Registry entries **SWC-128 (DoS with Block Gas Limit)** and **SWC-116 (Block Timestamp Dependence)** were reinforced/popularized in smart contract security checklists specifically citing Fomo3D as the canonical example, pushing auditors to flag any contract logic that assumes fair or guaranteed transaction inclusion within a tight time window.

---

## References

- Contract source mirror: https://github.com/foreachsky/Fomo3D-1
- Attack documentation issue: https://github.com/ConsenSys/smart-contract-best-practices/issues/182
- GitHub topic — Fomo3D / block-stuffing analyses: https://github.com/topics/fomo3d
- Detailed block-by-block breakdown (Round 1): https://medium.com/@zhongqiangc/smart-contract-stuffing-fomo3d-42cb1d11ab03
- Round 2 analysis: https://medium.com/@zhongqiangc/block-stuffing-fomo3d-part-2-c8c1bea282fa
- Round 3 analysis: https://medium.com/@zhongqiangc/block-stuffing-fomo3d-part-3-bde3671482a4
- Academic survey citing Fomo3D as A3 (bad randomness + DoS with block gas limit): *Survey on Quality Assurance of Smart Contracts* (arXiv:2311.00270)
- Original technical anatomy write-up: https://osolmaz.com/2018/10/18/anatomy-block-stuffing/