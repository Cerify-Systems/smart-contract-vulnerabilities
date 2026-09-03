# Opyn — Incorrect Option Settlement Logic (ETH Put "Double Exercise" Incident)

## Summary

| | |
|---|---|
| **Protocol** | Opyn (v1 — "Convexity Protocol") |
| **Date** | August 4, 2020, starting 09:25:54 AM UTC |
| **Vulnerability class** | Incorrect option settlement / exercise logic — flawed `msg.value` accounting across a loop |
| **Affected component** | ETH-collateralized **Put** oToken contracts only |
| **Contract** | `OptionsContract.sol` |
| **Faulty function** | `_exercise()` (internal), invoked repeatedly from `exercise()` |
| **Loss** | ~371,260 USDC stolen by the attacker |
| **Recovery** | ~439,000–572,000 USDC pulled out via Opyn's own white-hat drain of remaining vaults |

---

## Background

Opyn v1 (built on what the team called the "Convexity Protocol") let anyone mint, buy, sell, and **exercise** options on ERC20 assets. Options were represented as ERC20 "oTokens." Sellers locked collateral into per-address `Vault` structs; buyers of the corresponding oToken could later **exercise** — burn their oTokens, hand over the underlying asset, and receive the promised collateral payout.

For ETH Put options specifically, the *underlying* asset being handed over during exercise was ETH itself (not an ERC20), which meant the contract had to treat ETH reception differently from a standard ERC20 `transferFrom`.

---

## The Vulnerability

Opyn's `exercise()` function allowed a caller to settle against **multiple vaults in a single transaction**, looping through a supplied array and calling an internal `_exercise()` once per vault:

```solidity
function exercise(
    uint256 oTokensToExercise,
    address payable[] memory vaultsToExerciseFrom
) public payable {
    require(!isSystemPaused(), "Option contract is paused");
    require(oTokensToExercise > 0, "Can't exercise 0 oTokens");

    for (uint256 i = 0; i < vaultsToExerciseFrom.length; i++) {
        address payable vaultOwner = vaultsToExerciseFrom[i];
        require(hasVault(vaultOwner), "Cannot exercise from a vault that doesn't exist");
        Vault storage vault = vaults[vaultOwner];
        if (oTokensToExercise == 0) {
            return;
        } else if (vault.oTokensIssued >= oTokensToExercise) {
            _exercise(oTokensToExercise, vaultOwner);
            return;
        } else {
            oTokensToExercise = oTokensToExercise.sub(vault.oTokensIssued);
            _exercise(vault.oTokensIssued, vaultOwner);
        }
    }
    ...
}
```

Inside the **historical, vulnerable** `_exercise()`, when the underlying asset was ETH, the contract validated payment like this (illustrative — this branch has since been removed entirely):

```solidity
// [historical / vulnerable pattern — for illustration]
if (isETH(underlying)) {
    require(msg.value == amtUnderlyingToPay, "wrong ETH amount sent");
    // no ETH bookkeeping decrement happens here
} else {
    underlying.transferFrom(msg.sender, address(this), amtUnderlyingToPay);
}
```

### Why this was wrong

`msg.value` is a **transaction-level constant** in Solidity — it reflects the total ETH sent with the call and does **not** decrease as it gets "used" inside internal function calls or loop iterations. The contract, however, treated `msg.value == amtUnderlyingToPay` as proof of a *fresh* ETH payment on every single call to `_exercise()`.

Because `exercise()` could invoke `_exercise()` multiple times per transaction (once per vault in the loop), the same `msg.value` — sent to the contract exactly once — was checked and "accepted" as valid payment **on every iteration**. No running balance or decrement tracked how much ETH had already been consumed.

---

## Attack Flow

