# theRun: Insecure randomness

## Overview

| | |
|---|---|
| **Class** | Insecure / predictable on-chain randomness (SWC-120, "Bad Randomness") |
| **Contract** | `theRun` |
| **Chain** | Ethereum mainnet |
| **Category** | Public gambling / lottery-style contract |
| **Root cause** | "Random" outcomes derived entirely from publicly readable, miner-influenceable, on-chain data |
| **Documented in** | Trail of Bits — [`crytic/not-so-smart-contracts`](https://github.com/crytic/not-so-smart-contracts), `bad_randomness` example set |

---

## About the contract

`theRun` was an early (~2016-era) Ethereum gambling/lottery contract. Players sent Ether to the contract (between 0.5 and 20 ETH) via its fallback function, which queued them as a "player" entitled to a future payout with a multiplier applied. A portion of every deposit was skimmed into fees and into a shared `WinningPot`. On top of the standard queued payout mechanic, any deposit larger than 1 ETH (and larger than the payout currently owed to the front of the queue) triggered a **bonus draw**: the contract called an internal `random()` function, and if the result satisfied a modulo condition, the depositor won the entire `WinningPot` outright.

Selected contract fields relevant to the exploit:

```solidity
contract theRun {
    uint private Balance = 0;
    uint private Payout_id = 0;
    uint private Last_Payout = 0;
    uint private WinningPot = 0;
    ...
    struct Player {
        address addr;
        uint payout;
        bool paid;
    }
    Player[] private players;
```

The bonus-draw logic inside `Participate()`:

```solidity
// Winning the Pot :) Condition : paying at least 1 people with deposit > 2 ether and having luck !
if( ( deposit > 1 ether ) && (deposit > players[Payout_id].payout) ){
    uint roll = random(100); //take a random number between 1 & 100
    if( roll % 10 == 0 ){ //if lucky : Chances : 1 out of 10 !
        msg.sender.send(WinningPot); // Bravo !
        WinningPot=0;
    }
}
```

This is the mechanism attackers targeted: correctly predict (or force) `roll % 10 == 0` and drain `WinningPot` on demand.

---

## The `random()` function

```solidity
uint256 constant private salt = block.timestamp;

function random(uint Max) constant private returns (uint256 result){
    //get the best seed for randomness
    uint256 x = salt * 100 / Max;
    uint256 y = salt * block.number / (salt % 5);
    uint256 seed = block.number/3 + (salt % 300) + Last_Payout + y;
    uint256 h = uint256(block.blockhash(seed));
    return uint256((h / x)) % Max + 1; //random number between 1 and Max
}
```

### What's wrong with it

1. **`salt` is not actually random or per-call.** It's declared `constant`, so in the Solidity version this was written for it is evaluated once — effectively at deployment — and never changes again. A value fixed for the entire life of the contract contributes zero entropy to any later call.

2. **Every remaining input is public, queryable state.**
   - `block.number` — visible to anyone before they submit a transaction.
   - `Last_Payout` — a contract state variable, readable via a free `constant` call before betting.
   - None of these are secret from the perspective of a transaction being crafted to bet only when it will win.

3. **`block.blockhash(seed)` is frequently stale or zero.** `blockhash()` only returns a non-zero value for the **most recent 256 blocks**; for any block outside that window it silently returns `0`. Because `seed` is built from a fixed `salt` (deployment-time timestamp) plus `block.number`, it very often resolves to a block far outside the 256-block window as the contract ages — collapsing `h` to `0` and making the "random" output **deterministic**, not just weak.

4. **No commit/reveal, no external entropy.** The entire computation happens synchronously inside the same transaction as the bet. There is no separation between committing to a wager and revealing an unpredictable value — an attacker can replicate the exact formula off-chain (or in their own contract) before deciding whether to send the transaction at all.

5. **Miner influence.** Even setting aside the staleness bug, `block.number`, and (in the general pattern) `block.timestamp` are values the block producer has partial latitude over. A miner could selectively include/exclude/reorder transactions, or decline to publish an unfavorable block, to bias the outcome.

Net effect: the function that was supposed to produce unpredictable outcomes for a gambling payout instead produced a value that was either fully computable in advance from public data, or literally constant due to the blockhash staleness bug.

---

## The exploit

Because every input to `random()` is either fixed, public state, or a stale/zero blockhash, an attacker did not need to break any cryptography — they only needed to **read state before betting**:

1. Query the contract's public view functions (e.g. `Total_of_Players`, and indirectly `Last_Payout` via `WatchLastPayout()`) and the current block number, both freely available with no transaction cost.
2. Reproduce the exact `random(100)` formula off-chain (or inside an attacker-controlled helper contract) using those same public values.
3. Only submit a real bonus-eligible deposit (> 1 ETH, and larger than the payout owed to the head of the queue) when the precomputed result satisfies `roll % 10 == 0`.
4. If the stale-blockhash condition applied, the result was deterministic on essentially every call, meaning bets could be timed to win reliably rather than merely "usually."
5. Repeat to drain `WinningPot` on demand, walking away with funds contributed by honest participants who were relying on the "1 in 10" odds advertised by the contract.

No reentrancy, no arithmetic overflow, no access-control bug was needed — the entire attack surface was **the randomness source being public and/or degenerate**.

---

## Loss incurred

There is no independently verified, widely reported dollar or ETH loss figure specifically attributable to `theRun` in mainstream security post-mortems (unlike, e.g., the DAO hack or the Parity multisig hack, which had well-documented on-chain forensic totals). `theRun` is preserved primarily as a **canonical code example** of the bad-randomness pattern in Trail of Bits' `not-so-smart-contracts` repository rather than as a headline incident with a confirmed loss total.

That said, the broader "bad randomness" vulnerability class it exemplifies is well-documented as materially costly across the Ethereum gambling-contract ecosystem of 2016–2019 — academic surveys tracking this vulnerability class report losses exceeding **$30 million** across affected decentralized applications (lotteries, dice games, and similar contracts using on-chain pseudo-randomness), with high-profile examples including *Fomo3D* and *Dice2Win*. Readers should treat `theRun` as representative of this class rather than assume a specific confirmed loss figure exists for it individually.

---

## Reference links

- Trail of Bits, **Not So Smart Contracts** (bad randomness category + write-up):
  https://github.com/crytic/not-so-smart-contracts/blob/master/bad_randomness/README.md
- Vulnerable contract source, **`theRun.sol`**:
  https://github.com/crytic/not-so-smart-contracts/blob/master/bad_randomness/theRun_source_code/theRun.sol
- Background: *Predicting Random Numbers in Ethereum Smart Contracts* (Positive Technologies):
  https://blog.positive.com/predicting-random-numbers-in-ethereum-smart-contracts-e5358c6b8620
- Ethereum StackExchange discussion on secure on-chain randomness:
  https://ethereum.stackexchange.com/questions/191/how-can-i-securely-generate-a-random-number-in-my-smart-contract

---

## Learning lessons

1. **Never derive security-critical randomness from on-chain data.** `block.timestamp`, `block.number`, `block.blockhash`, `block.difficulty`/`block.coinbase`, and contract state variables are all either publicly readable before a transaction lands or partially controllable by the block producer. If a value can be read or influenced before the outcome it "protects" is finalized, it isn't random from an attacker's perspective.

2. **Watch for `blockhash()` staleness.** `blockhash(n)` only returns a meaningful value for the last 256 blocks; referencing an older or future block silently returns `0`. Any randomness formula that can drift outside that window degrades from "weak" to "completely predictable" without any error being thrown — a dangerous silent failure mode.

3. **Same-transaction "randomness" is not randomness.** If the value used to decide a bet is computed in the very same call that places the bet, an attacker can simply replicate that computation off-chain first and choose whether to submit the transaction at all. True unpredictability requires a value that is *not knowable* at the time the wager is placed.

4. **Commit-reveal alone doesn't fully solve this.** A user who has funds riding on the outcome of a reveal can simply withhold their secret if it turns out unfavorable (a griefing/bias vector), unless the design defends against that (e.g., via forced timeouts, penalties, or aggregation across many uncorrelated commits).

5. **Use externally-sourced, verifiable randomness for anything valuable.** Oracle-based verifiable random functions (e.g., Chainlink VRF) or verifiable delay functions (VDFs) are the accepted modern mitigations — randomness generated and attested outside the deterministic, publicly-visible EVM state, with a proof the contract can check on-chain.

6. **Threat-model the miner, not just other players.** Any design that gives a block producer even partial influence over the inputs to a payout decision should be assumed to be exploitable by that block producer, given enough value at stake to justify the effort of reordering or withholding blocks.

7. **Treat "constant" seeds as a code smell.** A `constant` value initialized from a runtime expression (like `block.timestamp` at deployment) is fixed for the contract's lifetime — it is publicly discoverable by simply reading the deployed bytecode/state, and reusing it across every future call removes any per-call entropy the author may have believed it provided.