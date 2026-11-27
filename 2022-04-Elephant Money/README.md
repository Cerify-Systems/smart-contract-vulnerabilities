# Elephant Money — Flash Loan & Price Manipulation Exploit

## Overview

| | |
|---|---|
| **Protocol** | Elephant Money (ELEPHANT / TRUNK ecosystem) |
| **Chain** | BNB Smart Chain (BSC) |
| **Date** | April 12, 2022 |
| **Vulnerability class** | Flash loan–enabled price/oracle manipulation, combined with an unvalidated privileged withdrawal function |
| **Estimated loss** | ~$11.2M reported officially by the team (BNB/BUSD drained); total losses including stolen ELEPHANT supply estimated up to ~$22.2M by third-party trackers |
| **Auditors involved post-incident** | CertiK, InsurAce, PeckShield |

Elephant Money was a BSC-based "decentralized bank" built around two tokens:

- **ELEPHANT** — a reflection/rebasing token, the base asset of the ecosystem.
- **TRUNK** — a stablecoin partially collateralized by BUSD (75%) and ELEPHANT (25%), mintable and redeemable against the protocol's treasuries.

The protocol's mint/redeem logic depended on the **live, on-chain spot price of ELEPHANT** on PancakeSwap to value collateral. That price was trivially manipulable within a single transaction using a flash loan, and the treasury contract responsible for releasing funds had no independent way to sanity-check the amounts it was asked to pay out.

---

## The Contract & Faulty Function

**Contract:** `Treasury` (BUSD Treasury)
**Address:** `0xCb5a02BB3a38e92E591d323d6824586608cE8cE4` (BNB Smart Chain)
**Status at time of exploit:** Unverified / unaudited (confirmed by CertiK post-incident)

```solidity
pragma solidity ^0.6.8;

contract Treasury is Whitelist {

    IToken public token; // address of the BEP20 token traded on this contract

    constructor(address token_addr) public Ownable() {
        token = IToken(token_addr);
    }

    function withdraw(uint256 _amount) public onlyWhitelisted {
        require(token.transfer(_msgSender(), _amount));
    }
}
```

### Why this function was the target

`withdraw()` has exactly **one** protection: `onlyWhitelisted`. Beyond that access-control check, there is:

- No cap on `_amount`
- No collateralization or solvency check
- No comparison against an independent or time-weighted price
- No rate limiting or per-block/per-transaction ceiling

The function fully **outsources correctness to its caller**. It assumes that any whitelisted contract calling it has already computed a legitimate, collateral-backed amount. That assumption was safe only as long as the caller's own math couldn't be manipulated — and it could be.

The whitelisted caller was the Reserve / mint-redeem executor logic, which determined how much BUSD/ELEPHANT to mint, redeem, or release **based on ELEPHANT's live spot price on a PancakeSwap pool** — a price that exists entirely within the same block and can be moved arbitrarily by anyone with enough temporary capital.

---

## Attack Flow

1. **Flash loan taken:** the attacker borrowed 131,162 WBNB and 91,035,000 BUSD in a single, uncollateralized flash loan.
2. **Initial swap:** the WBNB was swapped for roughly 34,244 ELEPHANT tokens on PancakeSwap, this large buy already pushing ELEPHANT's spot price upward.
3. **Mint TRUNK:** the attacker minted TRUNK by depositing BUSD. Internally, the mint path itself converted BUSD → WBNB → ELEPHANT to maintain the protocol's backing ratios — this additional buy pressure inflated ELEPHANT's price further, *within the same transaction the attacker controlled*.
4. **Price now artificially high:** because the Reserve valued the attacker's holdings using this manipulated, in-block spot price, the attacker's ELEPHANT and freshly minted TRUNK were now worth far more than the capital initially put in.
5. **Cash out:** the attacker swapped their ELEPHANT for a larger amount of WBNB than they started with, and separately redeemed the minted TRUNK for both WBNB and BUSD.
6. **Treasury pays out blindly:** the Reserve called `Treasury.withdraw()` with the inflated amount. Since `withdraw()` performed no independent validation, it paid out without question.
7. **Repay & repeat:** the flash loan was repaid within the same transaction, netting the attacker roughly **$4 million profit per cycle**. The attacker repeated this cycle multiple times.
8. **Result:** ELEPHANT's price was crashed toward zero, the TRUNK peg broke, and the BUSD/ELEPHANT treasuries were drained.

