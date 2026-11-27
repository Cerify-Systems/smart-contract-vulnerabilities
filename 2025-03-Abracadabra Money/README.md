# Abracadabra Money — GMX V2 Cauldron Exploit (March 2025)

---

## Summary

| | |
|---|---|
| **Protocol** | Abracadabra Money (MIM Spell) |
| **Date** | March 25, 2025 |
| **Duration** | ~1 hour 40 minutes (07:57:52–09:37:36 UTC) |
| **Chain** | Arbitrum (funds later bridged to Ethereum) |
| **Loss** | ~$13–13.4M (≈6,262 ETH) |
| **Root cause** | Stale internal accounting after partial liquidation ("phantom collateral") |
| **Affected component** | `GmxV2CauldronV4` and its `RouterOrder` / `OrderAgent` periphery contracts |
| **Transactions** | 56 exploit transactions across 5 cauldrons |

---

## Background

Abracadabra Money lets users deposit interest-bearing tokens as collateral to borrow **MIM**, a USD-pegged stablecoin, through isolated lending markets called **Cauldrons**, built on top of **DegenBox** (a BentoBox variant).

To support **GMX V2** — an on-chain perpetual DEX with **non-atomic deposits/withdrawals** (a user submits an order, and a keeper fulfills it asynchronously later) — Abracadabra built a specialized `GmxV2CauldronV4`. Because a deposit can be "in flight" and not yet settled on-chain, the Cauldron extended its solvency check, `_isSolvent()`, to also count a user's *pending* order value via a function called `orderValueInCollateral()`, which lives inside a per-user `RouterOrder` proxy contract deployed by an `OrderAgent`.

This asynchronous design — collateral that is sometimes "real tokens on-chain" and sometimes "a promise of tokens still in transit" — is the surface the attacker exploited.

---

## The Vulnerability

Two functions in the RouterOrder contract fell out of sync with each other:

### 1. `sendValueInCollateral()` — removes real tokens, forgets to update state

```solidity
function sendValueInCollateral(address recipient, uint256 shareMarketToken) public onlyCauldron {
    (uint256 shortExchangeRate, uint256 marketExchangeRate) = getExchangeRates();

    uint256 amountShortToken = (degenBox.toAmount(IERC20(market), shareMarketToken, true) * oracleDecimalScale) /
        (shortExchangeRate * marketExchangeRate);

    shortToken.safeTransfer(address(degenBox), amountShortToken);
    degenBox.deposit(IERC20(shortToken), address(degenBox), recipient, amountShortToken, 0);
}
```

Called during liquidations, this function **physically extracts real tokens** from the RouterOrder — but never decrements the internal accounting fields (`inputAmount`, `minOut`, `minOutLong`) that describe how much collateral value is still "pending."

### 2. `orderValueInCollateral()` — reports stale, inflated value

```solidity
function orderValueInCollateral() public view returns (uint256 result) {
    (uint256 shortExchangeRate, uint256 marketExchangeRate) = getExchangeRates();

    if (depositType) {
        uint256 marketTokenFromValue = (inputAmount * shortExchangeRate * marketExchangeRate) / oracleDecimalScale;
        result = minOut < marketTokenFromValue ? minOut : marketTokenFromValue;
    } else {
        uint256 marketTokenFromValue = ((minOut + minOutLong) * shortExchangeRate * marketExchangeRate) / oracleDecimalScale;
        result = inputAmount < marketTokenFromValue ? inputAmount : marketTokenFromValue;
    }
}
```

This function computes the user's "pending" collateral purely from `inputAmount` / `minOut` / `minOutLong`. Since `sendValueInCollateral()` never reduced these fields, `orderValueInCollateral()` kept reporting the **original, pre-liquidation** value even after real tokens had already been pulled out — i.e., **"phantom collateral."**

