# Technical Analysis

## Vulnerable Contract

Contract:

```
contracts/StaxLPStaking.sol
```

Relevant Function:

- `migrateStake()`

---

## Vulnerable Logic

The `migrateStake()` function accepted a staking contract address supplied by the caller.

Instead of validating that the supplied contract was trusted, the function immediately invoked its migration logic.

Conceptually, the vulnerable behavior was:

```solidity
oldStaking.migrateWithdraw(...);
```

without verifying that:

```solidity
oldStaking == trustedMigrationContract
```

This allowed attackers to substitute a malicious contract and execute arbitrary external code.

---

## Attack Sequence

```
Deploy malicious contract

↓

Call migrateStake()

↓

Supply malicious contract address

↓

External migration call

↓

Tokens transferred

↓

Protocol funds drained
```

---

## Security Lessons

- Protect migration functions with access control.
- Validate external contract addresses.
- Maintain whitelists for trusted migration contracts.
- Avoid trusting user-controlled parameters.
- Review upgrade and migration mechanisms during audits.