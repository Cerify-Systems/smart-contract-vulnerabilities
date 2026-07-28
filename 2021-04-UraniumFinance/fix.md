# Fix


The invariant check should use the same scaling factor as the balance adjustments:

```solidity
require(
    balance0Adjusted.mul(balance1Adjusted) >=
    uint(_reserve0).mul(_reserve1).mul(10000**2),
    "UraniumSwap: K"
);
```
With this correction, every value participating in the invariant calculation is scaled consistently, restoring the mathematical guarantees of the Automated Market Maker (AMM).

## Additional Security Improvements

Although changing the constant fixes the immediate vulnerability, several engineering practices could have prevented the exploit:

### 1. Use Named Constants

Instead of hardcoding numerical values throughout the codebase, define them once as immutable constants.

```solidity
uint256 constant FEE_DENOMINATOR = 10000;
```
Using a single constant ensures that future modifications automatically propagate throughout the contract, reducing the risk of inconsistent updates.

### 2. Invariant Testing

Every swap should be tested to verify that the constant-product invariant never decreases.

Example property:

```text
K_after >= K_before
```
property-based testing and fuzz testing would have detected the weakened invariant before deployment.

### 3. Formal Verification

Formal verification tools can mathematically prove that critical invariants always hold regardless of user input. Applying formal methods to the swap logic would likely have identified the inconsistency before deployment.

## Lessons Learned

The Uranium Finance incident demonstrates that:

* Forking a battle-tested protocol does not guarantee security after modifications.
* Even a one-line arithmetic inconsistency can invalidate the security assumptions of an AMM.
* Core financial logic should always be protected with invariant tests, fuzzing, and formal verification.
* Replacing hardcoded "magic numbers" with named constants improves maintainability and reduces the risk of introducing similar vulnerabilities during future upgrades.

This exploit remains one of the most well-known examples of how a seemingly minor code modification can lead to catastrophic financial losses in decentralized finance.

