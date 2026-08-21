# Summary

**Date:** April 24–25, 2018
**Impact:** Counterfeit SMT tokens worth a nominal ~$5 octodecillion (10^57-scale) minted
across two attack transactions
**Type:** Unchecked integer overflow (CVE-2018-10376, "proxyOverflow")

SmartMesh's `transferProxy()` function, a delegated/gasless-transfer mechanism, checked
`balances[_from] < _feeSmt + _value` before allowing a transfer. Because `_feeSmt` and
`_value` were attacker-controlled `uint256` values with no overflow protection (this predates
Solidity's built-in overflow checks and the project hadn't adopted `SafeMath`), the attacker
chose values that summed to exactly `2^256`, wrapping around to `0`. The check then always
passed regardless of the sender's real balance, and the recipient/relayer addresses were
credited with astronomically large token amounts while the sender's balance was decremented
by the same overflowed (i.e., zero) amount.

This was discovered two days after an essentially identical bug- "batchOverflow"
(CVE-2018-10299) was found in BeautyChain's (BEC) `batchTransfer()` function, both by
PeckShield. The two bugs share a root cause (unchecked `uint256` arithmetic in ERC-20-style
transfer functions) and prompted major exchanges (Huobi, OKEx, Poloniex, HitBTC, Changelly,
and others) to halt ERC-20 deposits and withdrawals broadly while auditing which other listed
tokens shared the same vulnerable pattern.

**Fix:** adopt checked arithmetic (`SafeMath` at the time; Solidity ≥0.8 by default today) for
all balance-affecting computations, and prefer standardized, audited meta-transaction patterns
over bespoke fee/signature/nonce logic.
