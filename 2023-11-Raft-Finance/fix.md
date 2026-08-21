# Fix

## 1. Do not derive a critical index from a manipulable raw balance

The collateral index should not be calculated from:

```solidity
collateralToken.balanceOf(address(this))
```

when arbitrary transfers/donations can change that balance.

The protocol should distinguish between:

```text
accounted collateral
```

and:

```text
unaccounted token donations
```

Only accounted collateral should influence the index.

## 2. Correct the share-minting rounding direction

The share calculation must not guarantee one share whenever the input is non-zero.The implementation should use a rounding rule consistent with the economic direction of the operation.For collateral deposits, a robust design should ensure that a deposit cannot receive more shares than its exact proportional value.

## 3. Add minimum-share/value checks

The protocol should explicitly handle cases where:

```text
calculated shares < 1
```

rather than silently converting them to one share.

For example, the operation can revert when the amount is too small to mint a meaningful number of shares.

## 4. Bound index changes

An index should not be able to jump by several orders of magnitude in a single update.

A maximum rate-of-change check can provide defense in depth:

```text
newIndex <= oldIndex × permittedGrowthFactor
```

The exact bound must reflect legitimate protocol economics.

## 5. Test donation attacks

The regression suite should include:

1. Direct token donation to the position manager.
2. Liquidation immediately after donation.
3. Extremely large collateral index.
4. 1 wei collateral deposit.
5. Share result below one wei.
6. Repeated tiny deposits.
7. Redemption after repeated deposits.
8. Borrowing using the inflated share balance.

