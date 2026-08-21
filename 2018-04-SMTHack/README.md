# SmartMesh (SMT) proxyOverflow Incident — April 2018

## Brief Description

In April 2018, the SmartMesh (SMT) ERC-20 token contract was exploited via an integer overflow vulnerability known as **proxyOverflow**, officially tracked as **CVE-2018-10376**. The bug lived in a non-standard `transferProxy()` function that let a relayer submit gasless transfers on behalf of a token holder. By supplying carefully crafted `_fee` and `_value` parameters, an attacker could overflow a `uint256` addition, bypass the balance check entirely, and mint enormous amounts of counterfeit SMT out of thin air.

This was one of two related overflow bugs disclosed within days of each other in April 2018 — the other being **batchOverflow** (CVE-2018-10299), first found in the BeautyChain (BEC) token's `batchTransfer()` function. Both stem from the same root cause: unchecked arithmetic in non-standard ERC-20 extension functions, at a time before SafeMath was universally adopted.

## Total Loss Incurred

- **Counterfeit tokens generated:** ~6.5 × 10^49 SMT (a number vastly larger than any real supply)
- **Counterfeit tokens transferred to exchanges:** 65,300,289 SMT
- **Counterfeit tokens actually traded before exchanges froze balances:** ~16,638,887 SMT
- **Remediation:** SmartMesh Foundation burned an equivalent amount of legitimate SMT to offset the counterfeit tokens that had entered circulation, fixing total supply at **3,141,592,653 SMT**

Because the exploit was caught quickly and major exchanges (Huobi, Gate, OKEX, CEX) suspended SMT deposits/withdrawals within hours, the realized financial damage was contained relative to the theoretical (astronomically large) number of tokens minted.

## Attack Flow

1. `transferProxy()` was designed so a token holder with no ETH for gas could still move tokens: they'd sign an off-chain message authorizing a transfer, and a relayer would submit it on-chain, paying gas themselves in exchange for a token `_fee`.
2. The function needed to validate that the sender's balance covered **both** the transfer amount (`_value`) and the relayer's fee (`_fee`) before moving any tokens.
3. The balance check summed the two attacker-controlled parameters directly: `balances[_from] >= _fee + _value`.
4. Both `_fee` and `_value` are `uint256` values fully controlled by the caller. By choosing values whose sum exceeds the max `uint256` limit, the addition **wraps around** to a very small (or zero) number — similar to an odometer rolling over.
5. With the wrapped sum now tiny, the balance check passed trivially — even for an account holding **zero real SMT**.
6. The function then proceeded to credit the full (massive) `_value` to the recipient and the full `_fee` to the relayer (`msg.sender`), creating tokens that never existed.
7. The attacker moved the newly minted counterfeit tokens toward exchange deposit addresses, attempting to convert them into real value before detection.
8. PeckShield's automated monitoring flagged the anomalous, oversized transfers, and SmartMesh + exchanges intervened to freeze/suspend trading before most of the counterfeit supply could be liquidated.

## Vulnerable Contract

- **Token:** SmartMesh (SMT), Ethereum ERC-20
- **Contract address:** `0x55F93985431Fc9304077687a35A1BA103dC1e081`
- **Vulnerable function:** `transferProxy(address _from, address _to, uint256 _value, uint256 _fee, uint8 _v, bytes32 _r, bytes32 _s)`
- **Faulty line (conceptually):**
  ```solidity
  require(balances[_from] >= _fee + _value);
  ```
  This line is the root cause: it checks the sender's balance against the *sum* of `_fee` and `_value` without first verifying that `_fee + _value` doesn't overflow `uint256`. The individual downstream balance/overflow checks on the *result* of the transfer existed, but the addition of the two input parameters itself was unguarded.

## Explanation of `transferProxy()`

**Purpose:** Standard ERC-20 `transfer()` requires the token holder to pay their own ETH gas. `transferProxy()` was a convenience/non-standard extension allowing a token holder without ETH to still move tokens — they'd sign an authorization off-chain, and a third-party relayer would submit the transaction on their behalf, earning a token-denominated fee for doing so.

