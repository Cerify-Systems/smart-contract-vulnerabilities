# Port Finance – Max Withdraw

## Vulnerability

Port Finance is a lending protocol on Solana that allows users to deposit assets as collateral and borrow other assets against them.

The vulnerability was found in the calculation of the **maximum amount of collateral that a user could withdraw** from an obligation.

The affected function was:

```text
Obligation::max_withdraw_value()
```

Its purpose was to calculate how much collateral a user could safely withdraw while still keeping enough collateral to satisfy the protocol's borrowing requirements.

### Root Cause

The calculation incorrectly treated the collateral being withdrawn as if it had the same **Loan-to-Value (LTV)** requirement as the rest of the obligation.

In a lending protocol, different assets can have different LTV ratios. For example:

```text
Asset A → LTV = 80%
Asset B → LTV = 60%
```

Therefore, the amount of collateral that can safely be withdrawn depends on **which specific collateral reserve is being withdrawn**.

The vulnerable implementation calculated the required remaining collateral using the obligation's total deposited value and allowed borrow value, but it did **not include the LTV of the specific reserve being withdrawn**.

Conceptually, the vulnerable calculation was:

```text
Required collateral
        =
Borrowed value × Deposited value
--------------------------------
     Allowed borrow value
```

This could produce an incorrect maximum withdrawal amount.

### Impact

Because the maximum withdrawal amount was calculated incorrectly, a user could potentially withdraw **more collateral than the protocol should have allowed** while still having outstanding debt.

This could leave the obligation with insufficient collateral relative to the risk parameters of the particular asset being withdrawn.

The issue was therefore a **logic/calculation vulnerability**, rather than a memory-safety or authentication vulnerability.

### Vulnerable Code

The affected logic was located in:

```text
token-lending/program/src/state/obligation.rs
```

The repository also contains a proof-of-concept test:

```text
token-lending/program/tests/max_withdraw_bug_poc.rs
```

The PoC demonstrates the incorrect maximum-withdraw calculation.

### Tool / Detection

The vulnerability was reported through security research and was subsequently reviewed during the Port Finance bug-fix process.

The available proof-of-concept test can be used to reproduce the incorrect calculation.

**Primary analysis:** Rust source-code review + Proof of Concept (PoC)

### Fix

The fix was to make the maximum-withdraw calculation aware of the **LTV of the particular collateral reserve being withdrawn**.

A new value representing the withdrawal collateral's LTV was incorporated into the calculation:

```text
withdraw_collateral_ltv
```

The corrected calculation therefore considers:

1. The user's current borrowed value.
2. The total deposited/collateral value.
3. The protocol's allowed borrow value.
4. **The LTV of the specific collateral reserve being withdrawn.**

This ensures that the maximum withdrawal amount is calculated according to the actual risk parameters of the asset being removed.

### Vulnerability Classification

* **Type:** Logic Error / Incorrect Calculation
* **Category:** Improper collateral withdrawal validation
* **Language:** Rust
* **Platform:** Solana
* **Affected Component:** `Obligation::max_withdraw_value()`

## References

* Port Finance repository:
  https://github.com/port-finance/variable-rate-lending

* Port Finance Max Withdraw PoC:
  https://github.com/port-finance/variable-rate-lending/blob/master/token-lending/program/tests/max_withdraw_bug_poc.rs

* Immunefi Bug Fix Review:
  https://immunefi.com/blog/bug-fix-reviews/port-finance-logic-error-bugfix-review/
