# TempleDAO Missing Access Control (2022)

## Overview

The TempleDAO Missing Access Control vulnerability was exploited in October 2022 and resulted in the theft of approximately **$2.4 million** worth of staking tokens. The vulnerability existed in the `StaxLPStaking` contract, where a migration function intended for legitimate stake migration lacked proper authorization checks.

The contract trusted user-supplied contract addresses without verifying that they belonged to an approved migration contract. An attacker exploited this weakness by deploying a malicious contract and passing its address into the migration function, allowing arbitrary token withdrawals.

Unlike reentrancy or arithmetic vulnerabilities, this exploit was caused by **missing access control and insufficient validation of external contract addresses**.

---

## Root Cause

The vulnerability was caused by the absence of authorization checks in the `migrateStake()` function.

The function accepted an external staking contract supplied by the caller and immediately invoked its migration logic without verifying that the supplied contract was trusted.

Because no validation or access restriction existed, an attacker could substitute a malicious contract and execute arbitrary withdrawal logic.

---

## Affected Contract

### StaxLPStaking

**Contract**

- `contracts/StaxLPStaking.sol`

**Vulnerable Function**

- `migrateStake()`

The function trusted a user-supplied staking contract and performed an external call without validating its legitimacy.

---

## Attack Flow

1. The attacker deployed a malicious staking contract.
2. The attacker called `migrateStake()`.
3. The malicious contract address was supplied as the migration source.
4. The vulnerable contract executed the malicious contract's migration logic.
5. Tokens were transferred to the attacker.
6. Approximately **$2.4 million** worth of assets were drained.

---

## Technical Impact

The attack demonstrated that:

- External contract addresses must never be trusted without validation.
- Sensitive migration functions require proper authorization.
- Missing access control can be as damaging as low-level Solidity vulnerabilities.
- Business logic flaws can directly result in complete loss of protocol funds.

---

## Lessons Learned

- Restrict administrative functions using appropriate access control.
- Validate all externally supplied contract addresses.
- Maintain a whitelist of approved migration contracts.
- Follow the principle of least privilege.
- Thoroughly review migration and upgrade mechanisms during security audits.

---

## Vulnerability Classification

- Missing Access Control
- Missing Authorization
- Arbitrary External Call
- Business Logic Vulnerability

---

## References

See the `sources/` directory:

- `incident-report.md`
- `technical-analysis.md`
- `references.md`