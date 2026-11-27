# xToken (xSNXa / xBNTa) — Oracle Manipulation Incident

## Overview

| | |
|---|---|
| **Protocol** | xToken (xSNXa, xBNTa) |
| **Date** | May 12, 2021, 9:44 AM EST |
| **Vulnerability Type** | Oracle / Spot-Price Manipulation via Flash Loan |
| **Root Cause** | Mint pricing relied on a manipulable on-chain spot price sourced during the same transaction as the mint call |
| **Loss** | ~$24.5–25 million (combined xSNXa + xBNTa) |
| **Attack Vector** | Flash loan (61,800 ETH, ~$270M borrowed) used to move DEX price, then mint against the manipulated price |

Manipulated market prices caused incorrect valuation of the assets backing xSNXa/xBNTa, which in turn caused the protocol to mint (the minting equivalent of "over-borrow" in this design) far more tokens than the deposited collateral was actually worth.

---

## Background

xToken issued **xAssets** — ERC-20 wrapper tokens that gave holders passive exposure to yield/staking strategies on top of underlying DeFi tokens (e.g., xSNXa wrapped SNX staking, xBNTa wrapped BNT). Users could mint these tokens by depositing ETH or the underlying asset directly. Minting calculated the Net Asset Value (NAV) of the fund and issued tokens proportional to the value contributed, using live on-chain prices.

---

## The Vulnerable Function

`xSNXCore.sol` — `mint()`

```solidity
function mint(uint256 minRate) external payable whenNotPaused {
    require(msg.value > 0, "Must send ETH");

    uint256 fee = _administerFee(msg.value, feeDivisors.mintFee);
    uint256 ethContribution = msg.value.sub(fee);
    uint256 snxBalanceBefore = tradeAccounting.getSnxBalance();

    uint256 totalSupply = totalSupply();
    (bool allocateToEth, uint256 nonSnxAssetValue) = tradeAccounting
        .getMintWithEthUtils(ethContribution, totalSupply);

    if (!allocateToEth) {
        tradeAccounting.swapEtherToToken.value(ethContribution)(
            snxAddress,
            minRate
        );
    }

    uint256 mintAmount = tradeAccounting.calculateTokensToMintWithEth(
        snxBalanceBefore,
        ethContribution,
        nonSnxAssetValue,
        totalSupply
    );

    emit Mint(msg.sender, block.timestamp, msg.value, mintAmount, true);
    return super._mint(msg.sender, mintAmount);
}
```

### Why this function was exploitable

1. **`minRate` was caller-controlled slippage protection.**
   `swapEtherToToken(snxAddress, minRate)` swaps the contributed ETH into SNX on Kyber/Uniswap at whatever price the pool currently reflects. An attacker calling their own transaction could simply pass a negligible `minRate`, meaning "accept any price, no matter how bad" — removing the one guardrail meant to catch a bad price.

2. **The swap and the valuation happened in the same atomic transaction.**
   `snxBalanceBefore` is captured *before* the swap, but `calculateTokensToMintWithEth()` (in `TradeAccounting.sol`) prices the mint using the *post-swap* on-chain SNX spot price (via `getWeiPerOneSnxOnMint()` → `getSynthPrice()`), which the attacker had just moved in the same transaction using a flash loan. There was no time-weighted average price (TWAP), no external price feed cross-check, and no cooldown between price observation and mint execution.

3. **No sanity bound on minted amount vs. deposited value.**
   Nothing compared the resulting `mintAmount` against an independent reference price to catch an economically implausible mint.

The `xBNTa` contract compounded the exploit in the same transaction: it was supposed to only allow minting when the deposited token was actually BNT, but it failed to validate this, letting the attacker mint xBNTa using a different token entirely.

---

## Attack Flow

```
1. Attacker takes a flash loan of 61,800 ETH (~$270M) from a lending pool.
2. Attacker uses part of the borrowed ETH to trade on Kyber/Uniswap,
   pushing the on-chain SNX price down (or otherwise skewing it favorably).
3. Attacker calls xSNXCore.mint(minRate) with a near-zero minRate:
     a. swapEtherToToken() executes at the now-manipulated (crashed) price.
     b. calculateTokensToMintWithEth() computes mintAmount using that
        same manipulated price/balance state within the same tx.
     c. super._mint() issues a disproportionately large amount of xSNXa
        to the attacker relative to the real value of ETH contributed.
4. In parallel, the attacker exploits the missing token-check in xBNTa
   to mint large amounts of xBNTa without depositing real BNT.
5. Attacker immediately sells the newly minted xSNXa on the Balancer
   pool and xBNTa on the Bancor pool for real assets (ETH, SNX, BNT).
6. Attacker repays the flash loan within the same transaction, keeping
   the arbitrage profit — ~2,400 ETH, 781,000 BNT, 407,000 SNX,
   and 1.9B xBNTa extracted in total.
7. Entire attack — borrow, manipulate, mint, drain, repay — executed
   atomically in a single transaction block.
```

This is the canonical **mint → inflate price → drain liquidity pool** oracle manipulation pattern: deposit/mint against a manipulated valuation, then cash out before the price reverts.

---

## Smart Contracts

| Contract | Address (Ethereum Mainnet) |
|---|---|
| xSNXa (proxy/token) | `0x2367012ab9c3da91290f71590d5ce217721eefe4` |
| xSNXCore (implementation, pre-exploit) | `0x2934443c1749dcc0cdcabbd77098eea31d2ea6c3` |

Verified source is viewable on Etherscan under the above addresses (Contract → Code tab).

