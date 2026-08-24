# PancakeBunny Exploit — May 2021

## Incident

PancakeBunny was exploited on 19 May 2021 on BNB Smart Chain. The attack abused PancakeBunny's LP valuation and reward-minting flow.

The relevant deployed contracts are:

- `VaultFlipToFlip`
  - `0xd415e6caa8af7cc17b7abd872a42d5f2c90838ea`
- `BunnyMinterV2`
  - `0x819eea71d3f93bb604816f1797d4828c90219b5d`
- `PriceCalculatorBSCV1`
  - `0x81ef2bc1e02fee5414e46accc6ae14d833eebba0`

BscScan marks the first two deployed contracts as verified exact-match Solidity source. The exploit analysis identifies `PriceCalculatorBSCV1.valueOfAsset()` as the critical price-calculation flaw.

## Correct Contract Relationship

```text
VaultFlipToFlip.getReward()
        |
        v
BunnyMinterV2.mintForV2()
        |
        +--> _zapAssetsToBunnyBNB(...)
        |
        +--> PriceCalculatorBSCV1.valueOfAsset(...)
        |
        v
inflated LP valuation
        |
        v
amountBunnyToMint(...)
        |
        v
excess BUNNY minted
```

The exploit therefore should not be represented by `PriceCalculatorBSCV1` alone. This package includes the three relevant contract records and the exploit-relevant source excerpts.

## Root Cause

The critical flaw was the use of a manipulable PancakeSwap LP spot reserve to value LP tokens.

`PriceCalculatorBSCV1.valueOfAsset()` used the WBNB reserve and LP total supply to calculate an LP's BNB value:

```solidity
valueInBNB =
    amount.mul(reserve0).mul(2)
    .div(IPancakePair(asset).totalSupply());
```

or the equivalent `reserve1` branch when WBNB was token1.

The attacker manipulated PancakeSwap reserves with flash-loaned capital. The manipulated reserve was then used by the Bunny reward-minting path, causing an inflated LP valuation and an excessive BUNNY mint.

## Impact

Independent technical reconstruction reports approximately:

- 6.97 million BUNNY minted
- 114,631 WBNB extracted
- approximately $30 million at the time of the technical reconstruction

Other contemporary reports described the incident as a $40M–$45M event because of the market impact and valuation methodology.

## Source Integrity

The `contracts/` directory contains **exploit-relevant source excerpts**, not fabricated "complete" contracts.

The exact historical verified source is linked in `contracts/SOURCE_NOTES.md` and can be opened directly on BscScan. This distinction is intentional: the deployed contracts are verified as multi-file Solidity Standard JSON source bundles, and reproducing only a subset as though it were the entire verified bundle would be misleading.

For Cerify's "exact vulnerable contract versions" requirement, use the BscScan verified source pages linked in the package and preserve the full Standard JSON bundle when importing the complete source.

## Repository Structure

```text
2021-05-PancakeBunny/
├── contracts/
│   ├── BunnyMinterV2.sol
│   ├── PriceCalculatorBSCV1.sol
├── README.md
├── summary.md
├── exploit.md
├── fix.md
└── writeups/
    ├── attack-analysis.md
    ├── aftermath.md
    ├── transactions.md
    └── sources.md
```
