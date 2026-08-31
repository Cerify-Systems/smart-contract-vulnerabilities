# Incident Report

## Summary

The SpankChain Reentrancy Attack occurred in October 2018 and targeted the payment channel implementation used by the SpankChain platform. An attacker exploited a reentrancy vulnerability during the channel timeout process, allowing repeated withdrawals before the ledger channel state was deleted.

The vulnerability existed because the contract interacted with an external token contract before updating its own internal state. By supplying a malicious token contract, the attacker was able to recursively invoke the timeout function and withdraw the same funds multiple times.

The attack resulted in a loss of approximately **$38,000** worth of Ether. Following the incident, SpankChain suspended its payment channel service, deployed patched contracts, and compensated affected users.

---

## Timeline

- **October 2018** – Vulnerability exploited.
- SpankChain suspended payment channel operations.
- Investigation confirmed a reentrancy vulnerability.
- Patched contracts were deployed.
- Users were reimbursed.

---

## Impact

- Approximately **$38,000** stolen.
- Payment channel service temporarily suspended.
- Demonstrated that external token contracts can introduce reentrancy vulnerabilities.
- Reinforced adoption of the Checks-Effects-Interactions (CEI) pattern and reentrancy guards.

---

## Root Cause

The contract executed an external token transfer before deleting the ledger channel state.

A malicious token contract re-entered the vulnerable timeout function before state cleanup occurred, allowing multiple withdrawals from the same payment channel.

The issue was a classic violation of the Checks-Effects-Interactions (CEI) pattern.