Critically, `_isSolvent()` is only evaluated **once, at the end** of a batched `cook()` transaction (Abracadabra's multi-action transaction bundler) — not after every intermediate step — giving the attacker a window to manufacture an inconsistent state and still pass the final check.

---

## Attack Flow

### Preparation
- Attacker funded multiple wallets via Tornado Cash, bridged ETH to Arbitrum via Stargate, acquired GM tokens (gmETH/ETH) through GMX, and distributed small collateral positions across 5 wallets to seed multiple parallel attack paths.
- Deployed an exploit contract to orchestrate the batched calls.

### Exploitation (repeated per cauldron/wallet)
1. **Manufacture phantom collateral** — Submit a GMX deposit order via `cook()` with a deliberately unreachable `minOut`. GMX rejects the deposit and returns the input tokens (e.g., USDC) to the RouterOrder. The Cauldron still treats the order as if the deposit succeeded, because the accounting fields (`inputAmount`, `minOut`) were never invalidated.
2. **Seed a small borrow** — Borrow a small amount of MIM to fund the recycling loop.
3. **Push into liquidation** — Within a single `cook()` call: borrow MIM (Action 5) to push the loan-to-value ratio above the liquidation threshold, then call the attacker's own contract to precompute optimal extraction amounts (Action 30).
4. **Self-liquidate** — Trigger liquidation (Action 31). This pulls real, previously-returned USDC out of the RouterOrder via `sendValueInCollateral()` — but again, `inputAmount`/`minOut` are left untouched.
5. **Borrow against the phantom balance** — Since `orderValueInCollateral()` still reports the pre-liquidation value, the attacker borrows MIM *again* against collateral that no longer physically exists.
6. **Extract and repeat** — Swap out the borrowed MIM, then repeat the cycle across different wallets and cauldrons.
7. **Bypass the final check** — `_isSolvent()`, evaluated once at the end of the `cook()` batch, reads the stale `orderValueInCollateral()` value and reports the user as solvent. The transaction does not revert.

This pattern was repeated **56 times across 5 GM Cauldrons** (gmETH/ETH, gmETH, gmBTC, gmSOL, gmBTC/BTC) over ~100 minutes. The single largest extraction was ~932 ETH in one `cook()` call.

> Oracle prices were **not** manipulated — the exploit was purely a stale internal-accounting bug, not a price-feed attack.

---

## Why This Happened

- **Non-atomic integration complexity**: bridging GMX V2's asynchronous order model into a synchronous solvency-check system created "paper collateral" states that had to be perfectly reconciled with real token movements — and weren't.
- **Missing state invalidation on partial extraction**: `sendValueInCollateral()` moved real value out without updating the fields that `orderValueInCollateral()` depended on.
- **Batch-only solvency checking**: `_isSolvent()` ran once at the end of `cook()`, rather than after each state-changing action, giving the attacker a multi-step window to create and exploit the inconsistency before any check could catch it.
- **Audit gap**: the only audit of this component (Guardian Audits, Nov 14, 2023) flagged **4 Critical/High** and **10 Medium** severity findings — a strong signal the code needed a follow-up review. No re-audit was performed after subsequent architectural changes to the integration.

---

## Smart Contracts & GitHub References

| Item | Reference |
|---|---|
| Vulnerable functions (`sendValueInCollateral()`, `orderValueInCollateral()`) — `GmxV2CauldronOrderAgent.sol` | https://github.com/Abracadabra-money/abracadabra-money-contracts/blob/dff69a19a219bbff90ab7b752c9f9c0ab5e8fe6f/src/periphery/GmxV2CauldronOrderAgent.sol#L241-L280 |
| Prior security audit (Guardian Audits, Nov 14, 2023 — 4 Critical/High, 10 Medium findings) | https://github.com/Abracadabra-money/abracadabra-money-contracts/blob/main/audits/11-14-2023_Abracadabra_GMXV2.pdf |
| `GmxV2CauldronV4` (gmETH/ETH) — Arbiscan | https://arbiscan.io/address/0x625Fe79547828b1B54467E5Ed822a9A8a074bD61 |
| gmETH Cauldron | https://arbiscan.io/address/0x2b02bBeAb8eCAb792d3F4DDA7a76f63Aa21934FA |
| gmBTC Cauldron | https://arbiscan.io/address/0xD7659D913430945600dfe875434B6d80646d552A |
| gmSOL Cauldron | https://arbiscan.io/address/0x7962ACFcfc2ccEBC810045391D60040F635404fb |
| gmBTC/BTC Cauldron | https://arbiscan.io/address/0x9fF8b4C842e4a95dAB5089781427c836DAE94831 |
| Largest single exploit transaction (~932 ETH) | https://arbiscan.io/tx/0xe93ec4b5a5c96dbc2cf9321b29f38c7ae3f667986bee37696c8f0ed5e5ca6123 |
| Attacker wallet (primary origin) | `0xe9A4034E89608Df1731835A3Fd997fd3a82F2f39` |
| Attacker wallet (funding & laundering) | `0xaf9e33aa03caaa613c3ba4221f7ea3ee2ac38649` |

---

## Loss & Impact

- **~$13–13.4M** drained (≈6,262 ETH), minted as undercollateralized MIM across 5 GM Cauldrons.
- **GMX token price**: dropped **$55.20 → $46.92** (−15.0%).
- **MIM Spell price**: dropped **$1.20 → $1.08** (−10.0%), causing brief depegging pressure.
- **Scope contained**: only the GM-token-backed cauldrons were affected; other (non-GMX) Abracadabra cauldrons were unaffected, and no user collateral in unrelated markets was touched.
- This was Abracadabra's **second** major exploit, following a **~$6.49M** exploit in Jan/Feb 2024 (a CauldronV4 debt-accounting/share-inflation bug), and preceded a smaller **~$1.7M** exploit in October 2025 — all three targeted the Cauldron/router accounting layer.

---

## Incident Response / The Fix

**Immediate response:**
- All `gmCauldrons` were paused, halting further borrowing by 09:46:22 UTC (within ~9 minutes of the attack ending).
- The `orderAgent` address was set to `0x000...000` to block creation of any further GMX deposit orders.
- ~$260,000 in assets still sitting in RouterOrder contracts post-exploit were recovered.
- Abracadabra coordinated with Chainalysis, Guardian Audits, and the Seal 911 community for fund tracing and forensics, and offered the attacker a 20% bug bounty (~$2.58M) for return of funds.

**Root-cause fix:**
The core fix is to make `sendValueInCollateral()` decrement the same accounting fields that `orderValueInCollateral()` reads from, so extracted value can never be reported twice. Conceptually (illustrative patch):

```solidity
function sendValueInCollateral(address recipient, uint256 shareMarketToken) external onlyCauldron {
    (uint256 shortExchangeRate, uint256 marketExchangeRate) = getExchangeRates();

    uint256 amountShortToken =
        (degenBox.toAmount(IERC20(market), shareMarketToken, true) * oracleDecimalScale)
        / (shortExchangeRate * marketExchangeRate);

    // Decrement the "paper" collateral fields so orderValueInCollateral()
    // can no longer overstate the user's remaining collateral.
    if (depositType) {
        inputAmount = (inputAmount >= someEquivalentShort) ? (inputAmount - someEquivalentShort) : 0;
        if (minOut > someEquivalentShort) minOut -= someEquivalentShort;
    } else {
        // Equivalent adjustment to (minOut + minOutLong) or inputAmount
    }

    shortToken.safeTransfer(address(degenBox), amountShortToken);
    degenBox.deposit(IERC20(shortToken), address(degenBox), recipient, amountShortToken, 0);
}
```

A complete fix also requires correctly tracking closed/consumed orders and auditing every code path (deposits, liquidations, cancellations) that touches `inputAmount`, `minOut`, and `minOutLong`.

**Additional hardening recommended:**
1. **Intermediate solvency checks** — call `_isSolvent()` after each major step of a `cook()` batch, not only at the end.
2. **Re-audit after architectural changes** — the original Guardian Audits review already flagged serious issues; further integration changes should have triggered a follow-up audit before deployment.
3. **Restrict self-liquidation** — disallow or tightly constrain self-liquidation within a single transaction unless fully verified.
4. **Broaden real-time monitoring** — Hexagate monitoring was in place for Cauldrons but did not cover DegenBox, the vault that actually held the exploited assets; extending monitoring coverage would have enabled faster detection.

---

## Lessons Learned

1. **Non-atomic, cross-protocol integrations are a high-risk surface.** Any time a system must represent "value in transit" as if it were settled collateral, every code path that can extract real value must simultaneously and atomically update the accounting used for solvency.
2. **Batch-transaction solvency checks are only as strong as their weakest intermediate state.** Checking solvency once at the end of a multi-action batch allows an attacker to pass through invalid intermediate states undetected.
3. **Unresolved audit findings are a leading indicator of risk.** A pre-launch audit with 4 Critical/High and 10 Medium findings, with no subsequent re-audit after further architectural changes, is a strong warning sign.
4. **Oracle correctness doesn't guarantee protocol correctness.** This exploit is a reminder that accurate price feeds are necessary but not sufficient — internal state accounting must also be correct.
5. **Monitoring coverage should extend to every contract that custodies value**, not just the primary business-logic contracts (Cauldrons) — DegenBox, the actual vault, was left unmonitored.
6. **Repeated incidents in the same architectural layer signal systemic risk.** Three separate exploits (2024, March 2025, October 2025) all targeted the Cauldron/router accounting layer, suggesting the underlying design pattern — not just isolated bugs — warranted a deeper redesign.

---

## References

- Three Sigma, *"Draining the Cauldron: Inside the $13M Abracadabra GMX V2 Exploit"* (Mar 28, 2025): https://threesigma.xyz/blog/exploit/abracadabra-gmx-defi-exploit-explained
- Halborn, *"Explained: The Abracadabra Money Hack (March 2025)"*: https://www.halborn.com/blog/post/explained-the-abracadabra-money-hack-march-2025
- Phylax Credible Layer, *"Abracadabra GMX V2 Cauldron Exploit"* case study: https://docs.phylax.systems/assertions-book/previous-hacks/abracadabra-gmx-v2-exploit
- CoinDesk, *"Abracadabra Drained of $13M in Attack Targeting Cauldrons Tied to GMX Liquidity Tokens"*: https://www.coindesk.com/business/2025/03/25/abracadabra-drained-of-usd13m-in-exploit-targeting-cauldrons-tied-to-gmx-liquidity-tokens
- The Block, *"Hacker steals $13 million in Abracadabra's 'Magic Internet Money'..."*: https://www.theblock.co/post/348059/hacker-steals-13-million-in-abracadabras-magic-internet-money-seemingly-using-a-flash-loan-attack
- CryptoPotato, *"GMX Defends Contracts After $13 Million Loss Tied to Abracadabra's Cauldron Exploit"*: https://cryptopotato.com/gmx-defends-contracts-after-13-million-loss-tied-to-abracadabras-cauldron-exploit/
- Full attacker activity log (Abracadabra post-mortem spreadsheet): https://docs.google.com/spreadsheets/d/1VzOwlKbYjbfmTI0VXCH6CngCQT3QUBAxxZskAvVDjxg/edit?gid=0#gid=0