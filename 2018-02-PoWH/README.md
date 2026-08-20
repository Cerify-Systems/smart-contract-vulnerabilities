# Proof of Weak Hands (PoWH) Coin — Underflow Exploit (Feb 1, 2018)

## Summary

| | |
|---|---|
| **Name** | Proof of Weak Hands (PoWH) Coin |
| **Date** | February 1, 2018 |
| **Loss** | ~866 ETH (~$800,000 at the time) |
| **Vulnerability Type** | Integer underflow via missing access-control parameter |
| **Root Cause** | Internal `sell()` function trusted `msg.sender` instead of the actual token owner (`_from`) passed into `transferFrom()` |
| **Standard weakness class** | CWE-682 (Incorrect Calculation) / unchecked arithmetic underflow, enabled by a broken trust boundary between `transferTokens()` and `sell()` |
| **Contract** | `0xa7ca36f7273d4d38fc2aec5a454c497f86728a7a` |
| **Language / Compiler** | Solidity ^0.4.18 (pre-SafeMath era, no built-in overflow/underflow checks) |

PoWH was a self-described, openly-admitted Ponzi scheme created by 4chan's `/biz/` board in late January 2018. It attracted over 1,000 ETH in three days before an integer underflow bug allowed an attacker to fabricate a near-infinite token balance and drain the contract of 866 ETH.

---

## Background

PoWH worked as a bonding-curve dividend token:

- Users **buy** tokens by sending ETH to the contract (`buy()` / `fund()`), at a price that rises as more tokens are minted.
- Users **sell** tokens back for ETH (`sell()`), which lowers the price for everyone else.
- Every trade skims a small dividend fee, distributed pro-rata to existing token holders.
- The whole system was funded entirely by later buyers' ETH — a Ponzi mechanic that the project openly advertised as its selling point ("weak hands" = people who sell early).

The project was based on Jochen Hoenicke's original Ponzi-token concept, and its ERC-20-like interface allowed the standard `approve()` / `transferFrom()` delegated-transfer pattern, which is what made the exploit possible.

---

## The Vulnerability

### Faulty function: `sell()`

```solidity
function sell(uint256 amount) internal {
    var numEthers = getEtherForTokens(amount);

    totalSupply -= amount;
    balanceOfOld[msg.sender] -= amount;   // <-- BUG: decrements msg.sender, not the token owner

    var payoutDiff = (int256) (
        earningsPerShare * amount + (numEthers * PRECISION)
    );
    payouts[msg.sender] -= payoutDiff;
    totalPayouts -= payoutDiff;
}
```

`sell()` is never called directly by users. It's invoked internally from **`transferTokens(_from, _to, _value)`** whenever tokens are sent to the contract's own address — that's the mechanism by which "selling" happens under the hood (send-to-self triggers a sale).

`transferTokens()` correctly validates that `_from` owns enough tokens to cover `_value`. The problem is what happens *after* that check passes: it calls `sell(_value)`, but never tells `sell()` **whose** balance to actually decrement. `sell()` just assumes it's always operating on `msg.sender` — the caller of the current transaction — rather than `_from`, the account whose tokens are supposedly being spent.

This breaks down the moment `msg.sender != _from`, which is exactly the normal case for a delegated transfer authorized via `approve()`.

### Why this happened

1. **Broken trust boundary**: `transferTokens()` validates ownership against `_from`, but `sell()` silently re-derives "the seller" from `msg.sender` — two different notions of "who is selling" inside the same call.
2. **No checked arithmetic**: Solidity 0.4.x had no built-in overflow/underflow protection, and this contract predates widespread SafeMath adoption. `balanceOfOld[msg.sender] -= amount` on an account with a balance of `0` doesn't revert — it silently wraps around to `2^256 - 1`.
3. **ERC-20's `approve`/`transferFrom` pattern was bolted onto Ponzi-token logic never designed for delegated transfers**, so no one had reasoned through what "sell on behalf of someone else" should even mean.

---

## Attack Flow

1. **Setup** — Attacker funds a secondary, near-empty account (`0xb9cd700b8a16069bf77ededc71c3284780422774`) with a trivial number of tokens, then has it `approve()` the attacker's primary account to spend on its behalf.
2. **Trigger the underflow** — Attacker calls:
   ```
   transferFrom(_from = secondaryAccount, _to = ContractAddress, _value = 1)
   ```
   - `transferTokens()` checks that `secondaryAccount` owns ≥1 token → passes.
   - Because `_to` is the contract's own address, this internally calls `sell(1)`.
   - Inside `sell()`, `balanceOfOld[msg.sender]` is decremented — but `msg.sender` is the **attacker's primary account**, which owns **zero** tokens.
   - `0 - 1` underflows to `2^256 - 1` (≈1.1579 × 10⁷⁷), which is now the attacker's primary-account token balance.
