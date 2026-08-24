# Curve Finance Reentrancy Incident (July 2023)

**Root cause:** Vyper compiler bug (versions `0.2.15`, `0.2.16`, `0.3.0`)
**Date:** July 30, 2023
**Estimated loss:** ~$70M initial estimate (~$52M net after white-hat / MEV recoveries)

---

## 1. Introduction

Curve Finance is a decentralized exchange (DEX) on Ethereum purpose-built for
low-slippage, low-fee swaps between correlated assets — stablecoins, and
pegged pairs such as ETH/stETH or ETH/pETH — using a "StableSwap" bonding
curve invariant. Liquidity providers (LPs) deposit assets into pool contracts
and receive LP tokens representing a claim on the pool's reserves.

Curve's pool contracts are written in **Vyper**, a Python-like, security-
oriented smart contract language that serves as an alternative to Solidity
on the EVM. Vyper contracts repo: <https://github.com/curvefi/curve-contract>

On July 30, 2023, several Curve stable pools that use **native ETH transfers**
(pETH/ETH, alETH/ETH, msETH/ETH, CRV/ETH) were drained via reentrancy. Critically,
this was **not a bug in Curve's Vyper source code** — the contracts looked
correct and were audited. The flaw was a **zero-day defect in the Vyper
compiler itself**, which silently broke the `@nonreentrant` guard for any
contract compiled with the affected versions.

---

## 2. The Vulnerability and Its Cause

### 2.1 How Vyper's reentrancy guard is supposed to work

Vyper offers a `@nonreentrant(<key>)` function decorator. Two (or more)
functions that share the same `<key>` string are meant to share a **single
storage slot lock**:

- On entry, the compiler-generated code checks the lock is inactive, then
  sets it active.
- On exit, it resets the lock to inactive.
- If a locked function is re-entered — directly, or indirectly through
  another function sharing the same key — the call reverts.

This lets a pool protect `add_liquidity` and `remove_liquidity` (functions
that both touch pool reserves and LP supply) with one shared lock, e.g.
`@nonreentrant('lock')`.

### 2.2 What actually broke

During a multi-year refactor of the Vyper compiler's storage-slot allocator,
a fix (`v0.2.15`) meant to resolve an earlier storage-corruption bug
(introduced in `v0.2.13`/`v0.2.14`) inadvertently **removed the logic that
ensured only one storage slot was allocated per `<key>`**.

From `v0.2.15` through `v0.3.0`, the compiler instead allocated a **brand-new
storage slot for every function decorated with `@nonreentrant`, regardless
of the key string used**:

```python
# vulnerable allocation logic (v0.2.15 - v0.3.0), simplified
storage_slot = 0
for node in vyper_module.get_children(vy_ast.FunctionDef):
    type_ = node._metadata["type"]
    if type_.nonreentrant is not None:
        # BUG: key is never checked — a new slot is handed out every time
        type_.set_reentrancy_key_position(StorageSlot(storage_slot))
        storage_slot += 1
```

The practical consequence: `add_liquidity()` and `remove_liquidity()`, despite
both being tagged `@nonreentrant('lock')`, ended up with **two independent,
non-interacting lock slots**. Locking one function no longer blocked entry
into the other. Cross-function reentrancy protection was effectively dead —
even though every visible line of the Curve source code looked correct and
had been audited as such.