### Why this vulnerability happened

- **Single-block price oracle:** the protocol relied on a live DEX spot price (an AMM pool reserve ratio) as its source of truth for ELEPHANT's value, instead of a manipulation-resistant price feed such as a TWAP (time-weighted average price) or an external oracle like Chainlink.
- **Composable, same-transaction attack surface:** flash loans let an attacker borrow enormous, temporary capital with zero collateral, execute the manipulation, extract the profit, and repay the loan — all atomically, with no risk if the trade reverted.
- **No independent validation at the money-movement layer:** even if the price computation upstream was flawed, `Treasury.withdraw()` was the last line of defense before funds actually left the protocol, and it did not check the plausibility of the amount it was asked to release. Access control (`onlyWhitelisted`) was mistaken for a sufficient safeguard, when in fact it only shifted trust to the caller's logic rather than eliminating risk.
- **Unverified/unaudited treasury contract:** CertiK stated post-incident that the flaw was specifically in the treasury contract, which had never been verified or audited — despite the project advertising audits from CertiK and Solidity Finance elsewhere on its site.

---

## Impact & Losses

- Elephant Money's official statement reported **$11.2 million** lost.
- Independent trackers estimate total losses closer to **$22.2 million** once ~30 billion stolen ELEPHANT tokens are valued in (roughly $10M of ELEPHANT on top of the ~$11M in BNB/BUSD cashed out).
- ELEPHANT's price collapsed toward zero.
- TRUNK depegged significantly (reported drop of ~27% from its BUSD peg on PancakeSwap).
- The protocol paused the Reserve, disabling Stampede and all TRUNK minting/redemption while investigating.
- The team engaged CertiK, InsurAce, and later PeckShield, and reported completing a debrief with the U.S. Department of Justice regarding the incident.

---

## The Fix

Elephant Money's post-incident redesign (documented in their "Reserve Exploit: Live Updates" and later releases) introduced several concrete mitigations:

1. **Moved away from spot-price oracles toward TWAP-based pricing.**
   Later contracts (e.g., the Futures product) integrate a `IPcsPeriodicTwapOracle` to price ELEPHANT via a time-weighted average rather than a single in-block spot price, which is far more resistant to flash-loan-driven manipulation:
   ```solidity
   uint[] memory amounts = oracle.consultAmountsOut(collateralAmount, path);
   ```

2. **Added a price-floor invariant enforced on every state-changing call.**
   Newer token contracts (e.g., Trumpet) enforce that internal price can never decrease within a transaction:
   ```solidity
   function _requirePriceRises(uint256 oldPrice) internal {
       uint256 newPrice = _calculatePrice();
       require(newPrice >= oldPrice, 'Price Cannot Fall');
       emit PriceChange(oldPrice, newPrice, _totalSupply);
   }
   ```
   This directly blocks the "buy-manipulate-then-drain" pattern used in the original attack, since any transaction that would leave the price lower than it started simply reverts.

3. **Simplified the Reserve so it no longer directly manages liquidity or buy/sell logic.**
   Treasuries became simpler, more isolated one-sided liquidity pools accessed only by whitelisted executor contracts, reducing the blast radius of any single compromised or miscalculating caller.

4. **Introduced a block-delayed claim mechanism.**
   A "sister claim function" was added to deliver minted tokens outside of the block in which they were requested, breaking the atomicity that flash-loan attacks depend on — an attacker can no longer manipulate, mint, and redeem all within a single transaction.

