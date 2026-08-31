# Technical Analysis

## Vulnerable Contract

```
contracts/MultiStablesVault.sol
```

## Vulnerable Function

```solidity
function _deposit(...)
```

## Root Cause

The vault converted deposited assets into a common accounting asset before calculating the number of shares to mint.

```solidity
_amount = shareConverter.convert_shares_rate(
    _want,
    address(basedToken),
    _amount
);

if (_amount == 0) {
    _amount = basedConverter.convert_rate(
        _want,
        address(basedToken),
        _amount
    );
}
```

These conversion functions ultimately depended on Curve Finance pool prices.

Because Curve prices could be manipulated using a flash loan, the calculated deposit value became artificially inflated.

The vault then minted shares using

```solidity
_shares = (_amount.mul(totalSupply())).div(_pool);
```

Since `_amount` was already manipulated, the attacker received significantly more vault shares than deserved.

## Attack Flow

1. Borrow funds using an Aave flash loan.
2. Manipulate stablecoin prices in Curve Finance.
3. Deposit manipulated assets into MultiStablesVault.
4. Vault calculates an inflated deposit value.
5. Excess vault shares are minted.
6. Redeem shares for legitimate assets.
7. Repay flash loan.
8. Keep the remaining assets as profit.

## Security Recommendations

- Use TWAP instead of spot prices.
- Use decentralized oracle networks such as Chainlink.
- Reject abnormal price deviations.
- Test protocols against flash loan attacks.
- Avoid relying on instantaneous AMM prices for accounting.