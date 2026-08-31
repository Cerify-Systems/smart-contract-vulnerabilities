# Incident Report

## Summary

The Transit Swap Hack occurred on October 2, 2022, when attackers exploited a vulnerability in the protocol's permission management contract. By abusing missing authorization checks, the attacker was able to transfer tokens from users who had previously approved the protocol.

The exploit affected multiple tokens on BNB Smart Chain and resulted in losses estimated at approximately $21 million.

Following the attack, the Transit Swap team suspended services, collaborated with blockchain security firms and exchanges, and recovered a substantial portion of the stolen assets.

---

## Timeline

- **October 2, 2022** – Attack detected.
- Transit Swap suspended protocol services.
- Security firms began investigating the exploit.
- Exchanges assisted in tracking stolen assets.
- A significant portion of the funds was later recovered.

---

## Impact

- Approximately **$21 million** stolen.
- Multiple supported tokens affected.
- Temporary suspension of protocol operations.
- Highlighted the importance of authorization checks in permission management systems.

---

## Root Cause

The permission management contract trusted user-supplied owner information without verifying authorization before executing token transfers.

This allowed attackers to abuse existing token approvals and transfer assets belonging to other users.