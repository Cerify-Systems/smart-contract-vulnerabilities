# SpankChain Reentrancy Attack (2018)

## Overview

The SpankChain Reentrancy Attack occurred in October 2018 and targeted SpankChain's payment channel smart contracts. The vulnerability allowed an attacker to repeatedly withdraw funds by exploiting a reentrancy flaw during channel timeout handling.

The attack resulted in the theft of approximately **$38,000** worth of Ether. Following the incident, SpankChain suspended its payment channel service, deployed patched contracts, and reimbursed affected users.

Unlike the DAO attack, which exploited Ether transfers, the SpankChain attack demonstrated that **external token contract calls** can also introduce reentrancy vulnerabilities when protocol state is updated after external interactions.

---

## Root Cause

The vulnerability was caused by a violation of the **Checks-Effects-Interactions (CEI)** pattern.

Within the `LCOpenTimeout()` function, the contract performed an external token transfer before deleting the ledger channel state.

If the transferred token implemented malicious behavior, its `transfer()` function could re-enter `LCOpenTimeout()` before the channel was deleted, allowing the attacker to execute multiple withdrawals from the same payment channel.

The vulnerability resulted from updating protocol state **after** interacting with an external contract.

---

## Affected Contract

### LedgerChannel

**Contract**

- `contracts/LedgerChannel.sol`

**Vulnerable Function**

- `LCOpenTimeout()`

The function transfers channel assets back to the participant before deleting the channel state, allowing reentrant execution through an external token contract.

---

## Attack Flow

1. The attacker created a ledger channel using a malicious token contract.
2. The channel reached its timeout period.
3. `LCOpenTimeout()` initiated token transfers.
4. The malicious token contract executed a callback during `transfer()`.
5. The callback re-entered `LCOpenTimeout()`.
6. Since the channel had not yet been deleted, the same balances could be withdrawn again.
7. The process repeated until the channel funds were drained.

---

## Technical Impact

The attack demonstrated that:

- External token transfers must be treated as untrusted external calls.
- State updates performed after external interactions can enable reentrancy.
- ERC-20 compatible interfaces may still contain arbitrary logic in token implementations.
- Following the Checks-Effects-Interactions pattern is essential for payment channel security.

---

## Lessons Learned

- Always follow the Checks-Effects-Interactions (CEI) pattern.
- Update protocol state before interacting with external contracts.
- Treat all external token contracts as potentially malicious.
- Use reentrancy guards for functions performing external calls.
- Minimize trust assumptions about third-party token implementations.

---

## Vulnerability Classification

- Reentrancy
- External Call Reentrancy
- Checks-Effects-Interactions (CEI) Violation
- Business Logic Vulnerability

---

## References

See the `sources/` directory for:

- `incident-report.md`
- `technical-analysis.md`
- `references.md`