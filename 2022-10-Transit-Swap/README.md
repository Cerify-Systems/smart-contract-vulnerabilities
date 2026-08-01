# Transit Swap Hack (2022)

## Overview

The Transit Swap Hack occurred on **October 2, 2022**, affecting the Transit Swap decentralized exchange (DEX) aggregator deployed on the BNB Smart Chain. The attacker exploited a flaw in the protocol's permission management logic, allowing arbitrary token transfers from users who had previously approved the Transit Swap contracts.

The attack resulted in the theft of approximately **$21 million** worth of digital assets across multiple tokens. Following the incident, the Transit Swap team paused affected services, worked with security firms and exchanges, and successfully recovered a significant portion of the stolen funds.

Unlike traditional smart contract exploits such as reentrancy or integer overflow, this incident was caused by **improper input validation and missing authorization checks** within a permission management contract.

---

## Root Cause

The vulnerability existed because the permission management contract trusted user-supplied parameters without verifying that the caller was authorized to spend tokens on behalf of the specified owner.

The vulnerable logic accepted an arbitrary owner address and directly executed `transferFrom()` on behalf of that address. If a user had previously approved the Transit Swap contract to spend tokens, an attacker could supply the victim's address as the owner parameter and transfer tokens without the victim's consent.

The absence of proper authorization checks allowed approved token balances to be drained from multiple users.

---

## Affected Component

### Permission Management Contract

The vulnerable component was the protocol's internal permission management contract responsible for processing token transfers.

**Original Solidity source code was not publicly released or verified.** Public security analyses were performed using decompiled blockchain bytecode rather than verified source code.

For this reason, this repository does not include a Solidity implementation of the vulnerable contract.

---

## Attack Flow

1. A user approves the Transit Swap contract to spend their tokens.
2. The attacker submits a malicious transaction supplying the victim's address as the token owner.
3. The permission management contract fails to verify the owner's authorization.
4. The contract executes `transferFrom()` using the victim's approval.
5. Tokens are transferred directly to the attacker.
6. The attack is repeated across multiple approved users.

---

## Technical Impact

The attack demonstrated that:

- Smart contracts should never trust user-supplied ownership information.
- Every privileged operation must perform explicit authorization checks.
- Token approvals become dangerous when permission validation is incomplete.
- Business logic vulnerabilities can be just as severe as low-level Solidity bugs.

---

## Lessons Learned

- Validate all user-controlled inputs.
- Never trust externally supplied owner addresses.
- Verify authorization before calling `transferFrom()`.
- Follow the principle of least privilege.
- Minimize long-lived token approvals where possible.

---

## Vulnerability Classification

- Improper Input Validation
- Missing Authorization Check
- Arbitrary `transferFrom()`
- Business Logic Vulnerability

---

## References

See the `sources/` directory:

- `incident-report.md`
- `technical-analysis.md`
- `references.md`