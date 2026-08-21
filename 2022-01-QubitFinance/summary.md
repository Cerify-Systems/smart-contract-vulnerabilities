# Summary- Qubit Finance QBridge Exploit

**Date:** January 27–28, 2022
**Loss:** ~$80,000,000 (206,809 BNB)
**Type:** Cross-chain bridge deposit spoofing / broken input validation

Qubit Finance's Ethereum→BSC bridge let a user "deposit" with `tokenAddress = address(0)`
and no attached ETH. Because `address(0)` had been whitelisted to support a later-added
native-ETH deposit feature, and because Qubit's custom transfer helper didn't check that the
target address actually contained contract code, the deposit call succeeded without moving
any real value. The BSC side trusted the resulting event and minted 77,162 qXETH to the
attacker, who then borrowed and swept real assets (BNB, wETH, BTC-B, stablecoins, CAKE,
BUNNY, MDX) out of Qubit's money market, converting everything into ~206,809 BNB.

**Root cause:** sentinel-value collision (`address(0)` meaning both "native ETH" and
"unset/invalid") combined with a non-standard token-transfer helper that doesn't verify the
target has contract code, plus a bridge design that mints on the destination chain based
purely on a source-chain event rather than a verifiable proof of locked funds.

**Fix:** removed `address(0)` from the generic ERC-20 whitelist, migrated to OpenZeppelin's
`SafeERC20`, and separated the native-ETH and ERC-20 deposit code paths.

This ranked as the largest DeFi exploit of 2022 at the time and the 7th largest DeFi hack on
record, per contemporary reporting (CertiK, SlowMist, rekt.news).
