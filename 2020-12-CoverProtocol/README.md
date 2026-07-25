# Cover Protocol Hack — December 28, 2020

**Incident type:** Memory/storage logic bug leading to infinite token minting (Solidity)
**Protocol:** Cover Protocol (DeFi insurance, formerly "Safe")
**Vulnerable contract:** `Blacksmith.sol` (the shield-mining/rewards contract)
**Estimated loss:** ~$4.4M+ directly stolen; COVER token price crashed ~75-96% within hours
**Status:** Contract address for `Blacksmith.sol` not yet confirmed on Etherscan — verify before final submission (see note in `contracts/README-IMPORTANT.md`)

## TL-DR
Cover Protocol let people stake liquidity tokens (BPT) in a contract called `Blacksmith` to earn COVER token rewards. The `deposit()` function loaded a `pool` struct into a **memory** variable, then called `updatePool()`, which correctly updated the *same* pool's fields in **storage** but because the memory copy is a separate copy, not a live reference, the memory variable stayed stale. The rest of `deposit()` kept using that stale memory value to calculate how many reward tokens a miner should be excluded from (`rewardWriteoff`), producing wildly wrong numbers. Attackers exploited this by manipulating pool state right before depositing, tricking the contract into minting quintillions of COVER tokens out of thin air.


## Vulnerable code
File: `Blacksmith.sol`, function `deposit()`. A `pool` variable is copied into memory (line ~118 in original), then `updatePool()` updates the real storage copy but the memory copy never sees that update, and is still used afterward to calculate `rewardWriteoff`.
