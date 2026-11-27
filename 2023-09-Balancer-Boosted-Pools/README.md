# Balancer Boosted Pools — September 2023
## Incident
Balancer's September 2023 disclosure concerned a critical vulnerability affecting Boosted Pools that used vulnerable Linear Pool implementations. The primary exploit-relevant contract family was `ERC4626LinearPool`. A rounding weakness in ERC-4626 Linear Pool accounting could be combined with Balancer flash swaps to manipulate the effective rate and extract value.
## Vulnerable contract
The main contract is `ERC4626LinearPool`, inherited from Balancer's `LinearPool`. The historical Balancer deployment repository identifies ERC-4626 Linear Pool deployment families including `20230206-erc4626-linear-pool-v3` and `20230409-erc4626-linear-pool-v4`. The exploit-relevant implementation is included in `contracts/ERC4626LinearPool.sol`.
## Impact
Immunefi reported that all value in affected Boosted Pools could have been drained and that this represented approximately 20% of Balancer's roughly $1 billion TVL at the time. Balancer rapidly mitigated the issue, most funds at risk were withdrawn within 48 hours, and a $1,000,000 USDC whitehat bounty was paid.
## Contents
`contracts/ERC4626LinearPool.sol` contains the exploit-relevant Solidity implementation. `summary.md` gives the overview. `exploit.md` explains the vulnerability. `fix.md` documents remediation. `writeups/aftermath.md` records the response.
