# Sentiment Protocol Exploit — April 4, 2023

**Read-Only Reentrancy in `WeightedBalancerLPOracle.getPrice()`**

| | |
|---|---|
| **Protocol** | Sentiment (undercollateralized lending on Arbitrum) |
| **Date** | April 4, 2023, 17:50 UTC |
| **Chain** | Arbitrum One |
| **Loss** | ~$1,000,000 (≈90% later returned by the attacker) |
| **Vulnerability class** | Read-only reentrancy → oracle price manipulation |
| **Status** | Patched (oracle redeployed with reentrancy guard) |

---

## Table of Contents

- [Summary](#summary)
- [Root Cause](#root-cause)
- [Vulnerable Code](#vulnerable-code)
- [Attack Walkthrough](#attack-walkthrough)
- [On-Chain References](#on-chain-references)
- [Proof of Concept](#proof-of-concept)
- [The Fix](#the-fix)
- [Key Timestamps](#key-timestamps)
- [Lessons / Takeaways](#lessons--takeaways)
- [Further Reading](#further-reading)

---

## Summary

Sentiment is a permissionless, undercollateralized lending protocol. To value Balancer LP tokens (BPTs) posted as collateral, it relied on a custom oracle, `WeightedBalancerLPOracle`, which called into the Balancer Vault to read pool balances and total supply.

An attacker exploited a **read-only reentrancy** bug in Balancer V2: during `exitPool()`, Balancer burns LP tokens and transfers withdrawn assets (including native ETH) *before* it finishes updating its internal balances. Because the ETH transfer uses a low-level `call()`, it hands control back to the caller mid-update. From that reentrant callback, the attacker called Sentiment, which in turn called the oracle — reading a **freshly reduced `totalSupply()`** against **stale (not-yet-decremented) pool balances**. This inflated the reported BPT price by **>16x**, letting the attacker borrow far more than their real collateral justified.

---

## Root Cause

Balancer's `exitPool()` is not fully CEI-compliant (Checks-Effects-Interactions) with respect to the reentrancy guard scope:

1. LP tokens are burned (`totalSupply()` drops immediately).
2. Underlying tokens are transferred to the caller.
   - If one of the returned assets is **native ETH**, this uses a low-level `call()`, which triggers the receiving contract's `fallback()`.
3. **Only after** the transfer does Balancer finish updating its internal pool balances.

Because step 2 hands back execution before step 3 completes, any external `view` call made during that window — such as `Vault.getPoolTokens()` — returns **balances that don't yet reflect the withdrawal**, while `totalSupply()` **already does**.

Sentiment's oracle combined both values in the same price formula without checking whether it was being called during an in-progress Balancer operation:

```
price = (Σ balance[i] × weight-adjusted market price) / totalSupply()
```

A shrunk `totalSupply()` divided into a not-yet-shrunk numerator produces an inflated price — and Sentiment's risk engine trusted that number to gate borrowing.

**Why it evaded reentrancy protection:** `getPrice()` was declared `view`. Standard reentrancy guards (`nonReentrant` modifiers) only protect *state-mutating* functions; a `view` function has no state to "protect" from the guard's perspective, so it's simply never checked — even though it reads externally-manipulable state.

---

## Vulnerable Code

`WeightedBalancerLPOracle.sol` (deployed at [`0x16F3ae9C1727ee38c98417cA08BA785BB7641b5B`](https://arbiscan.io/address/0x16F3ae9C1727ee38c98417cA08BA785BB7641b5B)):

```solidity
function getPrice(address token) external view returns (uint) {
    (
        address[] memory poolTokens,
        uint256[] memory balances,
    ) = vault.getPoolTokens(IPool(token).getPoolId());

    uint256[] memory weights = IPool(token).getNormalizedWeights();

    uint length = weights.length;
    uint temp = 1e18;
    uint invariant = 1e18;
    for (uint i; i < length; i++) {
        temp = temp.mulDown(
            (oracleFacade.getPrice(poolTokens[i]).divDown(weights[i]))
                .powDown(weights[i])
        );
        invariant = invariant.mulDown(
            (balances[i] * 10 ** (18 - IERC20(poolTokens[i]).decimals()))
                .powDown(weights[i])
        );
    }

    return invariant
        .mulDown(temp)
        .divDown(IPool(token).totalSupply());
}
```

**The two unsafe reads:**
- `vault.getPoolTokens(...)` — live, manipulable mid-transaction balances.
- `IPool(token).totalSupply()` — used as the divisor; already reduced when read during the exploit window.

---

## Attack Walkthrough

Pool: *Balancer 33 WETH / 33 WBTC / 33 USDC*

| Step | Action | Pool `totalSupply` | Reported `price` (ETH) |
|---|---|---|---|
| 0 | Baseline | 8,412.44 | 0.2201 |
| 1 | Flash-loan 606 WBTC, 10,050.1 WETH, 18M USDC from Aave v3 | — | — |
| 2 | Open Sentiment account, deposit 50 WETH, LP into pool → 221.2 BPT (used as collateral) | 8,633.65 | 0.2201 |
| 3 | Directly LP remaining flash-loan funds (606 WBTC / 10,000 WETH / 18M USDC) → 130,600.98 BPT | 139,234.63 | ~unchanged |
| 4 | Call `exitPool()` withdrawing the step-3 liquidity, **requesting native ETH** as one output asset | — | — |
| 5 | Balancer burns 130,600.98 BPT, sends ETH via `call()` → **reentry into attacker's `fallback()`** | 8,633.65 (already dropped) | — |
| 6 | Attacker's `fallback()` calls Sentiment → Sentiment queries oracle mid-reentrancy | 8,633.65 | **3.5501** (16x inflated) |
| 7 | Attacker borrows 461K USDC, 361K USDT, 81 WETH, 125K FRAX against the now-"$1.45M-valued" 50 WETH collateral | — | — |
| 8 | Swap FRAX → USDC, repay flash loan, withdraw remaining borrowed assets to EOA | — | — |

Net result: real collateral posted ≈ 50 ETH (~$92.5K); borrowing power granted ≈ 785 ETH-equivalent (~$1.45M) — the gap was drained from Sentiment's lending pools.

---

## On-Chain References

| Entity | Address / Link |
|---|---|
| Attack transaction | [`0xa9ff2b58...41e0f74d`](https://arbiscan.io/tx/0xa9ff2b587e2741575daf893864710a5cbb44bb64ccdc487a100fa20741e0f74d) |
| Attacker EOA | [`0xdd0cdb4c3b887bc533957bc32463977e432e49c3`](https://arbiscan.io/address/0xdd0cdb4c3b887bc533957bc32463977e432e49c3) |
| Attacker exploit contract | [`0x9f626F5941FAfe0A5b839907d77fbBD5d0deA9D0`](https://arbiscan.io/address/0x9f626F5941FAfe0A5b839907d77fbBD5d0deA9D0) |
| Attacker's Sentiment account (BeaconProxy) | [`0xdf346f8d160424c79cb8e8b49b13dd0ca61c3b8c`](https://arbiscan.io/address/0xdf346f8d160424c79cb8e8b49b13dd0ca61c3b8c) |
| Sentiment `AccountManager` | [`0x62c5AA8277E49B3EAd43dC67453ec91DC6826403`](https://arbiscan.io/address/0x62c5AA8277E49B3EAd43dC67453ec91DC6826403) |
| Vulnerable `WeightedBalancerLPOracle` | [`0x16F3ae9C1727ee38c98417cA08BA785BB7641b5B`](https://arbiscan.io/address/0x16F3ae9C1727ee38c98417cA08BA785BB7641b5B) |
| Patched `WeightedBalancerLPOracle` | [`0xC0Fc3193Bf2176D1DA6D2F24C14996766f46eB67`](https://arbiscan.io/address/0xC0Fc3193Bf2176D1DA6D2F24C14996766f46eB67) |
| Balancer Vault (Arbitrum) | [`0xBA12222222228d8Ba445958a75a0704d566BF2C8`](https://arbiscan.io/address/0xBA12222222228d8Ba445958a75a0704d566BF2C8) |

---

## Proof of Concept

Reproducible Foundry PoC (community-maintained):

- **Repo:** [SunWeb3Sec/DeFiHackLabs](https://github.com/SunWeb3Sec/DeFiHackLabs)
- **File:** `src/test/2023-04/Sentiment_exp.sol`
- **Run:**
  ```bash
  forge test --contracts ./src/test/2023-04/Sentiment_exp.sol -vvv
  ```

Sentiment's own oracle source (pre-fix implementation referenced in their postmortem):

- **Org:** [sentimentxyz](https://github.com/sentimentxyz)
- **Repo:** `sentimentxyz/oracle` — "Price Oracles for Sentiment"

---

## The Fix

Sentiment redeployed all Balancer LP oracle contracts with a mutating `getPrice()` that first checks whether Balancer's own reentrancy guard is currently engaged:

```solidity
function checkReentrancy() internal {
    vault.manageUserBalance(new IVault.UserBalanceOp[](0));
}

function getPrice(address token) external returns (uint) {
    checkReentrancy();
    (
        address[] memory poolTokens,
        uint256[] memory balances,
    ) = vault.getPoolTokens(IPool(token).getPoolId());
    // ...
}
```

`manageUserBalance([])` is a no-op on Balancer's Vault, but calling it will **revert** if the Vault's internal reentrancy lock is currently held (i.e., mid-`exitPool`). This forces `getPrice()` to fail loudly instead of silently returning manipulated data — implementing Balancer's own [recommended on-chain BPT pricing guidance](https://docs.balancer.fi/concepts/advanced/valuing-bpt.html#on-chain-price-evaluation). Note the function had to drop `view`, since `checkReentrancy()` is a real (non-static) external call.

---

## Key Timestamps

| Event | Time (UTC) | Tx |
|---|---|---|
| Exploit executed | Apr 4, 2023, 17:50 | [tx](https://arbiscan.io/tx/0xa9ff2b587e2741575daf893864710a5cbb44bb64ccdc487a100fa20741e0f74d) |
| Issue identified | Apr 4, 2023, 18:00 | — |
| Protocol paused / mitigated | Apr 4, 2023, 19:26 | [tx](https://arbiscan.io/tx/0xbeedfeb88f2d83eb9e26f586bf6001c29627202cd539ca93e99f1bd11d61ac25) |
| Fix deployed / resolved | Apr 5, 2023, 04:35 | [tx](https://arbiscan.io/tx/0xfa324fb23cdac4b94f3dfb0071bc3075cde29917178753a720ef7905a21cc0e7) |

Roughly 90% of stolen funds were later returned by the attacker after negotiation with the Sentiment team.

---

## Lessons / Takeaways

- **`view` ≠ safe from reentrancy.** Reentrancy guards conventionally protect state-mutating functions; a read-only function that reads *externally manipulable* state (another protocol's live balances) is just as exploitable.
- **Native ETH transfers via `call()` are a reentrancy hazard.** Any function that can send ETH mid-operation hands control to the recipient before your own bookkeeping is finished — treat this exactly like a state-mutating external call for guard purposes.
- **Don't trust composed protocol state without verifying its settlement.** If your oracle reads from another protocol (Balancer, Curve, Uniswap, etc.), check whether that protocol exposes a way to detect "operation in progress" (e.g., Balancer's `manageUserBalance` no-op trick) and use it.
- **Numerator/denominator asymmetry is a classic tell.** Any price formula combining two values from the same external system (here, `balances[]` and `totalSupply()`) is vulnerable if those two values can be updated at different points within the same transaction.

---

## Further Reading

- [Sentiment Incident Postmortem (official)](https://hackmd.io/@sentimentxyz/SJCySo1z2)
- [Balancer & Read-Only Reentrancy — Part 1 (Coinmonks)](https://medium.com/coinmonks/theoretical-practical-balancer-and-read-only-reentrancy-part-1-d6a21792066c)
- [QuillAudits — Decoding Sentiment Protocol's $1M Exploit](https://quillaudits.medium.com/decoding-sentiment-protocols-1-million-exploit-quillaudits-f36bee77d376)
- [Neptune Mutual — How Was Sentiment Exploited?](https://neptunemutual.com/blog/how-was-sentiment-exploited/)
- [Balancer Docs — On-chain BPT Price Evaluation](https://docs.balancer.fi/concepts/advanced/valuing-bpt.html#on-chain-price-evaluation)