5. **Withdrawal-size gating on treasuries.**
   Later versions cap direct treasury withdrawals (e.g., limited to under 1% of treasury balance per withdrawal); anything larger triggers a minting path instead of a direct drain, reducing the amount any single manipulated call can extract.

6. **Additional external audits.**
   PeckShield was brought on to audit the rebuilt `ElephantReserve` and `Stampede` contracts going forward, addressing the earlier gap where the exploited Treasury had never been verified or audited at all.

---

## GitHub / Source References

Elephant Money did not maintain a public GitHub repository for its core contracts; source was published directly via BscScan's "Submitted for verification" contract pages rather than a version-controlled repo. As a result:

- The **exploited Treasury contract** (`0xCb5a02BB3a38e92E591d323d6824586608cE8cE4`) was **unverified on BscScan at the time of the attack** and has no known public GitHub mirror.
- Later, hardened contracts *are* verified on BscScan and can be referenced directly:
  - `Trumpet` — `0x574a691D05EeE825299024b2dE584B208647e073` (verified 2023-03-04)
  - `Futures` — `0x5B24f7645eec47EDd997bF8faDF3E340518af11B` (verified 2023-02-16)
  - `TRUNK` token — `0xdd325C38b12903B727D16961e61333f4871A70E0`
  - `ELEPHANT` token — `0xE283D0e3B8c102BAdF5E8166B73E02D96d92F688`

No official GitHub organization/repository for Elephant Money's smart contracts was located; all source references above come from BscScan's verified-source pages.

---

## External References

- Elephant Money — "Reserve Exploit: Live Updates" (official Medium post-mortem): https://medium.com/elephant-money/reserve-exploit-52fd36ccc7e8
- PeckShield Audit Report — ElephantReserve & Stampede (post-incident rebuild): https://elephant.money/media/PeckShield-Audit-Report-ElephantReserve-v1.0rc.pdf
- The Record (Recorded Future News) — "Hackers steal more than $11 million from Elephant Money DeFi platform": https://therecord.media/hackers-steal-more-than-11-million-from-elephant-money-defi-platform
- web3isgoinggreat.com incident log: https://www.web3isgoinggreat.com/?id=2022-04-12-1
- ImmuneBytes — "Top 10 Flash Loan Attacks": https://immunebytes.com/blog/top-10-flash-loan-attacks/
- BlockSec (@BlockSecTeam) — original Twitter thread analyzing the exploit transaction (April 12, 2022)

---

## Lessons Learned

1. **Never price critical financial logic off a single in-block DEX spot price.** Spot reserves in an AMM pool can be moved arbitrarily within one transaction by anyone with enough temporary (flash-loaned) capital. Use TWAPs, external oracles (e.g., Chainlink), or multi-block confirmation windows for anything that gates minting, collateral valuation, or withdrawals.
2. **Access control is not the same as amount validation.** `onlyWhitelisted` correctly restricts *who* can call a sensitive function, but says nothing about *whether the amount requested makes sense*. Privileged functions that move funds should independently sanity-check amounts against known bounds (treasury balance percentage, historical averages, hard caps) rather than trusting the caller's computation implicitly.
3. **Every contract that can move funds needs to be verified and audited — including "simple" ones.** The Treasury contract was minimal, which likely contributed to it being deprioritized for verification/audit. Simplicity is not a substitute for scrutiny; small contracts sitting at the end of a fund-movement chain are exactly where unchecked trust becomes exploitable.
4. **Break transaction atomicity for high-value, price-sensitive actions.** Introducing a block delay between requesting and receiving minted/redeemed funds (as Elephant Money later did) directly defeats flash-loan attacks, since the attacker can no longer manipulate price, mint/redeem, and repay the loan within a single atomic transaction.
5. **Composability cuts both ways.** Flash loans, DEX pools, and whitelisted internal contracts are powerful building blocks, but every external call and price read they enable is also a potential manipulation vector. Systems built by composing multiple contracts need to treat each cross-contract call as untrusted unless proven otherwise, even when the caller is "whitelisted."