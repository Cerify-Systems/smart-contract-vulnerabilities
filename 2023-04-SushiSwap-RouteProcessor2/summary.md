# Summary

## Incident

SushiSwap's `RouteProcessor2` was exploited in April 2023 because the router did not adequately validate the user-controlled route supplied to `processRoute()`.

## Vulnerable contract

Ethereum:

`0x044b75f554b886A065b9567891e45c79542d7357`

Contract:

`RouteProcessor2`

Compiler:

Solidity `0.8.10`

## Root cause

The router trusted a pool address read from the user-controlled route.

The vulnerable path was:

```text
processRoute()
    ↓
processRouteInternal()
    ↓
InputStream(route)
    ↓
swapUniV3()
    ↓
lastCalledPool = attacker-controlled address
    ↓
attacker-controlled pool.swap()
    ↓
uniswapV3SwapCallback()
    ↓
safeTransferFrom(victim, ...)
```

The callback's `msg.sender == lastCalledPool` check was therefore insufficient because the value of `lastCalledPool` itself was attacker-controlled.

## Impact

The attacker could move ERC-20 tokens from wallets that had previously approved RouteProcessor2.

Sushi reported that approximately 1,800 WETH was drained from the first major victim within seconds. CertiK reports approximately $3.3M in total loss. Sushi and HYDN conducted whitehat rescue operations. citeturn0search0turn0search2

## Classification

- Missing input validation
- Callback authorization bypass
- Arbitrary pool / external-call selection
- Approval-draining vulnerability
