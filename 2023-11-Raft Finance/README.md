# Raft Finance — Rounding / Precision-Loss Exploit (November 2023)

## Overview

| | |
|---|---|
| **Protocol** | [Raft Finance](https://raft.fi) — a decentralized, over-collateralized stablecoin lending protocol built on Ethereum, issuing the **R** stablecoin against liquid-staking-token collateral (stETH, wstETH, cbETH). |
| **Vulnerability class** | Rounding / precision-loss error in debt-share (index) accounting |
| **Date of exploit** | November 10, 2023 (~18:59:23 UTC) |
| **Public disclosure** | November 10, 2023, 19:18 UTC (initial alert); full post-mortem published November 13, 2023 |
| **Funds minted (unbacked R)** | ~6,705,028 R (~$6.7M) |
| **Funds actually extracted by attacker** | ~$3.3M–$3.6M (net attacker profit ended up **negative**, ~‑4 ETH, due to a self-inflicted error — see Impact) |
| **Root cause** | Rounding-up in share-minting math combined with attacker-manipulated collateral index |

---

## Description of the Vulnerability

Raft's collateral/debt accounting is built on **index-based rebasing tokens**. Instead of tracking a user's raw token balance directly, the protocol tracks a *share* balance and multiplies it by a global `currentIndex` to compute the user's real balance:

```
balanceOf(user) = shares(user) × currentIndex / INDEX_PRECISION
```

This index-share design is common in lending protocols (similar to Compound's `cToken` exchange rate or Aave's aToken index) because it lets balances "rebase" automatically as interest accrues or collateral value changes, without needing to update every user's balance individually.

The flaw: when a very small amount of collateral was deposited/minted against an **inflated index**, the conversion from "collateral amount" to "shares" would mathematically round down to **zero shares** under correct behavior — but the contract's minting logic **rounded up instead of down (truncating)**, so the depositor received **1 share** instead of 0.

Normally this is a harmless off-by-one-wei rounding quirk. It becomes dangerous once an attacker can control the index value itself. By artificially inflating the index (see Attack Flow below), each "1 share" was worth a hugely inflated amount of underlying collateral value — letting the attacker mint real economic value (and therefore borrow real R stablecoin) from almost nothing, repeated many times.

---

## Why This Happened — Root Cause Analysis

1. **Design choice: round up instead of down in share minting.** Share/debt-token math in lending protocols must be rounding-direction-aware — rounding should always favor the protocol (i.e., round *down* / in the protocol's favor) on mint, and round the *opposite* way on burn/redeem, to prevent value creation from dust amounts. Raft's `ERC20Indexable` minting path rounded in the user's favor instead.
2. **The index was externally manipulable.** The `setIndex()` function on the indexable collateral token could be influenced by the attacker through a sequence of donate → liquidate operations against the `InterestRatePositionManager`, letting them push the index to an artificial, inflated value.
3. **No lower bound / sanity check on mint size vs. share output.** The contract did not reject or guard against mints that should have produced zero shares — a value that "should never economically matter" was allowed to be repeatedly harvested.
4. **Audits missed it.** Raft's contracts had been audited by Trail of Bits and via a Hats Finance public audit competition, but neither caught this specific interaction between index manipulation and rounding direction — illustrating that precision-loss bugs are notoriously difficult to catch via standard manual/automated review and require dedicated fuzzing/invariant testing.

---

## Attack Flow (Step by Step)

1. **Setup — inflate the index.**
   The attacker donated 1,061 cbETH directly to the `InterestRatePositionManager` (IRPM) contract, then liquidated a pre-created position. This manipulated the internal accounting so that the collateral token's index (`storedIndex`, used by the indexable rcbETH-c share token) became artificially amplified.

2. **Flash loan for scale.**
   The attacker took a flash loan of 6,000 cbETH from Aave, transferred 6,001 cbETH into the IRPM contract, and liquidated another pre-created position — further compounding the index manipulation.

3. **Redeem cheaply.**
   The attacker redeemed 6,003 cbETH while paying only 90 wei worth of rcbETH-c shares — a sign the index was now heavily distorted in their favor.

4. **Exploit the rounding bug repeatedly.**
   Using `managePosition()` on the position manager, the attacker deposited tiny amounts of collateral one unit at a time. Each time, under correct math the mint should have produced **0 shares** (the amount was too small relative to the inflated index) — but the rounding-up behavior in the share-minting function instead minted **1 share per call**. Because the index was inflated, each of these "1 share" mints was worth a large amount of value.

5. **Borrow against the inflated collateral.**
   With an artificially large collateral-share balance built up from repeated 1-share mints, the attacker called `managePosition()` again to borrow/mint ~6.7 million **R** stablecoin against this phantom collateral.

6. **Cash out.**
   The R tokens were swapped through Balancer (R/sDAI, R/DAI pools) and Uniswap (R/USDC), converting the unbacked R into other stable assets, which were further converted toward ETH — draining real liquidity from the protocol's trading pools and causing R to depeg.

7. **Self-inflicted loss.**
   In a final twist, a coding/handling error by the attacker caused **1,570 of the 1,577 ETH** they had extracted to be sent irreversibly to a burn address (`0x000...dEaD`-style address), leaving them with only ~7 ETH. After accounting for gas and flash-loan costs, the attacker's own net result was approximately **‑4 ETH** (a loss), even though the protocol lost millions.

---

## Contracts & Functions Involved

**Repository:** [`raft-fi/contracts`](https://github.com/raft-fi/contracts)

| Contract | Role in the exploit | GitHub link |
|---|---|---|
| **`ERC20Indexable`** | The rebase/indexable share token implementation. Deployed as the collateral share token instance **rcbETH-c**. Contains the `mint()` function whose share-conversion math rounded **up**, and `setIndex()`, which set the manipulable index. This is the contract where the actual precision bug lived. | [`contracts/ERC20Indexable.sol`](https://github.com/raft-fi/contracts/blob/master/contracts/ERC20Indexable.sol) |
| **`PositionManager`** | The main entry point for opening/adjusting positions, borrowing, liquidating. Its `managePosition()` function was called repeatedly by the attacker to trigger the flawed mint path. | [`contracts/PositionManager.sol`](https://github.com/raft-fi/contracts/blob/master/contracts/PositionManager.sol) |
| **`RToken`** | The R stablecoin itself, mintable/burnable only by `PositionManager`. This is what got minted in an unbacked/undercollateralized way as the end result of the exploit. | [`contracts/RToken.sol`](https://github.com/raft-fi/contracts/blob/master/contracts/RToken.sol) |
| **`InterestRatePositionManager` (IRPM)** | The specific on-chain deployed instance of the position manager used for cbETH collateral, which the attacker directly targeted with donate → liquidate manipulation to inflate the index. | On-chain: [`0x9ab6b21cdf116f611110b048987e58894786c244`](https://etherscan.io/address/0x9ab6b21cdf116f611110b048987e58894786c244) |

**Key on-chain references:**
- Exploit transaction: [`0xfeedbf51b4e2338e38171f6e19501327294ab1907ab44cfd2d7e7336c975ace7`](https://etherscan.io/tx/0xfeedbf51b4e2338e38171f6e19501327294ab1907ab44cfd2d7e7336c975ace7)
- Index-manipulation setup transaction: [`0xa1378a4d61e81339daaf2c7c8bb669be42002919f10379c616d0aee34047794`](https://etherscan.io/tx/0xa1378a4d61e81339daaf2c7c8bb669be42002919f10379c616d0aee34047794)
- Attacker address: [`0xc1f2b71a502b551a65eee9c96318afdd5fd439fa`](https://etherscan.io/address/0xc1f2b71a502b551a65eee9c96318afdd5fd439fa)

---

## Loss Incurred & Impact

- **Unbacked R minted:** ~6,705,028 R (~$6.7 million in artificially created stablecoin supply).
- **ETH extracted from AMM pools:** ~1,577 ETH (~$3.3M–$3.6M), drained from R/sDAI and R/DAI Balancer pools and the R/USDC Uniswap pool as the attacker dumped minted R.
- **Attacker's actual take-home:** Due to a self-inflicted error sending 1,570 of 1,577 ETH to a burn address, the attacker was left with only ~7 ETH, and after gas/flash-loan costs their **net result was a loss of ~4 ETH** — an unusual outcome where the exploiter lost money despite a successful attack on the protocol.
- **Protocol-level impact:**
  - The **R stablecoin depegged** significantly (dropping as low as ~$0.0036–$0.0041 at points) as the attacker dumped millions of unbacked R into thin liquidity.
  - Raft's Total Value Locked (TVL) collapsed — from a peak of ~$64M months earlier to roughly **$1.48M** shortly after the incident (compounded by ongoing TVL decline, not solely the hack).
  - All Raft smart contracts were **paused/suspended** following the incident.
  - Raft's governance token (RAFT) price dropped roughly **60%** in the aftermath.
  - Raft filed a police report and worked with centralized exchanges to trace stolen funds, and proposed a recovery/compensation plan for affected users using protocol-owned sDAI reserves in its Peg Stability Module.
  - Reputational damage: this was one of several 2023 DeFi rounding-error exploits (alongside Onyx Protocol, Hundred Finance, Midas Capital), reinforcing scrutiny on precision-loss handling industry-wide.

---

## The Fix / Remediation

Following the incident, Raft's response and subsequent remediation centered on:

1. **Immediate mitigation:** All Raft smart contracts were paused to stop further exploitation; users retained the ability to repay debt and retrieve collateral while contracts were suspended.
2. **Root-cause fix — correct rounding direction:** The core fix was to change the share-minting/index-conversion math so that it always **rounds in the protocol's favor** (i.e., rounds down / truncates on mint operations that produce shares, and rounds the opposite direction on burns), eliminating the ability to mint non-zero shares from below-threshold collateral amounts. This aligns with the general best-practice pattern of "round against the user" in all share/debt token conversions.
3. **Guarding the index-setting logic:** Hardening around what operations (donations, liquidations) are able to influence `setIndex()`/`storedIndex`, and validating index updates against expected bounds, to prevent an attacker from artificially inflating the index through donate-then-liquidate sequences.
4. **Recovery plan for affected users:** Raft proposed using protocol-owned sDAI held in its Peg Stability Module to compensate users impacted by the R depeg, with community feedback incorporated before execution.
5. **Expanded testing:** Increased emphasis on invariant/fuzz testing (property-based testing) specifically targeting precision-loss and rounding-direction properties across all share-conversion functions, since these vulnerabilities are easy for standard audits and unit tests to miss.
6. **Known issues tracking:** The repository maintains a [`KNOWN_ISSUES.md`](https://github.com/raft-fi/contracts/blob/master/KNOWN_ISSUES.md) file documenting known limitations/accepted risks — a practice adopted industry-wide after incidents like this to make precision/edge-case assumptions explicit rather than implicit.

---

## References

- [Raft Protocol Exploit — Nov 10, 2023 — Detailed Analysis (ImmuneBytes)](https://immunebytes.com/blog/raft-protocol-exploit-nov-10-2023-detailed-analysis/)
- [DeFi protocols continue to get hacked due to same basic maths problem (DL News)](https://www.dlnews.com/articles/defi/hackers-continue-to-profit-from-defi-developers-math-problem/)
- [$1.3 Million dollar Raft Protocol Precision Loss Exploit explained (Coinmonks / Medium)](https://medium.com/coinmonks/1-3-million-dollar-raft-protocol-precision-loss-exploit-explained-7f4fd2c4d907)
- [Security Audits Miss Vulnerabilities As Raft Hacked For $6.7M (Bitget News)](https://www.bitget.com/news/detail/12560603838228)
- [When Hacking Goes Haywire: Raft's 1570 ETH Loss (MetaTrust Labs)](https://metatrust.io/blogs/post/when-hacking-goes-haywire-rafts-1570-eth-loss-takes-a-cosmic-detour-to-the-black-hole)
- [Raft Hack (2023) — $3.3M Lost (Smart Contract Hacking)](https://smartcontractshacking.com/hacks/raft-hack-2023)
- [SharkTeam: Analysis of the Principles of Raft Attack Incident (Medium)](https://medium.com/@sharkteam/sharkteam-analysis-of-the-principles-of-raft-attack-incident-814127d626bd)
- [Raft Finance floats user bailout plan after odd exploit (Blockworks)](https://blockworks.com/news/exploit-ether-defi-protocol)
- [Latest DeFi exploits show audits are no guarantee (Blockworks)](https://blockworks.co/news/audits-cannot-guarantee-defi-exploits)
- [Rounding Error — Blockchain Security Glossary (Zealynx)](https://www.zealynx.io/glossary/rounding-error)
- [`raft-fi/contracts` GitHub repository](https://github.com/raft-fi/contracts)
- Exploit transaction on Etherscan: [`0xfeedbf51...c975ace7`](https://etherscan.io/tx/0xfeedbf51b4e2338e38171f6e19501327294ab1907ab44cfd2d7e7336c975ace7)

---

## Lessons Learnt

1. **Rounding direction is a security property, not just a UX detail.** Every division/multiplication in share, debt, or exchange-rate math must be deliberately rounded *against* the user (in the protocol's favor) for mint/borrow operations, and the opposite way for burn/repay/redeem operations. Getting this backwards — even by "just 1 wei" per call — is exploitable at scale via repetition.
2. **Index/exchange-rate values that can be influenced by user actions (donations, liquidations, direct transfers) are a high-risk surface.** Any function that lets an external actor nudge a global accounting variable (like `setIndex`) needs strict validation, bounding, and ideally should not be influenced by simple token donations to the contract.
3. **"Dust" amounts deserve dedicated fuzzing.** Precision-loss bugs live at the extremes — deposits/mints of size 1 wei to a few hundred wei. Standard test suites built around "realistic" transaction sizes routinely miss these. Property-based/invariant fuzz testing (e.g., Foundry invariant tests, Echidna, Medusa) targeting "no free value creation" invariants is essential.
4. **Audits are not a guarantee.** Raft's contracts were reviewed by reputable auditors (Trail of Bits) and a public audit competition (Hats Finance), yet this bug was missed. Security is a continuous process — post-audit monitoring, bug bounties, and invariant testing in production are necessary complements, not replacements, for audits.
5. **Repeated small transactions that look "economically irrational" should raise alarms.** The attack pattern (looping tiny deposits to accumulate shares) is a recognizable signature; real-time monitoring/alerting on high-frequency, sub-economic transaction patterns against sensitive contracts can help catch this class of exploit before large capital is at risk.
6. **Even attackers make mistakes.** The exploiter's own error — burning ~1,570 of their stolen ETH — is a reminder that exploits are executed under real-world operational pressure, and complex multi-step attack scripts are themselves bug-prone. It does not reduce the protocol's responsibility to fix the underlying flaw, but is a notable footnote in this incident's story.
7. **This is part of a broader pattern.** Raft was one of several 2023–2025 DeFi protocols hit by nearly identical precision-loss/rounding exploits (Onyx Protocol, Hundred Finance, Midas Capital, and later the much larger Balancer V2 rounding exploit in November 2025), underscoring that this vulnerability class is systemic across Compound-fork and share-based lending architectures, and warrants a "cultural change" in how DeFi teams treat fixed-point arithmetic.