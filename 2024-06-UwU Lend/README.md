# UwU Lend Exploit

## Overview

| | |
|---|---|
| **Protocol** | UwU Lend (non-custodial liquidity market, fork of Aave V2) |
| **Date of primary attack** | June 10, 2024 |
| **Date of follow-up attack** | June 13, 2024 |
| **Vulnerability class** | Price oracle manipulation (flash-loan-assisted) |
| **Total loss** | ~$19.3M–$23M (first attack) + ~$3.7M (second attack) ≈ **$23–24M combined** |
| **Chain** | Ethereum Mainnet |
| **Attacker address** | `0x841dDf093f5188989fA1524e7B893de64B421f4` |
| **Attacker exploit contract** | `0x21C58d8F816578b1193AEf4683E8c64405A4312E` |

---

## Description

UwU Lend is a decentralized, non-custodial lending protocol built as a fork of **Aave V2**. Users can deposit assets as collateral, borrow against that collateral, and liquidate undercollateralized positions. UwU Lend customized Aave's fallback oracle logic to price a market for **sUSDe** (Ethena's staked USDe).

To price sUSDe, UwU Lend deployed a custom oracle contract, **`sUSDePriceProviderBUniCatch`**, which computed a price by:

1. Pulling **11 separate price sources** for USDe:
   - **1 Uniswap V3** USDe/USDT TWAP
   - **5 Curve Finance pools**, each contributing **two** values: the pool's instantaneous spot price (`get_p()`) and its exponential moving average (`get_price()`)
2. Sorting all 11 values and taking the **median** as the "true" price.

The design intent was that using 11 independent feeds and a median (rather than a mean) would make the price resistant to manipulation — an attacker would need to move roughly half the feeds to shift the median materially.

**The flaw:** 5 of the 11 inputs came directly from Curve's `get_p()` function, which returns the **raw, instantaneous spot price** of the pool — a value with **no time-weighting or smoothing**. Curve Finance's own team has publicly stated that `get_p()`/raw spot prices are not intended to be used as standalone price oracles, precisely because they can be moved within a single transaction by a large enough trade. Despite this well-known guidance, UwU Lend's oracle used these spot values directly as inputs to the median calculation.

In principle, moving the median of 11 close values requires manipulating at least 6 of them. However, one of the "safe" EMA-based inputs — the USDe/USDC Curve pool EMA — was already sitting ~5.5% away from where it should have been at the time of the attack (its cause is unconfirmed; possibly pre-positioned by the attacker in earlier blocks). This meant the attacker only needed to manipulate the 5 vulnerable spot-price feeds to flip the median in their favor — reducing the cost/complexity of the attack.

Additionally, PeckShield's prior audit of UwU Lend's contracts explicitly **excluded the oracle** from its scope, on the assumption that UwU Lend was using a trusted, well-designed price oracle. That assumption did not hold.

---

## Attack Flow

The attack was executed across **3 transactions in ~6 minutes**, using **9 flash loans** and **4 helper/exploit contracts**, funded initially via Tornado Cash (a sanctioned mixer).

1. **Flash loan acquisition** — The attacker borrowed roughly **$3.796 billion** in assets across Aave V3, Aave V2, Uniswap V3, Balancer, Maker, Spark, and Morpho — reportedly one of the largest flash-loan amounts ever used in a DeFi exploit.

2. **Suppress sUSDe price** — A portion of the borrowed USDe was swapped through Curve pools to push down the spot price (`get_p()`) on the 5 vulnerable Curve feeds. This pulled the oracle's computed median sUSDe price down (observed drop: ~4%, from ~$0.988 to enable a favorable borrow rate near $0.99).

3. **Open leveraged position at manipulated price** — With sUSDe now artificially cheap, the attacker deposited other collateral and borrowed a very large amount of sUSDe against it, and/or built a large recursive/leveraged sUSDe debt position while the price was suppressed.

4. **Reverse the manipulation** — The attacker executed reverse trades in the same Curve pools, rapidly pushing the sUSDe price back up (observed rise: to ~$1.03).

5. **Trigger and self-liquidate** — The sudden price swing flipped the attacker's own leveraged position into apparent insolvency under the (now-inflated) price. The attacker repeatedly triggered `liquidationCall`-type operations against their own position, extracting large amounts of collateral (notably **uWETH**) at favorable terms.

6. **Unwind and exit** — The attacker reversed remaining manipulated positions, repaid all flash loans within the same transactions, converted stolen assets, and exited.

A **second attack**, three days later (June 13, 2024), used the same flash-loan/oracle-manipulation pattern against remaining exposure UwU Lend had not yet fully remediated, draining an additional ~$3.7M. Security firms (Beosin, Blocksec) attributed both attacks to the same actor.

---

## Why This Vulnerability Happened

