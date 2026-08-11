# Attack Analysis

## Contract Chain

The exploit is best understood as a cross-contract data flow:

```text
VaultFlipToFlip.getReward()
        |
        v
BunnyMinterV2.mintForV2()
        |
        v
_zapAssetsToBunnyBNB()
        |
        v
WBNB/BUNNY LP tokens
        |
        v
PriceCalculatorBSCV1.valueOfAsset()
        |
        v
PancakeSwap.getReserves()
        |
        v
manipulated WBNB reserve
        |
        v
inflated valueInBNB
        |
        v
amountBunnyToMint()
        |
        v
6.97M BUNNY
```

## Critical Calculation

The documented vulnerable calculation was:

```solidity
if (IPancakePair(asset).token0() == WBNB) {
    valueInBNB =
        amount.mul(reserve0).mul(2)
        .div(IPancakePair(asset).totalSupply());
}
```

The attacker did not need to compromise the oracle contract itself.

Instead, the attacker manipulated the underlying AMM state that the oracle trusted.

## Why the Attack Worked

The calculation assumed that the current WBNB reserve represented a reliable economic valuation.

But during the attack:

```text
flash liquidity
      ↓
large AMM trade
      ↓
WBNB reserve changes
      ↓
LP valuation changes
      ↓
BunnyMinterV2 sees inflated fee value
      ↓
BUNNY mint increases
```

The protocol therefore converted a temporary market manipulation into permanent token issuance.
