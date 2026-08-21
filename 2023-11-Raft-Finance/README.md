# Raft Finance Exploit — November 10, 2023

## Incident

Raft Protocol was exploited on Ethereum on November 10, 2023 through a precision/rounding vulnerability in the collateral-share accounting used by its `rcbETH-c` collateral token.

The attacker first donated cbETH to Raft's `InterestRatePositionManager` and then liquidated a position. Because the collateral index was updated from the manager's raw cbETH balance, the donated cbETH was incorporated into the collateral index.

The attacker then repeatedly supplied only 1 wei of cbETH. The affected collateral token's `mint()` used an upward-rounded `divUp()` operation, so a non-zero amount could produce at least one share even when the mathematically correct result was below one share.

The inflated index made those tiny shares represent a very large amount of collateral. The attacker ultimately used the inflated collateral position to borrow approximately 6.7 million R.

Independent analyses identify `InterestRatePositionManager` at `0x9ab6b21cdf116f611110b048987e58894786c244` as the exploited contract and identify the `rcbETH-c` mint/share calculation as the precision flaw. 

## Vulnerable contracts

### 1. InterestRatePositionManager

```text
0x9AB6b21cDF116f611110b048987E58894786C244
```

Etherscan confirms:

- Contract: `InterestRatePositionManager`
- Solidity: `0.8.19`
- Source: Verified Exact Match
- Optimization: 200,000 runs


### 2. rcbETH-c collateral token

This is the collateral-token implementation containing the vulnerable share-mint calculation:

```solidity
function mint(address to, uint256 amount)
    public
    virtual
    override
    onlyPositionManager
{
    _mint(to, amount.divUp(storedIndex));
}
```

and:

```solidity
function divUp(uint256 a, uint256 b)
    internal
    pure
    returns (uint256)
{
    if (a == 0) {
        return 0;
    } else {
        return (((a * ONE) - 1) / b) + 1;
    }
}
```

Independent technical analyses reproduce this exact logic and identify it as the precision-loss component of the exploit. citeturn4search0turn5search2

## Core vulnerable logic

The index was updated using the collateral token balance held by the `InterestRatePositionManager`:

```solidity
raftCollateralToken.setIndex(
    collateralToken.balanceOf(address(this))
);
```

Therefore, an attacker could donate cbETH directly to the manager before liquidation.

The resulting index became enormously inflated.

Then:

```text
1 wei cbETH
    ↓
divUp(1 wei / huge index)
    ↓
1 wei rcbETH-c
```

instead of zero.

Because the attacker repeated this operation, the resulting rcbETH-c balance became economically significant under the manipulated index.

## Impact

Approximately **6.7 million R** was minted without corresponding legitimate collateral value. The incident is generally reported as approximately **$3.3M–$3.6M** in losses. The attacker ultimately converted roughly 1,575 ETH, but accidentally sent approximately 1,570 ETH to the zero address during the final extraction step. 