3. **Cash out** — Attacker sells down a modest, safe portion of that fabricated balance for ETH via the normal `sell()` path (this time called by them directly, so `msg.sender` correctly matches their own inflated balance).
4. **Drain** — Attacker calls `withdraw()`, pulling the accumulated ETH — including dividends attributable to every other real holder — out of the contract.

   Note: the attacker fumbled once — they first tried to transfer their *entire* fabricated balance into the contract to sell it all at once, which underflowed their balance right back to the max value again (an amusing side effect of the same bug). On the second attempt they sold a smaller, safe portion instead.

### On-chain evidence

| Step | Transaction |
|---|---|
| Underflow-triggering `transferFrom` | `0xb08fb4ec0b3c7ed15579fa65c84778296f858d48e51b86e140f5ce5350ce029f` |
| Final `withdraw()` draining ~866 ETH | `0x496c0411f52978dfd7953b7e6965465977162bfaf7b88c0c78fcdc97cd395d62` |

The secondary account used to set up the exploit (`0xb9cd700b8a16069bf77ededc71c3284780422774`) still shows the maximum `uint256` token balance on Etherscan to this day, a permanent artifact of the underflow.

---

## Loss & Impact

- **~866 ETH** (~**$800,000 USD** at February 2018 prices) drained from the contract in a single sequence of transactions, roughly three days after launch.
- Every legitimate holder's dividends and principal were wiped out — the pooled ETH backing the token was gone, collapsing the price to effectively zero.
- The **same underlying bug was reused against numerous PoWH clones/forks** that copy-pasted the vulnerable `sell()`/`transferTokens()` logic without fixing it, multiplying the damage across the broader "Ponzi-token" fad of early 2018.
- Beyond the direct financial loss, the incident became a widely cited early case study for:
  - the danger of **implicit trust in `msg.sender`** inside internal functions reached via multiple call paths,
  - the necessity of **checked arithmetic** (this event predates OpenZeppelin's SafeMath becoming a near-universal default),
  - and the risks of unaudited, rapidly-forked "meme" DeFi/Ponzi contracts.

---

## The Fix

The core fix is straightforward and addresses both root causes identified above:

1. **Thread the correct account through the call chain** — `sell()` must know *whose* balance it's adjusting rather than inferring it from `msg.sender`:
   ```solidity
   function sell(address _from, uint256 amount) internal {
       var numEthers = getEtherForTokens(amount);

       totalSupply -= amount;
       balanceOfOld[_from] -= amount;   // decrement the actual token owner

       var payoutDiff = (int256) (
           earningsPerShare * amount + (numEthers * PRECISION)
       );
       payouts[_from] -= payoutDiff;
       totalPayouts -= payoutDiff;
   }
   ```
   And `transferTokens()` must call `sell(_from, _value)` instead of the parameterless `sell(_value)`.

2. **Use checked/safe arithmetic** so any residual accounting mistake reverts the transaction instead of silently wrapping around:
   ```solidity
   balanceOfOld[_from] = SafeMath.sub(balanceOfOld[_from], amount); // reverts on underflow
   ```
   This became standard practice industry-wide shortly after this generation of incidents, and Solidity ≥0.8.0 later made overflow/underflow checks the **default language behavior**, removing the need for SafeMath entirely.

3. **Never let an internal privileged function silently substitute `msg.sender` for a caller-supplied identity parameter** once that identity has already been validated by an outer function — either pass the validated identity through explicitly (as above) or re-validate inside the internal function itself.

Successor projects (e.g., PoWH3D / the "Hourglass" contract, deployed later the same month) were built as hardened rewrites in direct response to this and similar clone-contract failures, though they carried their own separate set of design trade-offs and later issues unrelated to this specific underflow bug.

---

## References

- **Vulnerable contract (verified source):** [`0xa7ca36f7273d4d38fc2aec5a454c497f86728a7a`](https://etherscan.io/address/0xa7ca36f7273d4d38fc2aec5a454c497f86728a7a#code) — Etherscan
- **Underflow transaction:** [`0xb08fb4ec...ce029f`](https://etherscan.io/tx/0xb08fb4ec0b3c7ed15579fa65c84778296f858d48e51b86e140f5ce5350ce029f)
- **Drain / withdraw transaction:** [`0x496c0411...d395d62`](https://etherscan.io/tx/0x496c0411f52978dfd7953b7e6965465977162bfaf7b88c0c78fcdc97cd395d62)
- **GitHub — code walkthrough & vulnerable `sell()` source:** [MikeSpa/ethereum-exploit](https://github.com/MikeSpa/ethereum-exploit) → `ProofofWeakHandsCoin/`
- **GitHub — hands-on reproduction / hacking challenge:** [thec00n/Smart-Contract-Hacker-Playground](https://github.com/thec00n/Smart-Contract-Hacker-Playground) → `PoWH_Coin/`
- **Contemporary write-up:** Eric Banisadr, *"How $800k Evaporated from the PoWH Coin Ponzi Scheme Overnight"* — Medium, Feb 2018
- **Contemporary write-up:** *"Proof of Weak Hands (PoWH) Coin hacked, 866 eth stolen"* — Steemit, Feb 1, 2018