- **Reliance on unsmoothed spot prices**: Using Curve's `get_p()` (instantaneous spot price) as an oracle input — a practice Curve explicitly advises against — allowed single-transaction, flash-loan-funded trades to move the price.
- **False sense of security from "median of many sources"**: A median across 11 feeds looks robust, but if roughly half the feeds are cheap to manipulate and the "safe" feeds aren't verified to be accurate in real time, the median can still be pushed by manipulating only the weak feeds — especially if one of the trusted feeds happens to already be off.
- **Low liquidity in underlying pools relative to attack capital**: Flash loans let the attacker temporarily command far more capital ($3.79B) than the real liquidity in the relevant Curve pools (reported around $173M), making price impact from massive swaps trivial to achieve.
- **No price smoothing / time-weighting on the vulnerable feeds**: No TWAP, no per-block price update limits, and no deviation/circuit-breaker checks on the 5 spot-price inputs.
- **Audit scope gap**: The oracle was excluded from PeckShield's audit scope, so this component of the system never received independent scrutiny despite being the most sensitive piece (asset pricing) in a lending protocol.
- **Custom fallback oracle logic on top of an Aave V2 fork**: The base Aave V2 code is well-audited and battle-tested, but UwU Lend modified the fallback oracle behavior specifically to support the sUSDe market — introducing a new, less-vetted trust boundary into an otherwise proven codebase.

---

## Smart Contract & Function Reference

| Item | Reference |
|---|---|
| **Vulnerable oracle contract** | `sUSDePriceProviderBUniCatch` |
| **Etherscan (verified source)** | https://etherscan.io/address/0xd252953818bdf8507643c237877020398fa4b2e8#code |
| **Faulty function(s)** | Price aggregation logic — `getAssetPrice()` → falls back to `_fallbackOracle` → `_getPrices()`, which calls Curve's `get_p()` (raw spot price) for 5 of the 11 price sources feeding the median calculation |
| **Underlying lending pool logic** | Aave V2 fork (`LendingPool` contract) |
| **UwU Lend GitHub org** | https://github.com/UwU-Lend |
| **UwU Lend contracts repo** | https://github.com/UwU-Lend/uwu-contracts |
| **Attacker EOA** | https://etherscan.io/address/0x841dDf093f5188989fA1524e7B893de64B421f4 |
| **Attacker exploit contract** | `0x21C58d8F816578b1193AEf4683E8c64405A4312E` |


---

## Loss and Impact

