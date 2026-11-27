# Yam Finance — Rebase Arithmetic Bug (Governance-Breaking Incident)

## Overview

| | |
|---|---|
| **Protocol** | Yam Finance |
| **Type** | Smart contract arithmetic bug (elastic-supply / rebase logic) |
| **Category** | Accounting bug → Governance failure |
| **Date** | August 12–13, 2020 (bug found ~6 PM UTC Aug 12, protocol effectively bricked ~4 AM EDT Aug 13, roughly 24 hours after launch) |
| **Root Cause** | Missing `div(BASE)` normalization in the `rebase()` function's `totalSupply` calculation |
| **Funds at Risk** | Staking/farming deposits were **not** at risk |
| **Actual Damage** | On-chain governance permanently broken; ~$750K+ of value effectively trapped/lost; token price collapsed >90% |
| **Audit Status** | Unaudited at launch (explicitly disclosed by the team) |

Yam Finance launched on August 11, 2020 as an experimental, community-driven yield farming protocol combining an Ampleforth-style elastic supply token with Synthetix/Compound-style farming and on-chain governance. It attracted hundreds of millions of dollars in locked value within 24 hours — before any external audit had been completed.

---

## Background: How Yam's Rebase Was Supposed to Work

YAM used an **elastic supply token**, similar in design to Ampleforth:

- The token targets a price of **$1**.
- Periodically (twice daily), a `rebase()` call checks the time-weighted average price (TWAP) from Uniswap.
- If YAM is trading **above** $1 → supply **expands** (positive rebase), diluting price back toward target. A portion of newly minted supply is routed to a **governance-controlled treasury/reserve**.
- If YAM is trading **below** $1 → supply **contracts** (negative rebase), increasing scarcity to push price back up.
- Supply changes are represented internally via a `yamsScalingFactor`, so that user balances (`balanceOf`) are computed as:

```solidity
balanceOf(who) = _yamBalances[who] * yamsScalingFactor / internalDecimals
```

This scaling-factor pattern requires **every** place that derives `totalSupply` from `initSupply` and `yamsScalingFactor` to divide back down by the fixed-point base (`BASE`, i.e. `10^18`) to keep units consistent.

---

## The Vulnerable Contract

**File:** `contracts/token/YAM.sol`
**GitHub reference (exact commit):**
`https://github.com/yam-finance/yam-protocol/blob/767e3a4a6918b6fb6100ad6bb356164408f5d82f/contracts/token/YAM.sol#L340`

**Known on-chain addresses (Ethereum mainnet):**

| Contract | Address |
|---|---|
| YAM Token | `0x0AaCfbeC6a24756c20D41914F2caba817C0d8521` |
| YAM Rebaser (original) | `0x1FB361f274F316d383B94D761832AB68099A7B00` |
| YAM Rebaser (patched, later) | `0x649714BC2fFfCb1e65c689b49a10216D4960833D` |

### The faulty function

```solidity
function rebase(
    uint256 epoch,
    uint256 indexDelta,
    bool positive
)
    external
    onlyRebaser
    returns (uint256)
{
    if (indexDelta == 0) {
      emit Rebase(epoch, yamsScalingFactor, yamsScalingFactor);
      return totalSupply;
    }

    uint256 prevYamsScalingFactor = yamsScalingFactor;

    if (!positive) {
       yamsScalingFactor = yamsScalingFactor.mul(BASE.sub(indexDelta)).div(BASE);
    } else {
        uint256 newScalingFactor = yamsScalingFactor.mul(BASE.add(indexDelta)).div(BASE);
        if (newScalingFactor < _maxScalingFactor()) {
            yamsScalingFactor = newScalingFactor;
        } else {
          yamsScalingFactor = _maxScalingFactor();
        }
    }

    // BUG: missing .div(BASE)
    totalSupply = initSupply.mul(yamsScalingFactor);

    emit Rebase(epoch, prevYamsScalingFactor, yamsScalingFactor);
    return totalSupply;
}
```

### The fix (what it should have been)

```solidity
totalSupply = initSupply.mul(yamsScalingFactor).div(BASE);
```

The line `totalSupply = initSupply.mul(yamsScalingFactor);` mistakenly omitted the `.div(BASE)` step that every other supply/balance calculation in the same file correctly applies (see `balanceOf`, `_mint`, `transfer`, `transferFrom`, all of which properly divide by `internalDecimals`/scaling terms). Since `yamsScalingFactor` is a fixed-point number scaled by `BASE = 10^18`, multiplying without dividing back down inflated `totalSupply` by roughly `10^18` relative to the intended value on any rebase **after** the first one (the first rebase happened to be masked because `yamsScalingFactor` was initialized equal to `BASE`).

