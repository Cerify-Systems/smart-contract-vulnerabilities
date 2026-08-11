# Attack Analysis

## Technical Reconstruction

The exploit targeted the Spartan Protocol V1 SPARTA/WBNB liquidity pool.

The pool maintained internal reserve variables while the actual ERC-20 balances could be changed independently through ordinary token transfers.

### Critical mismatch

```text
Internal reserve:
baseAmount / tokenAmount

Live balance:
token.balanceOf(pool)
```

The live balance could be increased without changing the internal reserve.

### Redemption

`removeLiquidityForMember()` obtained the redemption amounts from `UTILS.calcLiquidityShare()` and then reduced the stored pool balances.

The security problem was that `calcLiquidityShare()` used the live token balance.

Therefore:

```text
stored reserve != value used to price LP redemption
```

## Reconstructed Cycle

A detailed independent reconstruction gives the following sequence:

1. Flash loan: 100,000 WBNB.
2. Four/five swaps acquire SPARTA.
3. Add liquidity and receive approximately 830,465 LP units.
4. Perform additional swaps.
5. Donate approximately 2.50M SPARTA and 21.63K WBNB directly to the pool.
6. Redeem the LP units against the inflated live balances.
7. Re-add and re-remove liquidity to extract additional value.
8. Sell SPARTA for WBNB.
9. Repay the flash loan.

One reconstructed cycle produced approximately 1,026.71 WBNB of surplus before repetition.

The attack was repeated across several pools.

## Why `sync()` Did Not Save the Pool

The V1 pool had a public `sync()` function that could align recorded balances with actual balances.

The problem was not the absence of a sync primitive. The problem was that the vulnerable liquidity-removal path did not first reconcile the unsolicited donation before calculating the LP redemption.

That allowed the attacker to create:

```text
inflated spot balance
        +
unchanged internal reserve
        +
redemption priced from spot balance
```

which created the value leak.

## Classification

Primary vulnerability:

**LP-share inflation caused by inconsistent reserve and spot-balance accounting.**

Amplification mechanism:

**Flash loan.**

This distinction matters: the flash loan was not the root cause. The underlying smart-contract logic was exploitable without changing the fundamental bug; the flash loan simply supplied temporary capital to make the manipulation large and repeatable.
