# Official / Primary Analysis

## Eminence Finance Exploit

Date:

29 September 2020

Eminence Finance was an unfinished DeFi gaming ecosystem whose
contracts had been deployed to Ethereum mainnet for testing.

After the contracts became publicly known, users deposited approximately
$15 million into the system.

The contracts were subsequently exploited.

## Root Cause

The exploit involved the interaction between EMN and the secondary
Eminence currencies.

The secondary currencies used EMN as an underlying asset.

The attacker was able to:

1. Obtain DAI through a flash loan.
2. Mint EMN.
3. Use EMN to purchase a secondary currency.
4. Cause EMN to be burned.
5. Sell the remaining EMN back for DAI.
6. Repeat the process.

The bonding-curve accounting did not correctly preserve the economic
relationship between EMN supply and its reserve after the secondary
currency operation.

## Impact

Approximately $15 million was drained.

Approximately $8 million was subsequently returned to a Yearn-associated
deployer address.

## Prevention

The contracts should have been:

- fully tested before mainnet deployment,
- independently audited,
- protected by explicit economic invariants,
- tested against atomic flash-loan transactions,
- designed so secondary-token operations could not create an
  imbalance in the underlying EMN bonding curve.