---

## Attack Flow — Why This Happened

This was **not an external exploit**; no attacker crafted a malicious transaction. It was a **latent logic bug** triggered by the protocol's own normal, permissioned operation (`rebase()`, callable only by the `Rebaser` contract). The sequence of events:

1. **Aug 11, 2020 – Launch.** Yam Finance launches without an external audit. The team is transparent that the code reuses known, audited primitives (Ampleforth's rebase mechanics, Compound's governance module) but that the *composition* of these pieces into Yam had not itself been audited.

2. **Aug 11–12 – Explosive growth.** Total value locked approaches ~$400–500M within a day, driven by yield-farming incentives (YAM emitted to LP stakers of assets like COMP, LEND, LINK, MKR, SNX, WETH, YFI).

3. **Aug 12, ~6 PM UTC – Bug discovered.** A community member/developer identifies that the `rebase()` function's `totalSupply` calculation is missing the `.div(BASE)` step. On any *subsequent* positive or negative rebase (not the very first one), this would cause `totalSupply` to be computed at a wildly incorrect (hugely inflated) value.

4. **Cascading effect on governance.** Because a percentage of every positive rebase's newly "minted" supply is programmed to flow into the community governance reserve, the corrupted math meant the reserve would receive an astronomically oversized share of tokens relative to the circulating supply held by voters. This shifted the ratio of `quorum threshold : delegatable voting power` so far out of reach that **no proposal could ever realistically reach quorum again** — permanently disabling on-chain governance and locking treasury funds (~$750K of the Uniswap YAM/yCRV pool assets, later reported around $500K in yCRV specifically) with no mechanism left to move them.

5. **Emergency community response.** The team proposed a governance fix — `YAM Improvement Proposal` — that would patch the rebase logic and required **~160,000 YAM delegated** (later reports cite figures up to 175,000) to reach quorum **before the next scheduled rebase** (4 AM EDT / 8 AM UTC, Aug 13), since another rebase would compound the broken math further and could permanently strand governance before any fix could pass.

6. **Race against the clock.** The community mobilized rapidly, delegating enough YAM to hit quorum, and the proposal was submitted in time.

7. **Fix fails anyway.** Despite reaching quorum, the submitted proposal **failed to execute correctly on-chain**, and the next rebase occurred before any working patch could be applied. At that point, Yam Finance's governance was confirmed to be **permanently and irrecoverably broken**.

8. **Price collapse.** YAM price fell **more than 90%** within minutes of the news breaking, and liquidity was pulled from the YAM/yCRV Uniswap pool (reports indicate roughly 75% of the pool was withdrawn).

### Root cause classification

- **Type:** Arithmetic/unit-scaling omission (missing division step in fixed-point math).
- **Trigger:** Normal, intended protocol operation (`rebase()`), not adversarial input.
- **Why it wasn't caught pre-launch:** No independent smart contract audit was performed before deployment; the team launched intentionally fast as an "experiment," explicitly warning users of this risk.
- **Why it wasn't caught immediately after deployment:** The very first rebase happened to compute correctly by coincidence, because `yamsScalingFactor` was initialized equal to `BASE`, so `initSupply.mul(yamsScalingFactor)` and `initSupply.mul(yamsScalingFactor).div(BASE)` produced the same result on that one occasion — masking the defect until the second rebase.

---

## Impact

| Impact area | Detail |
|---|---|
| **User funds in staking/farming pools** | Not directly at risk — this was isolated to the rebase/supply logic, not the staking contracts. |
| **Governance treasury / reserve** | Effectively rendered inaccessible; reported at roughly **$750,000** in value (including ~$500,000 in yCRV), locked with no working governance path to retrieve or redeploy it. |
| **Token price** | Collapsed **>90%** within minutes once the unrecoverable nature of the bug was confirmed. |
| **Protocol governance** | Permanently disabled — no further on-chain proposals could reach quorum given the corrupted supply/reserve ratio. |
| **Liquidity** | A large share of the YAM/yCRV Uniswap pool was withdrawn as confidence collapsed. |
| **Reputational** | Widely cited as a cautionary tale about "unaudited DeFi experiments" during the 2020 DeFi/"yield farming summer" boom; co-founder Brock Elmore publicly apologized on Twitter. |

---

## Remediation

Because the bug lived in **immutable-by-design governance logic** (the whole point of the protocol was decentralized on-chain control), there was no admin key or emergency pause that could simply patch `YAM.sol` in place. The团队's options were constrained to:

