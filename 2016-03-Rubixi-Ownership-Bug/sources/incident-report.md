# Incident Report

## Summary

Rubixi is a pyramid scheme smart contract that became vulnerable after the contract was renamed from **DynamicPyramid** to **Rubixi** without renaming its constructor.

As a result, the constructor became a publicly callable function, allowing any user to become the contract owner after deployment.

Once ownership was obtained, privileged administrative functions could be executed by the attacker.

---

## Impact

- Complete ownership takeover.
- Unauthorized access to administrative functions.
- Ability to withdraw accumulated fees.
- Ability to permanently transfer ownership.

---

## Root Cause

The constructor name no longer matched the contract name.

Instead of executing only during deployment, the constructor became a normal public function callable by anyone.

This allowed arbitrary users to overwrite the owner variable.