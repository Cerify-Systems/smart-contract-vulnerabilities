# Attack Analysis

## Main Contract Relationship

```text
                ┌─────────────────────┐
                │  Fuse Comptroller    │
                │                     │
                │  exitMarket()       │
                └─────────┬───────────┘
                          │
                          │ account snapshot
                          ▼
                ┌─────────────────────┐
                │  CEther / CToken     │
                │                     │
                │  borrow()           │
                └─────────┬───────────┘
                          │
                          │ external ETH transfer
                          ▼
                ┌─────────────────────┐
                │ Attacker Contract    │
                │                     │
                │ receive()/fallback() │
                └─────────┬───────────┘
                          │
                          │ re-enter
                          ▼
                Comptroller.exitMarket()
```

## Critical State Transition

Before the ETH transfer:

```text
Collateral: present
Borrow balance: old value
```

The protocol then transferred ETH externally.

During the transfer:

```text
Attacker callback
      ↓
exitMarket()
      ↓
getAccountSnapshot()
      ↓
new ETH borrow not yet reflected
```

The account could therefore pass the `amountOwed == 0` test and exit its collateral market.After the callback, the original borrow operation continued.

The attacker now had:

```text
borrowed ETH
+
released collateral
```

## Why the Reentrancy Guard Was Insufficient

Rari had already recognized reentrancy as a risk and added a pool-wide guard to many market operations. The critical oversight was that `exitMarket()` was not covered. This is why the incident is a useful example of **incomplete reentrancy mitigation** rather than simply "forgot to use `nonReentrant`". Incident analyses explicitly describe the missed `exitMarket()` protection. 
