# Balancer — Deflationary / Fee-on-Transfer Token Accounting Exploit

## Summary

| | |
|---|---|
| **Protocol** | Balancer (V1) |
| **Vulnerability type** | ERC20 token accounting flaw — incompatibility with deflationary/fee-on-transfer tokens |
| **Date** | June 28, 2020, ~18:03 UTC |
| **Loss** | ~$500,000 USD (reported between $500K–$523K) |
| **Root cause** | Pool contract trusted internally recorded balances instead of verifying actual tokens received after transfer |
| **Affected pools** | Two Balancer pools containing **STA (Statera)** and **STONK**, both fee-on-transfer tokens |
| **Contract** | [`BPool.sol`](https://github.com/balancer/balancer-core/blob/master/contracts/BPool.sol) |
| **Key functions involved** | `swapExactAmountIn()`, `_pullUnderlying()`, `gulp()` |

---

## Background

Balancer launched on Ethereum mainnet in March 2020 as a generalized automated market maker (AMM), allowing pools with multiple tokens and custom weightings. Roughly three months later, the protocol suffered its first major security incident when an attacker exploited how `BPool` handled **deflationary tokens** — tokens that burn or deduct a fee on every transfer, meaning the recipient receives less than the amount sent.

Balancer's accounting logic was written assuming standard ERC20 semantics: if a function *requests* a transfer of `X` tokens, it assumes the pool's balance increases by exactly `X`. This assumption does not hold for fee-on-transfer tokens like **STA**, which burned 1% of every transfer.

---

## Why the Vulnerability Happened

The core issue was a **mismatch between Balancer's internal bookkeeping and the token's actual on-chain balance**:

1. Balancer pools track token balances internally in a `_records` mapping (`_records[token].balance`), used to price swaps via the constant-mean-style formula.
2. When a swap was executed, `BPool` updated `_records[tokenIn].balance` by the **requested input amount**, then called `_pullUnderlying()` to perform the actual `transferFrom`.
3. For a standard ERC20, the amount received equals the amount sent — so the internal record and actual balance stay in sync.
4. For **STA**, a 1% fee was deducted on every transfer. The pool's internal record kept increasing by the full requested amount, while the pool's *actual* STA balance grew by only 99% of that — creating a growing discrepancy between recorded and real balances.
5. Balancer also exposed a `gulp()` function, intended to let a pool "absorb" tokens sent to it outside the normal accounting flow (e.g., airdropped rewards) by resyncing `_records[token]` to the token's real balance. This function — designed as a fix mechanism — became the tool the attacker used to **lock in** the corrupted, extremely low internal balance for STA rather than correct it.
6. Because Balancer's pricing formula treats the scarcest recorded asset as the most valuable, artificially forcing STA's recorded balance down to ~1 wei made the pool willing to give up huge amounts of its other assets (WETH, WBTC, LINK, etc.) in exchange for negligible amounts of STA.

In short: **the contract never validated that the tokens it believed it received matched the tokens it actually received**, and a legitimate reconciliation function (`gulp()`) could be abused mid-attack to weaponize that gap instead of closing it.

---

## Attack Flow

1. **Flash loan** — The attacker borrowed 104,331 WETH from dYdX via a flash loan (no upfront capital required).
2. **Repeated swaps to deplete STA** — Using the borrowed WETH, the attacker called `swapExactAmountIn()` on the STA/WETH pool ~24 times in succession. Each swap:
   - Credited the pool's internal STA record by the full requested transfer amount.
   - Actually received 1% less STA due to the token's built-in transfer fee, via `_pullUnderlying()`.
   - Widened the gap between `_records[STA].balance` (inflated) and the pool's real STA token balance (depleted).
3. **Balance reset via `gulp()`** — The attacker called `gulp(STA)`, which resynced the pool's internal STA record to match the real, near-zero on-chain balance — pinning `_records[STA].balance` at effectively **1e-18 STA (1 wei)**.
4. **Extraction** — With STA recorded as almost nonexistent in the pool, the AMM pricing formula treated it as extremely scarce/valuable. The attacker sent in a tiny amount of STA via `swapExactAmountIn()` and received a hugely disproportionate amount of the pool's other assets (WETH and other bound tokens) in return.
5. **Repayment** — The attacker repaid the dYdX flash loan and kept the extracted profit.
6. The same technique was repeated against the **STONK** pool.

---

## Real-World Contract & Function References

- **Repository:** [`balancer/balancer-core`](https://github.com/balancer/balancer-core) (originally `balancer-labs/balancer-core`)
- **Contract file:** [`contracts/BPool.sol`](https://github.com/balancer/balancer-core/blob/master/contracts/BPool.sol)

### Functions implicated

| Function | Role in the exploit |
|---|---|
| `swapExactAmountIn()` | Updates internal `_records[tokenIn].balance` by the requested amount and initiates the pull of tokens, without verifying the balance delta actually received |
| `_pullUnderlying()` | Executes the actual `transferFrom` call to pull tokens into the pool — silently loses value for fee-on-transfer tokens, with no check that the received amount matches the recorded amount |
| `gulp()` | Legitimate function meant to resync a token's internal record to its real balance (e.g., for absorbing airdrops); exploited here to lock in the artificially depleted STA balance instead of correcting the root cause |

---

## Loss & Impact

- **Direct loss:** Approximately **$500,000** (~$523,616 per PeckShield's on-chain analysis) drained from the two affected pools.
- **Tokens affected:** Only pools containing fee-on-transfer/deflationary tokens (STA, STONK) were vulnerable — pools with standard ERC20 tokens were unaffected.
- **Reputational impact:** As one of DeFi's earliest and most prominent AMMs, the incident raised broader industry awareness of the risks of non-standard ERC20 tokens (deflationary, fee-on-transfer, rebasing, ERC777-style) interacting with AMM/lending protocols that assume standard transfer semantics.
- **Community reaction:** Balancer initially did not commit to reimbursement, drawing criticism and the threat of community/legal action; the team reversed course and reimbursed affected liquidity providers.
- **Broader pattern:** This was the first of several security incidents Balancer experienced in subsequent years (e.g., 2023 Euler Finance contagion loss, 2023 V2 pool precision issue, 2023 DNS hijacking, and a much larger unrelated ~$117M access-control exploit in November 2025), contributing to ongoing scrutiny of the protocol's security track record.

---

## The Fix

In response to the incident, Balancer took the following remediation steps:

1. **UI-level blacklisting** — Balancer began excluding known fee-on-transfer / deflationary tokens from the official front-end interface, similar to an existing blacklist for tokens with non-standard (non-boolean-returning) `transfer`/`approve` functions. This prevented users from unknowingly creating or joining pools with incompatible tokens through the official UI.
2. **Exclusion from incentives** — Tokens like STA were confirmed as intentionally excluded from BAL liquidity-mining reward whitelists, since their non-standard transfer behavior was already a known risk.
3. **Documentation and risk disclosure** — Balancer committed to publishing clearer documentation warning users and pool creators about the risks of binding deflationary, rebasing, or otherwise "broken"/non-standard ERC20 tokens to a pool.
4. **Continued audits** — Balancer noted it had already undergone two audits prior to the incident and had a third planned, reaffirming an ongoing audit commitment.
5. **Architectural change in later versions** — Balancer's subsequent architecture (V2 and later) centralized token accounting and transfers through a single **Vault** contract with internal balance tracking, reducing (though not fully eliminating) the surface area for this specific class of accounting mismatch, since pools no longer independently custody and self-account for tokens the way V1 `BPool`s did.

> **Important caveat:** Balancer's protocol remains permissionless — anyone can create a pool with any ERC20 token, including ones with non-standard transfer behavior. The 2020 fix was primarily a mitigation (blacklisting known bad tokens, warning users) rather than a complete protocol-level guarantee that *all* future deflationary or fee-on-transfer tokens are handled safely. Balancer's official guidance continues to recommend caution when pairing pools with non-standard ERC20 tokens.

---

## References

- Balancer Protocol (official): [Incident with non-standard ERC20 deflationary tokens](https://medium.com/balancer-protocol/incident-with-non-standard-erc20-deflationary-tokens-95a0f6d46dea) — Jun 29, 2020
- PeckShield: [Balancer Hacks: Root Cause and Loss Analysis](https://blog.peckshield.com/2020/06/28/balancer/) — Jun 28, 2020
- PeckShield (Medium mirror): [Balancer Hacks: Root Cause and Loss Analysis](https://peckshield.medium.com/balancer-hacks-root-cause-and-loss-analysis-4916f7f0fff5)
- QuadrigaInitiative Case Study: [Jun 2020 – Balancer Deflation Hack – $523k](https://www.quadrigainitiative.com/casestudy/balancerdeflationhack.php)
- Consensys Diligence: [Balancer Finance Audit](https://consensys.net/diligence/audits/2020/05/balancer-finance/)
- GitHub Repository: [balancer/balancer-core](https://github.com/balancer/balancer-core)
- Contract Source: [`BPool.sol`](https://github.com/balancer/balancer-core/blob/master/contracts/BPool.sol)