- **Affected compiler versions:** `0.2.15`, `0.2.16`, `0.3.0`
- **Introduced:** ~August–October 2021 (PR [#2391](https://github.com/vyperlang/vyper/pull/2391))
- **Silently fixed:** `v0.3.1` (December 2021), as an accidental side effect
  of an unrelated "storage optimization" fix — the security impact was not
  recognized at the time, so affected protocols were never notified
- **Publicly disclosed / exploited:** July 30, 2023
- **Advisory:** [GHSA-5824-cm3x-3c38](https://github.com/vyperlang/vyper/security/advisories/GHSA-5824-cm3x-3c38)
- **Fix PRs:** [#2439](https://github.com/vyperlang/vyper/pull/2439), [#2514](https://github.com/vyperlang/vyper/pull/2514)

### 2.3 Why it was exploitable specifically on ETH pools

A broken lock is only *profitable* to exploit if a function violates the
Checks-Effects-Interactions (CEI) pattern — i.e., it performs an external
call to an untrusted party *before* finalizing its own storage updates.

Curve's stablecoin-only pools (e.g. 3pool) move ERC-20 tokens via `transfer`,
which does not hand control back to the caller. But pools handling **native
ETH** must use a low-level, context-transferring `CALL` to send ETH — and
this happens *before* the pool's LP-token/reserve accounting is fully
settled. That external call is exactly the point where an attacker's
fallback function regains control while the pool's internal state is stale.

---

## 3. The Contract

**Example affected contract — pETH/ETH Curve pool (Factory pool used by JPEG'd):**

`https://etherscan.io/address/0x9848482da3ee3076165ce6497eda906e66bb85c5`

- Type: Curve Factory StableSwap pool, ETH-native pair (pETH/ETH)
- Language: Vyper
- Compiled with one of the vulnerable compiler versions (`0.2.15`)
- Repo family: Curve's Vyper pool contracts, e.g. `https://github.com/curvefi/curve-contract`

This pool (and its siblings — alETH/ETH, msETH/ETH, CRV/ETH, and Ellipsis'
BNB stable pools) shared the same structural pattern: a shared-key
`@nonreentrant` lock across `add_liquidity` / `remove_liquidity`, combined
with a raw ETH transfer inside the withdrawal path.

---

## 4. Description of the Vulnerable Functions

### `remove_liquidity()`
- Decorated with `@nonreentrant('lock')`.
- Burns the caller's LP tokens and sends back a proportional share of pool
  reserves.
- For ETH-native pools, sending the ETH portion requires a raw `CALL`,
  which transfers execution control to the recipient **before** the
  function has finished updating the pool's internal balances / LP
  total supply.
- Because the compiler bug gave this function its own private lock slot
  (instead of sharing one with `add_liquidity`), a reentrant call made
  from inside the receiving fallback was **not blocked**.

### `add_liquidity()`
- Also decorated with `@nonreentrant('lock')`, intended to share the same
  lock as `remove_liquidity()`.
- Mints LP tokens based on the pool's current (at-that-moment) balances.
- Because the two functions' locks didn't actually overlap, an attacker
  could re-enter `add_liquidity` (or call `remove_liquidity` again) mid-
  withdrawal, while the pool's reserve/supply bookkeeping still reflected
  **pre-withdrawal, stale values** — allowing LP tokens to be minted or
  redeemed against incorrect pool state.

### Net effect
By interleaving calls to these two functions across a reentrant fallback,
an attacker could manipulate the effective LP token price and redeem far
more of the pool's underlying assets than their genuine share, ultimately
draining the pool.

---

## 5. Attack Flow (pETH/ETH pool example)

1. **Flash loan** — Attacker borrows a large amount of WETH (~80,000 WETH
   from Balancer).
2. **Add liquidity** — Deposits WETH into the pETH/ETH pool via
   `add_liquidity()`, receiving LP tokens.
3. **Begin withdrawal** — Calls `remove_liquidity()`. The function starts
   transferring ETH back to the attacker's contract via a raw `CALL`,
   handing control to the attacker's fallback function **before** the
   pool's internal state is fully updated.
4. **Reenter** — Inside the fallback, the attacker re-enters the pool
   (calling `remove_liquidity` / `add_liquidity` again). Because the
   reentrancy lock is broken across these two functions, the call
   succeeds against **stale, pre-withdrawal balances**, letting the
   attacker extract disproportionate value.
5. **Repeat / drain** — This add/remove cycle is repeated, progressively
   distorting LP token pricing and draining the pool's real ETH and pETH
   reserves.
6. **Unwind** — The attacker converts extracted assets back to ETH/WETH on
   the open market, repays the flash loan, and keeps the profit
   (in this case, roughly 6,100 ETH, ~$11M, from the pETH/ETH pool alone).

The same broken-shared-lock pattern was independently exploited across
multiple ETH-native pools within hours of each other.

---

## 6. Impact

| Pool / Protocol | Approx. loss |
|---|---|
| JPEG'd — pETH/ETH | ~$11.5M |
| Alchemix — alETH/ETH | ~$13.6M (+ ~$9M in alETH) |
| Metronome — msETH/ETH | ~$1.6M (+ ~$1.8M in msETH) |
| Curve — CRV/ETH (drained twice) | ~$24.3M combined |
| Ellipsis (BNB Chain fork) — BNB stable pools | ~$78K |

- **Total initial estimate:** ~$70M across all affected protocols.
- **Net loss after recovery:** reduced to roughly **$52M**, as some
  attacks were executed or front-run by white-hat actors and MEV bots
  (notably `c0ffeebabe.eth`), who returned funds to the affected
  protocols in several cases.
- **Secondary effects:** Curve's governance token (CRV) dropped over 13%
  the same day; CRV was also collateral in large DeFi lending positions
  (e.g., on Aave), so the price shock raised concerns about cascading
  liquidations across the broader DeFi ecosystem.
- **Scope was narrow but systemic in nature:** only ETH-native pools
  compiled with the affected Vyper versions were vulnerable — Curve's
  large stablecoin pools (e.g., 3pool) were unaffected — but the bug
  cut across *multiple, unrelated protocols* simultaneously because it
  lived in the compiler, not any single project's code.

---

## 7. References

- Vyper official post-mortem: <https://hackmd.io/@vyperlang/HJUgNMhs2>
- Curve / LlamaRisk incident post-mortem: <https://hackmd.io/@LlamaRisk/BJzSKHNjn>
- Vyper security advisory (GHSA-5824-cm3x-3c38): <https://github.com/vyperlang/vyper/security/advisories/GHSA-5824-cm3x-3c38>
- Vulnerability-introducing PR: <https://github.com/vyperlang/vyper/pull/2391>
- Fix PRs: <https://github.com/vyperlang/vyper/pull/2439>, <https://github.com/vyperlang/vyper/pull/2514>
- Curve Vyper contracts repository: <https://github.com/curvefi/curve-contract>
- Rekt.news write-up: <https://rekt.news/curve-vyper-rekt>
- CertiK incident analysis: <https://www.certik.com/blog/vyper-incident-anaylsis>
- Halborn explainer: <https://www.halborn.com/blog/post/explained-the-vyper-bug-hack-july-2023>
- Chainalysis analysis: <https://www.chainalysis.com/blog/curve-finance-liquidity-pool-hack/>
- Affected contract (pETH/ETH pool): <https://etherscan.io/address/0x9848482da3ee3076165ce6497eda906e66bb85c5>

---

## 8. Lessons Learnt

1. **Auditing source code isn't enough — the compiler is part of your trust
   base.** Curve's Vyper source was correct and had been audited; the bug
   lived entirely in how the compiler translated that source to bytecode.
   Projects need to treat compiler correctness as part of their security
   surface, not an assumed given.

2. **Pin and actively track compiler versions.** Contracts compiled with
   `0.2.15`–`0.3.0` carried a silent, undocumented vulnerability for over
   18 months. Teams should monitor compiler changelogs/advisories for
   *all* versions they've ever deployed with — not just the latest.

3. **Shared-key reentrancy guards need explicit testing.** The bug was
   only caught, post-incident, once a dedicated cross-function
   reentrancy test was added in the `v0.3.1` fix. Language and framework
   maintainers should test the *interaction* between decorated functions
   sharing a lock key, not just isolated single-function reentrancy.

4. **CEI (Checks-Effects-Interactions) is not optional even with a lock.**
   The exploitability hinged on ETH transfers happening before state was
   finalized. Even when a reentrancy guard is present, following CEI
   strictly provides defense-in-depth if the guard itself ever fails.

5. **Immutable contracts inherit compiler risk indefinitely.** Because
   deployed bytecode can't be patched, a compiler bug fixed upstream does
   nothing for contracts already live on-chain with the vulnerable
   version. This motivated Vyper's post-incident push for dedicated
   audits and bug bounties covering *past* releases still securing TVL,
   not just the current one.

6. **Community/whitehat response can materially reduce damage.** Rapid
   coordination among white-hat hackers and MEV searchers who front-ran
   or intercepted exploit transactions cut total realized losses from an
   estimated $70M down to roughly $52M — underscoring the value of an
   active, fast-responding security community around major protocols.

7. **Monoculture / shared-dependency risk in DeFi.** Because many
   unrelated protocols (Curve, JPEG'd, Alchemix, Metronome, Ellipsis)
   independently used the same vulnerable Vyper versions, a single
   compiler defect became a multi-protocol, cross-chain incident within
   hours — a reminder that shared tooling/dependencies can create
   correlated risk across an otherwise diverse ecosystem.