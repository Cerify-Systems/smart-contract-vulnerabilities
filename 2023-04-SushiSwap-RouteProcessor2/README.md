# SushiSwap RouteProcessor2 Exploit- April 2023

## Incident

On 8–9 April 2023, SushiSwap's newly deployed `RouteProcessor2` contract contained a critical input-validation flaw. The contract accepted a user-controlled `route` and could be induced to treat an attacker-controlled contract as a Uniswap V3 pool.

The vulnerable Ethereum deployment was:

`0x044b75f554b886A065b9567891e45c79542d7357`

Etherscan identifies it as **SushiSwap: Route Processor 2** and reports that the address was compromised. Sushi's official post-mortem says the issue affected users who had approved the router. citeturn0search0turn1search4

## Root Cause

`processRoute()` accepted a route generated off-chain without adequately validating that the pool address encoded in the route was an authentic/canonical pool.

The route reached `swapUniV3()`, where:

```solidity
address pool = stream.readAddress();
...
lastCalledPool = pool;
IUniswapV3Pool(pool).swap(...);
```

The callback later checked:

```solidity
require(msg.sender == lastCalledPool, ...);
```

Because `lastCalledPool` had already been set to the attacker-controlled contract, the malicious contract could satisfy the callback check.

The callback decoded `tokenIn` and `from` from attacker-influenced data and could then execute:

```solidity
IERC20(tokenIn).safeTransferFrom(from, msg.sender, amount);
```

## Impact

Sushi's post-mortem reports that approximately **1,800 WETH** was drained from the first major affected user within seconds, while HYDN's rescue effort saved more than **$750,000** of user funds. CertiK reports the total incident loss at approximately **$3.3M**. 

## Contract

The archive includes the **actual RouteProcessor2 Solidity source** from a verified RouteProcessor2 deployment using Solidity `0.8.10`, rather than a placeholder file.

The verified Arbitrum deployment is:

`0xA7caC4207579A179c1069435d032ee0F9F150e5c`

Arbiscan identifies `RouteProcessor2`, compiler `v0.8.10+commit.fc410830`, optimization enabled with 10,000,000 runs, and `File 1 of 12: RouteProcessor2.sol`. The source contains the vulnerable `processRoute`, `swapUniV3`, and `uniswapV3SwapCallback` logic.

## Repository Structure

```text
2023-04-SushiSwap-RouteProcessor2/
├── contracts/
│   ├── RouteProcessor2.sol
├── README.md
├── summary.md
├── exploit.md
├── fix.md
└── writeups/
    ├── attack-analysis.md
    ├── aftermath.md
    └── sources.md
```
