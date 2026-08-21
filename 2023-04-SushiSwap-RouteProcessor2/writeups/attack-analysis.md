# Attack Analysis

## Vulnerable Data Flow

```text
processRoute(route)
        |
        v
InputStream.createStream(route)
        |
        v
read pool from route
        |
        v
swapUniV3()
        |
        +--> lastCalledPool = pool
        |
        +--> pool.swap(...)
                    |
                    v
          attacker-controlled pool
                    |
                    v
        uniswapV3SwapCallback()
                    |
                    v
        msg.sender == lastCalledPool
                    |
                    v
        attacker passes check
                    |
                    v
        decode(tokenIn, from)
                    |
                    v
        safeTransferFrom(from, attacker, amount)
```

## Critical Code

The vulnerable pool selection was:

```solidity
address pool = stream.readAddress();
...
lastCalledPool = pool;
IUniswapV3Pool(pool).swap(...);
```

The callback authorization was:

```solidity
require(
    msg.sender == lastCalledPool,
    'RouteProcessor.uniswapV3SwapCallback: call from unknown source'
);
```

The final transfer was:

```solidity
IERC20(tokenIn).safeTransferFrom(
    from,
    msg.sender,
    uint256(amount)
);
```

## Why the Check Failed

At first glance, the callback contained an authorization check.

The problem was **what it trusted**.

The contract trusted:

```text
lastCalledPool
```

But the attacker controlled the value assigned to `lastCalledPool` by supplying a malicious route.

Thus:

```text
"only the expected pool may call back"
```

became:

```text
"only the pool address supplied by the attacker may call back"
```

That converted the callback into an arbitrary token-transfer primitive for wallets that had approved the router.

## External Analysis

BlockSec describes the attack as an unverified external parameter issue: `processRoute()` allowed user control over the call flow and the callback could be reached from an attacker-controlled pool. 

HYDN likewise identifies weak input validation as the root cause and explains that an attacker could impersonate a V3 pool and move tokens from accounts that had approved RouteProcessor2.