**First attack (June 10, 2024): ~$19.3M–$23M** (figures vary slightly across security firms' tracking)

Reported stolen assets included:

| Asset | Approx. Amount | Approx. Value |
|---|---|---|
| WETH | 481.36 | ~$1.70M |
| WBTC | 17.63 | ~$1.19M |
| bLUSD | 499,254 | ~$0.59M |
| crvUSD | 233,819 | ~$0.23M |
| sDAI | 1,394,055 | ~$1.52M |
| CRV | 25,354,902 | ~$9.38M |
| DAI | 3,522,428 | ~$3.52M |
| USDT | 4,224,277 | ~$4.22M |
| sUSDe | 486,455 | ~$0.53M |

Most stolen funds were converted to ETH shortly after the attack. Some stolen assets were also deposited into Curve-based **LlamaLend** markets, where the attacker borrowed over 8 million crvUSD against the deposited CRV.

**Second attack (June 13, 2024): ~$3.7M**, drained from remaining exposure via a repeat of the same flash-loan/oracle-manipulation pattern, despite UwU Lend having announced (a day after the first attack) that it had identified and resolved "the" vulnerability.

**Broader impact:**
- UwU Lend paused the protocol immediately following detection.
- The team publicly acknowledged the exploit via X (Twitter) and offered a $5M bounty for information on the attacker.
- Ironically, UwU Lend's TVL reportedly rose ~135% in the 24 hours after the first attack, likely from opportunistic/speculative activity rather than confidence in the protocol.
- The incident became a widely cited case study in DeFi security circles on the risks of (a) using AMM spot prices as oracle inputs and (b) narrow audit scoping that excludes "trusted" components like oracles.
- Curve Finance founder Michael Egorov publicly commented that Curve explicitly advises against using their pools as standalone price oracles, and that Curve would have flagged the issue if consulted during UwU Lend's oracle design.

---

## The Fix

Following the first attack (June 10), UwU Lend stated it had **identified and patched the vulnerability**, describing it as unique to the sUSDe market oracle, and resumed operations. However, this remediation was **incomplete** — the attacker exploited a related weakness three days later (June 13) for an additional ~$3.7M, indicating the initial fix did not fully close the underlying oracle design flaw.

Recommendations from the security community for a durable fix (consistent with standard DeFi oracle-security practice) included:

- **Stop using raw/instantaneous spot prices (`get_p()`) as oracle inputs.** Use Curve's own time-weighted/EMA price functions (`price_oracle()` / `get_price()` equivalents), which update at most once per block and dampen sudden price swings — Curve explicitly supports and recommends these over spot price for oracle use.
- **Exclude or down-weight low-liquidity feeds** from the median/aggregate calculation, since these are the cheapest to manipulate with flash-loan capital.
- **Introduce deviation checks / circuit breakers** that reject or flag price updates that move beyond a sane threshold within a single block or transaction.
- **Bring the oracle into audit scope.** Any component that determines collateral/borrow valuation is security-critical and should never be assumed "trusted" without independent review — a lesson directly drawn from PeckShield's audit excluding the oracle.
- **Consult with underlying protocol teams** (e.g., Curve) when building custom oracles on top of their infrastructure, since they understand the manipulation surface of their own pools better than an integrating protocol will.

---

## Lessons Learned

1. **Spot prices are not oracles.** AMM instantaneous prices (like Curve's `get_p()`) reflect the state of a pool at a single block and are trivially manipulable with flash-loan capital. Always use time-weighted or otherwise smoothed price feeds for anything security-critical.
2. **"Median of many sources" is not automatically manipulation-resistant.** If a meaningful fraction of the sources share the same underlying manipulable primitive (in this case, Curve spot prices), an attacker doesn't need to move a true majority of *independent* sources — just enough correlated ones, especially if a "trusted" feed happens to already be off.
3. **Audit scope must cover the full attack surface — especially oracles.** Excluding a price oracle from audit scope because it's assumed to be "a trusted, timely price feed" is a dangerous assumption in DeFi, where the oracle is often the single highest-value target in the entire system.
4. **Flash loans amplify existing design flaws; they are rarely the root cause themselves.** The ~$3.79B flash loan didn't create the vulnerability — it simply made an existing, cheap-to-manipulate price feed exploitable at massive scale in a single atomic transaction.
5. **A quick patch is not the same as a complete fix.** UwU Lend's post-incident announcement that it had "resolved" the vulnerability was followed by a second successful attack days later, underscoring the need for thorough root-cause analysis (and possibly a full pause/independent review) before resuming operations after an oracle-related exploit.
6. **Consult the protocols you build on top of.** Curve Finance's own team indicated they would have flagged the misuse of `get_p()` had they been consulted — engaging directly with the teams behind integrated infrastructure can surface known pitfalls before they become exploits.

---

## References

- QuillAudits — [Decoding UwU Lend's $19.4 Million Exploit](https://quillaudits.medium.com/decoding-uwu-lends-19-4-million-exploit-quillaudits-15a9c158166a)
- QuillAudits — [UwU Lend Hack Analysis (blog)](https://www.quillaudits.com/blog/hack-analysis/uwu-lend-hack)
- SlowMist — [Analysis of the UwU Lend Hack](https://slowmist.medium.com/analysis-of-the-uwu-lend-hack-9502b2c06dbe)
- Neptune Mutual — [Understanding the UwU Lend Exploit](https://medium.com/neptune-mutual/understanding-the-uwu-lend-exploit-b32ea552f030)
- CUBE3.AI — [Days in Advance, CUBE3.AI Detected Sophisticated $18M UwU Lend Attack](https://blog.cube3.ai/2024/06/11/cube3-ai-detected-uwu-lend-attack-days-in-advance/)
- Cyvers.ai — [UwU Lend $23M Exploit: Oracle Vulnerabilities Exposed](https://cyvers.ai/blog/uwu-lend-23m-exploit-oracle-vulnerabilities-exposed)
- The Block — [UwU Lend drained for $3.7 million in second exploit this week](https://www.theblock.co/post/299901/uwu-lend-second-hack-this-week)
- CryptoSlate — [Hacker drains $19.5 million from UwU Lend in price oracle exploit](https://cryptoslate.com/hacker-drains-19-5-million-from-uwu-lend-in-price-oracle-exploit/)
- 512M — [UwU Lend Exploit Analysis](https://512m.io/blog/uwu-lend-suffers-exploit-detailed-analysis)
- EXVUL — [UwU Lend attack incident analysis](https://medium.com/@exvul/uwu-lend-attack-incident-analysisattack-brief-3db51082ec5c)
- Coinlive — [UwU Lend Hack Analysis](https://www.coinlive.com/news/uwu-lend-hack-analysis)
- cmichel (X/Twitter) — [Technical thread on the oracle design flaw](https://x.com/cmichelio/status/1800463263433678945)
- Etherscan — [`sUSDePriceProviderBUniCatch` verified source](https://etherscan.io/address/0xd252953818bdf8507643c237877020398fa4b2e8#code)
- GitHub — [UwU-Lend/uwu-contracts](https://github.com/UwU-Lend/uwu-contracts)