1. The attacker held oETH Put oTokens issued against **two (or more) separate vaults**, each requiring the same ETH amount to exercise (e.g., 150 oTokens / 75 ETH per vault).
2. The attacker called `exercise()` with `vaultsToExerciseFrom` containing **multiple vault addresses**, and sent `msg.value` equal to the ETH required for **one** vault's exercise (75 ETH).
3. On the first loop iteration, `_exercise()` validated `msg.value == amtUnderlyingToPay` — correct, since the attacker had genuinely sent that ETH. The contract burned oTokens and paid out USDC collateral from vault #1.
4. On the second (and subsequent) loop iterations, `_exercise()` ran the **same check** against the **same, already-spent** `msg.value` — which still equaled the required amount. The check passed again, with no new ETH actually transferred.
5. The contract burned more oTokens and paid out USDC collateral from vault #2 (and further vaults), all funded by ETH that had only been sent once.
6. Net result: the attacker received USDC settlement payouts for multiple vaults while only ever paying the ETH cost of one — effectively getting free collateral extractions plus their original ETH back.

This is why the bug is described as a **"double exercise"** attack.

---

## Impact & Loss

- **~371,260 USDC** was confirmed stolen from ETH Put vaults.
- Only **ETH Put** oToken contracts were affected; all other Opyn markets (calls, ERC20-collateralized options) were untouched.
- Upon discovering the exploit (first flagged publicly on Twitter), the Opyn team:
  - Pulled liquidity from the affected Uniswap pools.
  - Disabled new vault creation / oToken purchases for the affected contracts.
  - Conducted their own **white-hat drain** of the remaining vulnerable vaults to protect outstanding collateral, recovering roughly 439,000–572,000 USDC (reports vary slightly on the exact recovered figure).
  - Offered to buy back all outstanding ETH Put oTokens at 20% above market price on Deribit to protect holders who couldn't otherwise exit safely.
- Opyn committed to expanding audit scope, increasing bug bounty rewards, and adding Echidna-based fuzz testing (Trail of Bits) going forward.

---

## The Fix

The corrected `OptionsContract.sol` eliminates the vulnerable code path structurally rather than patching the check in place:

1. **ETH is no longer permitted as the underlying asset at all**, enforced directly in the constructor:
   ```solidity
   require(
       address(_underlying) != address(0),
       "OptionsContract: Can't use ETH as underlying."
   );
   ```
2. **`_exercise()` always pulls the underlying via standard ERC20 `transferFrom`**, with no ETH-specific branch and no dependence on `msg.value`:
   ```solidity
   require(
       underlying.transferFrom(
           msg.sender,
           address(this),
           amtUnderlyingToPay
       ),
       "OptionsContract: Could not transfer in tokens"
   );
   ```

Because `transferFrom` requires a real balance and allowance movement **on every call**, it is inherently safe to invoke repeatedly inside a loop — unlike a static `msg.value` check, each `transferFrom` call independently verifies and moves real funds. This closes the reuse loophole entirely by removing the flawed instrument (raw ETH handling in a loop) rather than attempting to reintroduce more complex bookkeeping.

### General lesson
> Any time a `payable` function's `msg.value` is checked inside a loop, or across multiple internal calls within the same transaction, it must be treated as a **fixed, transaction-wide total** — not a per-call amount. Safe patterns require caching `msg.value` into a local variable and explicitly decrementing it as it's "spent," or avoiding raw ETH handling inside repeatable/loopable logic altogether in favor of pull-based ERC20-style transfers.

---

## References

- Opyn's official incident postmortem: `https://medium.com/opyn/opyn-eth-put-exploit-c5565c528ad2`
- PeckShield root cause analysis: `https://peckshield.medium.com/opyn-hacks-root-cause-analysis-c65f3fe249db`
- Secureum — "Making Opyn SAFU" (audit/incident breakdown, confirms `OptionsContract.sol` / `exercise()` / `_exercise()` as the affected function): `https://secureum.substack.com/p/making-opyn-safu-secureum-6`
- The Defiant — incident coverage: `https://thedefiant.substack.com/p/defis-lack-of-safety-nets-exposed`
- CoinGeek — incident coverage and loss figures: `https://coingeek.com/defi-platform-opyn-loses-371k-after-exploit/`
- Opyn GitHub organization (for browsing current/legacy contract source): `https://github.com/opynfinance`

