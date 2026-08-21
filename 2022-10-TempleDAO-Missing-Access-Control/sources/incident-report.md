# Incident Report

## Summary

The TempleDAO exploit occurred in October 2022 and targeted the `StaxLPStaking` contract. The attacker abused a publicly accessible migration function that lacked authorization checks.

By supplying a malicious staking contract, the attacker manipulated the migration process and transferred staking assets under their control.

The exploit resulted in approximately **$2.4 million** in losses before the protocol suspended operations.

---

## Timeline

- **October 11, 2022** – Attack executed.
- TempleDAO identified the exploit.
- Staking contracts were paused.
- Security researchers analyzed the missing access control vulnerability.

---

## Impact

- Approximately **$2.4 million** stolen.
- Staking operations suspended.
- Highlighted the importance of validating external contract addresses.
- Demonstrated the risks of unrestricted migration functions.

---

## Root Cause

The migration function accepted arbitrary contract addresses without verifying that they belonged to an approved migration contract.

This allowed attackers to execute malicious migration logic and drain protocol funds.