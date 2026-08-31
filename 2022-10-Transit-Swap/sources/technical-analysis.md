# Technical Analysis

## Vulnerable Component

The vulnerability existed within Transit Swap's permission management contract.

Unlike many smart contract incidents, the vulnerable contract was not publicly verified. Public analyses were therefore based on decompiled blockchain bytecode.

---

## Vulnerable Logic

The permission management contract accepted an externally supplied owner address and executed token transfers without validating that the caller was authorized to act on behalf of that owner.

Conceptually, the vulnerable behavior resembled:

```solidity
transferFrom(owner, recipient, amount);
```

without first verifying that the supplied owner had authorized the caller.

As a result, any address that had previously approved the Transit Swap contract could become a victim.

---

## Attack Sequence

```
Victim approves Transit Swap

↓

Attacker supplies victim address

↓

Missing authorization check

↓

transferFrom()

↓

Tokens transferred

↓

Repeat
```

---

## Security Lessons

- Never trust externally supplied ownership information.
- Always validate authorization before privileged operations.
- Treat user-controlled parameters as untrusted input.
- Restrict token approvals whenever possible.
- Perform thorough security reviews of permission management logic.