1. **Attempted in-protocol fix** — a governance proposal to halt/patch the rebase mechanism and burn the excess reserve tokens. This required reaching quorum via emergency community delegation, which was achieved, but the proposal **did not execute successfully** before the next rebase occurred, so the live contract was never actually repaired.
2. **Post-mortem architectural fix** — the corrected calculation was documented and fixed in the codebase going forward:
   ```solidity
   totalSupply = initSupply.mul(yamsScalingFactor).div(BASE);
   ```
3. **Migration to a new deployment** — since the original YAM token/governance could not be salvaged on-chain, the team announced plans for **YAM v2**, a re-launch with:
   - A full, community-funded third-party smart contract audit before deployment.
   - A migration contract allowing YAM v1 holders to migrate balances to the new, audited token.
   - Rebasing temporarily disabled/reworked in later iterations to reduce this entire class of risk.

---

## References

- CertiK — *Yam Finance Smart Contract Bug Analysis & Future Prevention*
  https://www.certik.com/resources/blog/yam-finance-smart-contract-bug-analysis-future-prevention
- SlowMist — *Analysis of YAM attack*
  https://slowmist.medium.com/analysis-of-yam-attack-b4f7c0139692
- CoinDesk — *DeFi Meme Coin YAM Succumbs to Fatal 'Rebase' Bug, Makes Plans for 'YAM 2.0'*
  https://www.coindesk.com/markets/2020/08/13/defi-meme-coin-yam-succumbs-to-fatal-rebase-bug-makes-plans-for-yam-20
- Decrypt — *Overnight DeFi success Yam Finance alerts users to 'bug'*
  https://decrypt.co/38510/overnight-defi-success-yam-finance-alerts-users-bug
- CryptoPotato — *YAM Developers Reveal Bug in Rebase Contract*
  https://cryptopotato.com/yam-developers-reveal-bug-in-rebase-contract/
- The Cryptonomist — *YAM Finance has lost control of governance*
  https://en.cryptonomist.ch/2020/08/13/yam-finance-lost-control-governance/
- Finematics — *Meteoric Rise and Fall of YAM*
  https://finematics.com/yam-explained/
- Source code — `yam-finance/yam-protocol` on GitHub
  https://github.com/yam-finance/yam-protocol/blob/767e3a4a6918b6fb6100ad6bb356164408f5d82f/contracts/token/YAM.sol
- Etherscan — YAM Token contract
  https://etherscan.io/address/0x0aacfbec6a24756c20d41914f2caba817c0d8521
- Etherscan — YAM Rebaser contract
  https://etherscan.io/address/0x1fb361f274f316d383b94d761832ab68099a7b00

---

## Lessons Learned

1. **Audit before deployment, especially for financial primitives that combine multiple mechanisms.** Yam reused audited building blocks (Ampleforth-style rebase, Compound-style governance) individually, but the *composed* system had never been audited as a whole — and composition is exactly where subtle unit/scaling bugs like this hide.

2. **Fixed-point arithmetic is a common and dangerous failure class.** Any time a scaling factor (`BASE`, `1e18`, etc.) is introduced, *every* downstream calculation that touches the scaled variable must consistently apply the same normalization. A single missed `.div(BASE)` was enough to break the entire protocol.

3. **Test all execution paths, not just the "happy path" or first invocation.** The bug was masked on the very first rebase (because `yamsScalingFactor` started equal to `BASE`), which likely made pre-launch manual testing look fine. Bugs that only manifest on the *second* or later invocation of a state-changing function are easy to miss without thorough unit/property-based testing (e.g., fuzzing across multiple rebase epochs).

4. **Governance-critical logic needs an emergency circuit breaker.** Because Yam's governance was fully on-chain and immutable from day one, there was no admin pause/upgrade path once the bug was live — the community had to race a hard deadline (the next scheduled rebase) with no fallback. Protocols should weigh the trade-off between "maximally decentralized from block one" and "no safety valve if something goes wrong early on."

5. **Quorum mechanics are fragile to supply-side manipulation (even accidental).** Because voting power and quorum thresholds are denominated in the same token whose supply the bug corrupted, the exploit (unintentional as it was) simultaneously broke both the "problem" and the "mechanism meant to fix the problem." Governance systems should consider decoupling voting power from a rapidly mutable/rebasing supply, or use snapshot-based accounting resistant to supply shocks.

6. **Transparency and rapid community mobilization can limit — but not always prevent — damage.** The team's immediate public disclosure and the community's fast delegation response showed the value of open communication during an incident, even though the technical fix ultimately failed to execute in time.

7. **"Move fast" DeFi launches carry real, quantifiable risk.** Yam's own team explicitly framed the project as an unaudited experiment, and users engaged anyway due to high yield incentives. This incident became one of the canonical case studies cited afterward for why unaudited, hastily launched DeFi protocols pose outsized risk regardless of how much value they attract in the short term.