**Intended flow:**
1. Verify the signature (`_v`, `_r`, `_s`) proves `_from` authorized this exact transfer.
2. Check `_from` has enough balance to cover both the transfer (`_value`) and the relayer's fee (`_fee`).
3. Deduct `_value + _fee` from `_from`'s balance.
4. Credit `_value` to `_to`.
5. Credit `_fee` to `msg.sender` (the relayer).

**Why it's important:** It's a legitimate and useful gasless-transaction pattern — the same idea underlying later "meta-transaction" and "permit"-style designs. The concept wasn't flawed; the *implementation* was, because it trusted that adding two large user-supplied numbers would never wrap around.

**Why it failed:** Solidity (pre-0.8.0, and without SafeMath) does not revert on arithmetic overflow by default — it silently wraps. Since `_fee` and `_value` were both attacker-controlled, the attacker could pick values that summed to zero (mod 2^256), sailing past the balance check and minting tokens with no real backing.

## References

- SmartMesh (SMT) token contract on Etherscan: https://etherscan.io/token/0x55f93985431fc9304077687a35a1ba103dc1e081
- Verified contract source code: https://etherscan.io/address/0x55f93985431fc9304077687a35a1ba103dc1e081#code
- CVE-2018-10376 (NVD): https://nvd.nist.gov/vuln/detail/CVE-2018-10376
- PeckShield original technical disclosure (proxyOverflow): https://peckshield.medium.com/integer-overflow-i-e-proxyoverflow-bug-found-in-multiple-erc20-smart-contracts-14fecfba2759
- Related bug — batchOverflow, CVE-2018-10299 (BeautyChain BEC): https://peckshield.medium.com/alert-new-batchoverflow-bug-in-multiple-erc20-smart-contracts-cve-2018-10299-511067db6536
- SmartMesh's official incident announcement: https://smartmesh.io/2018/04/25/smartmesh-announcement-on-ethereum-smart-contract-overflow-vulnerability/
- SmartMesh follow-up security update: https://smartmesh.io/2018/04/26/smt-security-update/
- Exploit / proof-of-concept repository: https://github.com/zhanlulab/Exploit_SMT_ProxyOverflow
- Verichains Lab technical analysis of both overflow bugs: https://blog.verichains.io/p/integer-overflow-simple-but-not-easy-9ebbc58bbaa5

## Lessons Learnt

1. **Never trust unchecked arithmetic on user-supplied inputs.** Any addition, subtraction, or multiplication involving external parameters must be checked for overflow/underflow — especially in a language like pre-0.8.0 Solidity where wraparound is silent, not an error.
2. **Use SafeMath (or Solidity ≥0.8.0's built-in overflow checks).** SafeMath was already available and recommended practice by 2018; contracts that skipped it for "custom" functions outside the ERC-20 standard paid the price.
3. **Non-standard extensions to well-audited standards deserve extra scrutiny.** `transfer()` and `transferFrom()` in the base ERC-20 spec were fine — the bug was introduced in a custom convenience function (`transferProxy`) that wasn't part of the audited standard and didn't receive the same level of review.
4. **Validate combined conditions, not just individual ones.** The contract checked balance sufficiency but failed to first validate that the sum of two attacker-controlled values (`_fee + _value`) was itself safe to compute — a reminder to check every intermediate calculation, not just the final comparison.
5. **Monitor on-chain activity for anomalies.** The exploit was caught because PeckShield's automated systems flagged unusually large transfer amounts in near real-time — proactive monitoring can materially reduce the blast radius of an active exploit.
6. **Have an incident response plan with exchanges.** SmartMesh's fast coordination with Huobi, OKEX, Gate, and CEX to freeze deposits/withdrawals prevented a much larger fraction of the counterfeit tokens from being cashed out.
7. **Upgradability and recovery mechanisms matter.** SmartMesh was able to patch the contract and burn counterfeit tokens to restore supply integrity — projects without any redeployment/governance path would have had far fewer options to remediate.
8. **Independent audits catch what internal teams miss.** This class of bug (unchecked arithmetic in copy-pasted or lightly-reviewed helper functions) is exactly what formal audits and static-analysis tools are designed to catch before mainnet deployment.