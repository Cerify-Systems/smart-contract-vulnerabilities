# SPL Token Lending — 2021

## Vulnerability

In 2021, Neodyme discovered a critical vulnerability in the **Token Lending program of the Solana Program Library (SPL)**.

SPL Token Lending allows users to deposit tokens and receive **cTokens** representing their share of the deposited assets. These cTokens can then be used as collateral to borrow other assets.

The vulnerability was in the calculation used when converting between the underlying token amount and cToken amount.

### Root Cause

The program used a **round-to-nearest** operation when calculating token amounts.

Conceptually, the vulnerable calculation behaved like:

```text
token_amount = round(cToken_amount × exchange_rate)
```

The problem is that `round()` can round the result **up**.

For example:

```text
Calculated value = 100.6 tokens

round(100.6) = 101 tokens
```

This means the user could receive 101 tokens even though the calculated value was only 100.6 tokens.

By repeatedly taking advantage of this rounding behavior, an attacker could potentially extract more underlying tokens than they were entitled to.

The issue became particularly serious because SPL Token Lending was used as a base for several Solana lending protocols. Neodyme estimated that approximately **$2.6 billion in total value was at risk** at the time of disclosure. No funds were reported stolen from the affected protocols as a result of this vulnerability.

## Vulnerable Component

The vulnerable code was part of:

```text
spl-token-lending
└── token-lending
    └── program
```

The affected logic performed conversions between:

```text
Tokens ↔ cTokens
```

The issue was the use of rounding instead of rounding down.

## Exploitation

An attacker could repeatedly perform operations that benefited from the rounding-up behavior.

Each individual rounding difference could be very small, but repeated operations could accumulate the difference and allow the attacker to obtain more tokens than the protocol intended.

This is therefore an example of a **precision / rounding vulnerability in financial smart-contract logic**.

## Tool / Detection

The vulnerability was discovered through **manual security auditing and code analysis by Neodyme**.

Neodyme investigated the SPL Token Lending implementation and identified the incorrect rounding behavior. They subsequently developed an exploit demonstrating that the issue could be economically significant.

**Language:** Rust

**Platform:** Solana

**Type:** Arithmetic / Rounding / Precision Error

## Fix

The vulnerable `round` operations were replaced with **`floor` operations**.

Instead of:

```text
amount = round(calculated_amount)
```

the corrected implementation uses:

```text
amount = floor(calculated_amount)
```

This guarantees that the protocol does not give the user more tokens than the calculated value allows.

For example:

```text
Calculated value = 100.6

round(100.6) = 101  ❌

floor(100.6) = 100  ✅
```

The fix prevents users from gaining value simply because a conversion calculation happens to fall above a fractional boundary.

Neodyme reported the vulnerability and the affected projects were given time to patch their implementations. The fix was subsequently incorporated into the SPL Token Lending code.

## Impact

The vulnerability potentially affected multiple Solana DeFi protocols that had based their lending implementations on SPL Token Lending.

The estimated TVL at risk at the time of disclosure was approximately:

```text
$2.6 billion
```

The vulnerability was fixed before a known public exploitation resulting in loss of funds.

## Classification

* **Vulnerability:** Incorrect Rounding / Precision Error
* **Root Cause:** Use of `round` instead of `floor`
* **Impact:** Potential extraction of excess tokens
* **Language:** Rust
* **Blockchain:** Solana
* **Component:** SPL Token Lending

## References

* Neodyme vulnerability disclosure:
  https://neodyme.io/en/blog/lending_disclosure

* SPL Token Lending repository:
  https://github.com/solana-labs/solana-program-library/tree/master/token-lending

* SPL Token Lending documentation:
  https://spl.solana.com/token-lending
