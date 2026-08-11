# Fix

## 1. Validate every externally supplied pool

The router should not trust a pool address solely because it was encoded in a route. For Uniswap V3, verify that the pool is deployed by the canonical factory and corresponds to the expected token pair and fee tier.

Conceptually:

```solidity
require(
    IUniswapV3Factory(factory).getPool(token0, token1, fee) == pool,
    "Invalid pool"
);
```

The exact implementation should use the protocol's canonical factory and route format.

## 2. Authenticate callback callers independently

The callback should not rely on a storage variable whose value can be influenced by untrusted route input. The caller should be independently verified as a canonical pool. A robust design should derive or verify the expected pool from trusted factory state.

## 3. Treat route bytes as untrusted input

`route` is effectively a user-supplied program describing external calls.

Every decoded:

- pool address
- token address
- recipient
- callback parameter
- fee tier

should be validated according to the intended routing model.

## 4. Avoid unlimited approvals where possible

Sushi's post-mortem highlighted the danger of unlimited approvals and recommended moving away from unlimited approvals where practical.This does not fix the contract vulnerability itself, but it limits the blast radius of future approval bugs.

## 5. Add emergency controls

Sushi's post-mortem also highlighted the importance of pausability for high-activity contracts. RouteProcessor2 was non-upgradeable and could not be paused during the incident, making response substantially harder.

## 6. Security tests

A proper regression suite should include:

1. A malicious route containing a non-canonical pool.
2. A malicious pool attempting to invoke the callback.
3. Callback data containing an arbitrary victim address.
4. A victim with an unlimited token approval.
5. A valid Uniswap V3 pool.
6. A valid route that must continue to work after the new checks.