### GitHub References
- xToken organization: https://github.com/xtokenmarket
- xSNX contracts repository (audited PRs referencing `xSNXCore.sol`, `TradeAccounting.sol`, `Proxy.sol`): `xtokenmarket/xsnx`
- xToken ABIs package: https://github.com/xtokenmarket/abis
- xToken JS SDK: https://github.com/xtokenmarket/js

---

## Loss & Impact

- **Total value lost:** ~$24.5–25 million across the xBNTa (Bancor) and xSNXa (Balancer) liquidity pools.
- **Direct loss on xSNXa contract:** 416 ETH (~7–8% of the fund's NAV at the time); the remaining 90%+ of value stayed in the xSNX contract and was later recoverable to holders.
- **Direct loss on xBNTa contract:** effectively total, via 1.9 billion xBNTa minted and drained; no BNT was actually lost from the xBNTa contract itself, but the paired liquidity pool was drained.
- **Assets extracted:** ~2,400 ETH ($10.3M), ~781,000 BNT ($6.2M), ~407,000 SNX ($8M), plus 1.9B xBNTa tokens.
- **Operational impact:** All minting across every xToken product was paused within ~30 minutes of detection (10:14 AM EST) as a precaution while the team assessed whether other xAssets shared the same weakness.
- **Reputational/follow-on impact:** xToken suffered a **second exploit on August 29, 2021** (~$4.5M, via an access-control flaw in `callFunction`, not the same oracle issue), after which the team retired the xSNX product line entirely, citing its complexity and large attack surface.
- **Compensation:** xToken snapshotted holder balances and funded a recovery/compensation program (rXTK token) using its native XTK treasury to make affected holders whole over time.

---

## The Fix

- **Minting was disabled immediately** across all xToken products as an emergency circuit breaker while the root cause was investigated.
- Going forward, xToken stated it had **already built a security feature for an upcoming product** that would have prevented this style of attack, and committed to rolling it out across the whole product suite. The general direction of the fix (in line with community/industry recommendations for this exact bug class) was:
  - Moving away from single-block, same-transaction spot prices toward **time-weighted average prices (TWAPs)** or external oracle feeds (e.g., Chainlink) that cannot be moved within a single atomic transaction.
  - Adding **deviation checks** comparing the price at deposit/mint time to a trusted reference price, rejecting mints where the two diverge beyond a safe tolerance.
  - Reassessing reliance on `minRate`-style caller-supplied slippage parameters as a security boundary, since a malicious caller controls that input.
  - Ultimately, xToken judged the xSNX product's dependency graph (Synthetix + Set Protocol + Curve + Kyber) too complex to fully harden and **sunset the xSNX product** after the second, unrelated exploit in August 2021.

---

## Lessons Learned

1. **Never price a mint/redeem/borrow action off a spot price that can move within the same transaction as the action itself.** Flash loans make any single-block, single-source price fully attacker-controlled.
2. **Caller-supplied slippage parameters (like `minRate`) are not a security control** — an attacker calling their own transaction will always choose the value that benefits them most.
3. **Use TWAPs or external oracles (e.g., Chainlink) instead of raw DEX spot prices** for any valuation that gates minting, borrowing, or collateral accounting.
4. **Add price-deviation guards**: compare price-at-action to a trusted recent reference and revert if the divergence exceeds a safe threshold, especially for high-value operations like minting.
5. **Treat multi-token/multi-pool systems as a combined attack surface.** The xBNTa and xSNXa contracts were exploited *together in a single transaction* — securing each contract in isolation isn't sufficient if they can be chained.
6. **Validate token identity on deposit paths.** xBNTa's failure to verify the deposited token was actually BNT shows that basic input validation matters just as much as sophisticated oracle design.
7. **Have an emergency pause/circuit-breaker ready and monitored.** xToken's ability to halt minting protocol-wide within ~30 minutes limited further damage, but faster anomaly detection (e.g., automated NAV-deviation alerts) could have caught it sooner.
8. **Complexity is itself a risk.** xToken explicitly cited xSNX's deep external dependency chain (Synthetix, Set Protocol, Curve, Kyber) as the reason it could not fully secure the product, and chose to retire it rather than keep patching.

---

## References

- xToken Initial Report on xBNTa, xSNXa Exploit (Medium): https://medium.com/xtoken/initial-report-on-xbnta-xsnxa-exploit-d6e784387f8e
- The Block — "Attacker uses flash loans in $24.5 million exploit of DeFi protocol xToken": https://theblock.co/amp/post/104667/defi-protocol-xtoken-exploit-attack
- CoinGeek — "xToken DeFi protocol loses $7M in yet another exploit": https://coingeek.com/xtoken-defi-protocol-loses-7m-in-yet-another-exploit/
- Cointelegraph — "Beleaguered DeFi project xToken suffers second major exploit since May": https://cointelegraph.com/news/beleaguered-defi-project-xtoken-suffers-second-major-exploit-since-may
- Quadriga Initiative Case Study — Aug 2021 xToken Function Access Control Exploit: https://www.quadrigainitiative.com/casestudy/xtokenfunctionaccesscontrolexploit.php
- iosiro — xSNX Relaunch Smart Contract Audit: https://iosiro.com/audits/xsnx-relaunch-smart-contract-audit
- xToken — "xSNX Take Two" (post-relaunch write-up): https://medium.com/xtoken/xsnx-take-two-8003f5ed8782
- xToken — "xSNXa False Start: Post Mortem" (earlier related mint-path issue, Aug 2020): https://medium.com/xtoken/xsnxa-false-start-post-mortem-f26a7a735383
- Etherscan — xSNXa Token: https://etherscan.io/token/0x2367012ab9c3da91290f71590d5ce217721eefe4
- Etherscan — xSNXCore Implementation: https://etherscan.io/token/0x2934443c1749dcc0cdcabbd77098eea31d2ea6c3