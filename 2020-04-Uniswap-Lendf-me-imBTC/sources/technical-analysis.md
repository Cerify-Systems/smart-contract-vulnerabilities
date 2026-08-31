# Technical Analysis

## Vulnerable Contracts

### Uniswap V1

Contract:

```
contracts/uniswap_exchange.vy
```

Relevant Functions:

- `tokenToEthInput()`
- `tokenToEthOutput()`

The exchange contract transferred Ether before completing the ERC-777 token transfer. During the transfer, the ERC-777 callback executed and re-entered the exchange while internal execution was still in progress.

---

### Lendf.me

Contract:

```
contracts/MoneyMarket.sol
```

Relevant Functions:

- `withdraw()`
- `doTransferOut()`

The `withdraw()` function invoked `doTransferOut()` before updating the user's stored balance.

Inside `doTransferOut()`, the protocol executed:

```solidity
token.transfer(to, amount);
```

Since imBTC implemented ERC-777, this transfer triggered callback hooks that allowed recursive execution of `withdraw()` before balances were updated.

---

## Attack Sequence

```
withdraw()

↓

doTransferOut()

↓

token.transfer()

↓

ERC777 callback

↓

withdraw()

↓

balance unchanged

↓

withdraw()

↓

repeat
```

---

## Security Lessons

- Follow the Checks-Effects-Interactions pattern.
- Update protocol state before external calls.
- Assume token transfers may execute arbitrary code.
- Protect critical functions using reentrancy guards.
- Carefully evaluate interactions with newer token standards such as ERC-777.