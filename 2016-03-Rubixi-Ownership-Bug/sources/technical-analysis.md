# Technical Analysis

## Vulnerable Contract

Contract:

```
contracts/Rubixi.sol
```

Relevant Function:

- `DynamicPyramid()`

---

## Vulnerable Logic

The contract defines:

```solidity
function DynamicPyramid() {
    creator = msg.sender;
}
```

Because the contract is named:

```solidity
contract Rubixi
```

the function is not recognized as a constructor.

Instead, it becomes a public function that can be called after deployment.

Calling this function assigns:

```solidity
creator = msg.sender;
```

allowing any user to become the contract owner.

---

## Attack Sequence

```
Deploy Contract

↓

DynamicPyramid()

↓

creator = attacker

↓

onlyowner passes

↓

collectAllFees()

↓

Funds withdrawn
```

---

## Security Lessons

- Always use the `constructor` keyword.
- Verify ownership initialization.
- Audit access control logic.
- Avoid legacy constructor syntax in modern Solidity.