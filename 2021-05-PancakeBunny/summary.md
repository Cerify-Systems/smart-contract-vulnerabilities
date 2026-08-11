# Summary

PancakeBunny was exploited on 19 May 2021 through an oracle/LP-valuation flaw.

The attack involved three relevant PancakeBunny components:

1. `VaultFlipToFlip` — the vault whose `getReward()` path was triggered.
2. `BunnyMinterV2` — processed the performance fee and ultimately minted BUNNY.
3. `PriceCalculatorBSCV1` — calculated the value of PancakeSwap LP tokens using live AMM reserves.

The attacker first deposited a small LP position into `VaultFlipToFlip`. During the exploit transaction, large flash loans were used to manipulate PancakeSwap's WBNB/USDT state and to create an oversized LP position.

When `getReward()` executed, `BunnyMinterV2` processed the performance fee and converted assets into WBNB/BUNNY LP tokens. It then called `PriceCalculatorBSCV1.valueOfAsset()`.

That calculator trusted the current WBNB reserve of the WBNB/BUNNY PancakeSwap pair:

```text
LP value = WBNB reserve × 2 × LP amount / total LP supply
```

Because the reserve had been manipulated, the LP value was massively inflated.

`BunnyMinterV2` then used that inflated value to calculate the BUNNY reward. Approximately 6.97M BUNNY were minted and the attacker extracted approximately 114,631 WBNB.

The flash loan was the amplification mechanism. The underlying vulnerability was the use of a manipulable AMM spot reserve as a trusted oracle for token minting.
