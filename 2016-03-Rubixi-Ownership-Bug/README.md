# Rubixi Ownership Bug (2016)

## Overview

The Rubixi Ownership Bug is one of the most well-known examples of an incorrect constructor vulnerability in early Solidity versions. The vulnerability occurred because the contract was renamed from **DynamicPyramid** to **Rubixi**, but the constructor retained its original name.

Before Solidity introduced the `constructor` keyword, constructors were identified solely by having the same name as the contract. Since the constructor name no longer matched the contract name, it became an ordinary public function that anyone could call after deployment.

An attacker could invoke the incorrectly named constructor to become the contract owner and subsequently gain access to all privileged administrative functions, including withdrawing accumulated fees and transferring ownership.

---

## Root Cause

The vulnerability was caused by an incorrectly named constructor.

The contract was declared as:

```solidity
contract Rubixi
```

while the constructor remained:

```solidity
function DynamicPyramid()
```

Because the names did not match, Solidity treated `DynamicPyramid()` as a normal public function instead of a constructor.

This allowed any user to execute the function after deployment and overwrite the `creator` variable.

---

## Affected Contract

### Rubixi

**Contract**

- `contracts/Rubixi.sol`

**Vulnerable Function**

- `DynamicPyramid()`

The function assigns:

```solidity
creator = msg.sender;
```

without any access restriction.

---

## Attack Flow

1. Contract is deployed.
2. Constructor is never executed.
3. Attacker calls `DynamicPyramid()`.
4. `creator` becomes the attacker.
5. `onlyowner` modifier now authorizes the attacker.
6. The attacker withdraws collected fees or changes ownership.

---

## Technical Impact

The vulnerability demonstrated that:

- Constructor names must exactly match the contract name in older Solidity versions.
- Renaming a contract without renaming its constructor can completely compromise ownership.
- Access control mechanisms are ineffective if ownership initialization is broken.

---

## Lessons Learned

- Use the `constructor` keyword instead of constructor naming.
- Carefully review ownership initialization logic.
- Audit access control mechanisms.
- Upgrade legacy Solidity contracts whenever possible.

---

## Vulnerability Classification

- Incorrect Constructor Name
- Ownership Takeover
- Access Control Vulnerability
- Legacy Solidity Constructor Bug

---

## References

See the `sources/` directory:

- `incident-report.md`
- `technical-analysis.md`
- `references.md`