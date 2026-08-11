# Summary

## Incident

Spartan Protocol was exploited on 2 May 2021 on BNB Smart Chain. The attacker abused a flaw in V1 liquidity-share accounting to withdraw more underlying assets than their LP position legitimately represented.

Spartan Protocol's own incident report said more than $40M was drained based on prices at the time. Independent technical analyses commonly estimate the loss at approximately $30–30.5M.

## Vulnerability

The V1 `Pool` contract tracked internal reserves (`baseAmount` and `tokenAmount`) separately from the actual ERC-20 balances at the pool address.

The vulnerable redemption flow used `UTILS.calcLiquidityShare()` to calculate how much of each underlying token an LP holder should receive. The calculation relied on the token's live `balanceOf(pool)` rather than the pool's synchronized internal reserves.

Anyone could increase `balanceOf(pool)` by transferring tokens directly to the pool. Because the redemption path did not first synchronize those balances into the internal reserves, the donated assets could be counted in the attacker's redemption.

The protocol therefore valued LP minting and LP burning using different accounting bases.

## Attack

The attacker used a 100,000 WBNB PancakeSwap flash loan to manipulate the SPARTA/WBNB pool and create the conditions needed for the accounting exploit.

The attack sequence consisted of:

1. Flash borrowing WBNB.
2. Multiple swaps to acquire SPARTA and alter the pool state.
3. Adding liquidity to obtain LP units.
4. Making additional swaps.
5. Directly donating SPARTA and WBNB to the pool without calling `sync()`.
6. Redeeming LP units against the inflated live balances.
7. Repeating the add/remove process.
8. Converting SPARTA back to WBNB.
9. Repaying the flash loan.

A detailed reconstruction identifies the principal victim pool as:

`0x3de669c4F1f167a8aFBc9993E4753b84b576426f`

and an example exploit transaction as:

`0xb64ae25b0d836c25d115a9368319902c972a0215bd108ae17b1b9617dfb93af8`

## Key Lesson

The incident was not primarily a flash-loan vulnerability. The flash loan made the attack economically feasible, but the underlying issue was faulty state accounting.
