# Aftermath

Raft acknowledged the November 10, 2023 security incident after approximately 6.7 million R was minted without corresponding collateral value.

The incident caused R to lose its peg and the protocol's value to fall sharply. Independent reports estimate the loss at approximately $3.3M–$3.6M.

The attacker converted approximately 1,575 ETH from the minted R, but a separate coding mistake in the attacker's extraction contract sent approximately 1,570 ETH to the zero address. The attacker therefore retained only a small amount of the extracted value. 

The incident highlighted two important lessons:

- rebasing/share-based accounting needs strict rounding-direction guarantees;
- protocol indexes must not depend on arbitrary token donations.

Raft subsequently moved toward winding down the affected system and the R token ecosystem. Balancer governance proposals shortly after the incident also moved to remove incentives for R-related pools because of the token's instability. 
