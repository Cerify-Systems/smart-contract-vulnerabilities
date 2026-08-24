# Spartan Protocol Exploit — May 2021

## Overview

Spartan Protocol, a DeFi liquidity-pool protocol running on BNB Smart Chain, was exploited on 2 May 2021. The attack abused a flaw in the V1 liquidity-share accounting.

The core accounting problem was an inconsistency between the pool's internal reserve variables and the live ERC-20 balances held by the pool. `removeLiquidityForMember()` obtained the redemption amount through `UTILS.calcLiquidityShare()`, while that calculation used the pool's current token balance. An attacker could therefore increase the live balance by transferring tokens directly to the pool without synchronizing the internal reserves, then redeem LP units against the inflated balance.

A flash loan supplied the capital needed to amplify the manipulation.

## Incident Information

| Field | Value |
|---|---|
| Protocol | Spartan Protocol |
| Network | BNB Smart Chain |
| Incident date | 2 May 2021 |
| Main vulnerable component | V1 `Pool.sol` + `Utils.sol` liquidity-share accounting |
| Main victim pool | SPARTA/WBNB pool |
| Victim pool address | `0x3de669c4F1f167a8aFBc9993E4753b84b576426f` |
| Attacker EOA | `0x3b6e77722e2bbe97c1cfa337b42c0939aeb83671` |
| Attacker contract | `0x288315639c1145f523af6d7a5e4ccf8238cd6a51` |
| Example exploit transaction | `0xb64ae25b0d836c25d115a9368319902c972a0215bd108ae17b1b9617dfb93af8` |
| Flash-loan source | PancakeSwap CAKE/WBNB pair |
| Flash-loan amount | 100,000 WBNB |
| Reported loss | More than $40M by Spartan Protocol's own incident report; independent analyses commonly cite about $30.5M |
| Vulnerability class | LP-share inflation / reserve-vs-balance accounting flaw |

Spartan Protocol itself reported that more than $40M in $SPARTA, BNB and other assets were drained based on prices at the time. Independent technical analyses give lower estimates around $30–30.5M, so this repository deliberately records both figures rather than silently choosing one.

## Root Cause

The V1 pool maintained internal accounting variables such as `baseAmount` and `tokenAmount`, while ERC-20 `balanceOf(pool)` represented the actual tokens sitting at the pool address.

An unsolicited token transfer changes `balanceOf(pool)` but does not automatically change the pool's internal reserves.

The vulnerable redemption path combined two incompatible accounting models:

1. LP deposits were valued using stored pool amounts.
2. LP redemptions were valued using the current ERC-20 balance.
3. `removeLiquidity()` did not first synchronize the donated balance into the stored reserves.

The attacker exploited this asymmetry by donating assets immediately before redemption. The donation inflated the balance used by `calcLiquidityShare()`, so the attacker's LP units were treated as representing a much larger amount of the pool's assets than they should have.

## Attack Flow

At a high level:

1. Borrow 100,000 WBNB from PancakeSwap using a flash loan.
2. Trade WBNB for SPARTA in the target Spartan pool repeatedly to establish the required pool state.
3. Add liquidity using the pool's internal reserve accounting and receive LP units.
4. Perform additional swaps.
5. Transfer a large amount of SPARTA and WBNB directly to the pool. This increases the live ERC-20 balances without updating the stored reserves.
6. Redeem LP units.
7. `calcLiquidityShare()` reads the inflated live balances and calculates an excessive redemption amount.
8. Re-add and re-remove liquidity to capture additional value from the same accounting discrepancy.
9. Swap recovered SPARTA back to WBNB.
10. Repay the flash loan and retain the surplus.

A detailed independent reconstruction reports an example cycle using roughly 2,503,847 SPARTA and 21,632 WBNB as the donation, followed by redemption against the inflated spot balances. One reconstructed cycle yielded approximately 1,026.71 WBNB before repeating the process.

## Vulnerable Components

### `Pool.sol`

The important functions are:

- `removeLiquidityForMember()`
- `removeLiquidity()`
- `sync()`
- internal reserve/balance accounting

The pool's redemption path delegated the share calculation to `UTILS.calcLiquidityShare()` and then decremented internal reserves.

### `Utils.sol`

The important function is:

- `calcLiquidityShare()`

The vulnerable calculation used the token's live `balanceOf(pool)` when determining the value represented by LP units.

This was the critical mismatch: the live balance could be increased by anyone through a normal ERC-20 transfer.

## Why the Flash Loan Mattered

The vulnerability was fundamentally an accounting bug; the flash loan was an amplification mechanism.

The attacker needed substantial temporary capital to manipulate the pool's balances and trading state. PancakeSwap supplied 100,000 WBNB for the attack transaction, allowing the attacker to perform the required sequence without maintaining that capital beforehand.

## Impact

The exploit drained multiple V1 liquidity pools. Spartan Protocol's own incident statement reported more than $40M in assets drained based on prices at the time. Other technical analyses estimate approximately $30–30.5M.

The affected assets included SPARTA, BNB/WBNB and assets from multiple other pools.

## Remediation

The project reviewed the `calcLiquidityShare` attack vector and deployed changes to prevent repeated exploitation. Spartan's May development report states that an update to the Utils contract was deployed after the exploit analysis.

The sound design response is to:

- value LP shares against synchronized/internal reserves;
- never treat unsolicited token transfers as immediately redeemable liquidity;
- use the same accounting basis for minting and burning LP shares;
- reconcile or isolate donations before reserve-dependent operations;
- add invariant and property-based tests around mint/burn accounting.

## Repository Structure

```text
2021-05-SpartanProtocol/
├── contracts/
│   ├── Pool.sol
│   ├── Utils.sol
│   └── SOURCE_NOTES.md
├── README.md
├── summary.md
├── exploit.md
├── fix.md
└── writeups/
    ├── attack-analysis.md
    ├── aftermath.md
    └── sources.md
```

## Source Code Note

The official Spartan Protocol V1–V2 contract repository is publicly available:

https://github.com/spartan-protocol/spartanswap-contracts

The repository contains historical contract directories, including `oldContracts`. Because the exploit-era contracts are historical source material, this package records the exact vulnerable functions and deployment addresses while linking to the upstream repository rather than presenting a reconstructed full source file as if it were the original.

