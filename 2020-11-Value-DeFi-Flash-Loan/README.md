# Value DeFi Flash Loan Attack (2020)

## Summary

The Value DeFi Flash Loan Attack occurred on **November 14, 2020**, resulting in a loss of approximately **$6 million**. The attacker exploited the MultiStablesVault contract by manipulating token prices using a flash loan. Instead of exploiting a low-level Solidity bug such as reentrancy or integer overflow, the attack abused the protocol's economic logic.

The vault trusted prices obtained through its converter contracts, which ultimately relied on Curve Finance pools. By temporarily manipulating these prices within a single transaction, the attacker received more vault shares than they were entitled to and later redeemed them for real assets.

---

## Vulnerability Type

- Flash Loan Attack
- Oracle / Price Manipulation
- Business Logic Vulnerability

---

## Affected Contract

```
contracts/MultiStablesVault.sol
```

Main vulnerable function:

```solidity
function _deposit(...)
```

---

## Root Cause

The vault calculated the number of shares to mint using conversion rates obtained from external converter contracts.

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

These conversion rates ultimately depended on Curve Finance pool prices.

Because Curve prices could be manipulated during a flash loan, the vault accepted an artificially inflated asset value.

Later, the vault minted shares using

```solidity
_shares = (_amount.mul(totalSupply())).div(_pool);
```

Since `_amount` was already manipulated, the attacker received significantly more vault shares than deserved.

---

## Attack Flow

1. Borrowed a large amount of funds using an Aave flash loan.
2. Manipulated stablecoin prices on Curve Finance.
3. Deposited manipulated assets into Value DeFi's MultiStablesVault.
4. The vault trusted the manipulated conversion rate.
5. Excess vault shares were minted.
6. The attacker redeemed those shares for real assets.
7. Repaid the flash loan.
8. Kept the remaining funds as profit.

---

## Impact

- Approximately **$6 million** stolen.
- Vault share calculation became inaccurate.
- Users suffered losses due to the inflated share issuance.

---

## Vulnerable Code

The critical logic exists inside:

```
MultiStablesVault::_deposit()
```

Specifically:

```solidity
_amount = shareConverter.convert_shares_rate(...);

if (_amount == 0) {
    _amount = basedConverter.convert_rate(...);
}

_shares = (_amount.mul(totalSupply())).div(_pool);
```

The contract trusted externally derived conversion rates without protecting against flash-loan-induced price manipulation.

---

## Why This Happened

The protocol assumed that the current Curve pool price represented the true market value.

However, flash loans allow an attacker to temporarily manipulate pool balances within a single transaction.

Because the vault immediately trusted these manipulated prices, it minted an incorrect number of shares.

---

## Mitigation

Possible mitigations include:

- Use Time-Weighted Average Price (TWAP) oracles.
- Use decentralized oracle networks such as Chainlink.
- Validate price deviations before minting shares.
- Introduce slippage protection on deposits.
- Avoid relying on instantaneous AMM spot prices for critical accounting.

---

## Sources

Additional documentation related to this incident is available in the `sources/` directory.

- `incident-report.md` – Summary of the Value DeFi flash loan attack.
- `technical-analysis.md` – Root cause and attack analysis.
- `references.md` – External references, Etherscan links, and research articles.