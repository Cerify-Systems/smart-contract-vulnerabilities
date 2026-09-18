# Raydium Protocol Exploit — December 2022

**Privileged Authority / Private-Key Compromise leading to `withdrawPNL` abuse**

---

## Summary

| Field | Detail |
|---|---|
| **Protocol** | Raydium (Solana-based AMM, shares liquidity with the OpenBook/Serum CLOB) |
| **Date** | December 16, 2022, ~2:00 PM UTC |
| **Vulnerability Class** | Privileged authority / private-key compromise (operational security failure) |
| **Root Cause** | Compromise of the "Pool Owner" admin keypair for the AMM V4 program, suspected trojan/remote-access intrusion on the VM/server hosting the key |
| **Exploited Function** | `withdrawPNL` (instruction discriminant `7`), combined with manipulation of `SyncNeedTake` / `need_take_pnl` parameters |
| **Funds Lost** | ~$4.4M (some sources report up to $5.5M including bridged/converted value) |
| **Pools Affected** | 9 pools, including SOL-USDC, SOL-USDT, RAY-USDC, RAY-USDT |
| **Classification** | Raydium later classified this as an **operational key-management failure**, not a program logic/code bug |

---

## Background

Raydium is an Automated Market Maker (AMM) built on Solana that shares liquidity with the OpenBook (formerly Serum) central limit order book. Raydium's AMM V4 program includes a set of **admin-only "upkeep" instructions** that are meant to be invoked only by a designated "Pool Owner" / admin authority. One such instruction, `WithdrawPnl`, is used by Raydium to periodically sweep accrued protocol trading fees (PnL — profit and loss accrued from swap fees) out of the liquidity pools into treasury-controlled accounts.

Because this instruction is privileged, the AMM V4 program does not perform complex validation on *why* it's being called — it simply trusts that the signer holding the hardcoded owner public key is legitimate. This trust boundary is exactly what the attacker exploited.

---

## Attack Flow — Why This Happened

1. **Key compromise.** The attacker gained control of the private key associated with Raydium's hardcoded "Pool Owner" account for the AMM V4 program. Raydium's internal review found no evidence the key was ever shared, transferred, or stored outside the VM where it was originally deployed — pointing instead to a remote compromise of that VM/server (a trojan was suspected as the intrusion vector).
2. **Privileged instruction abuse.** With signing authority over the owner account, the attacker repeatedly invoked the `withdrawPNL` instruction — roughly 1,000 transactions in total — each time draining accumulated trading/protocol fees without depositing any corresponding LP tokens.
3. **Parameter manipulation.** The attacker also manipulated the `SyncNeedTake` parameters, altering `need_take_pnl` values for the quote (`pc`) and base (`coin`) tokens in affected pools. This inflated the amount of "fees" the program believed were owed, allowing additional withdrawals beyond genuinely accrued PnL.
4. **Fund exfiltration.** Stolen assets were partially converted (via Uniswap on Ethereum after bridging) to ETH/USDC and funneled through Tornado Cash. The attacker retained ~109k SOL and ~3.2k stSOL on Solana; the remainder (~$2.5M) was bridged off-chain.

**Core reason this was possible:** The `withdrawPNL` and `SetParams`/`SyncNeedTake` instructions performed *no additional checks* beyond verifying the transaction was signed by the single hardcoded owner pubkey — no multisig requirement, no timelock, no rate limiting, and no on-chain governance gate. Once that one key was compromised, the attacker had unrestricted, repeatable access to a legitimate, "working-as-designed" administrative function.

---

## Real-World Contract & Function References

The Raydium AMM V4 program source is maintained publicly. Note: the current repository reflects the **patched, current state** (post-incident hardware-wallet migration) — it is not a historical snapshot of the exact bytecode deployed on-chain in December 2022.

- **Repository:** https://github.com/raydium-io/raydium-amm
- **On-chain Program ID (Mainnet):** `675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8`

| File | Purpose |
|---|---|
| [`program/src/instruction.rs`](https://github.com/raydium-io/raydium-amm/blob/master/program/src/instruction.rs) | Defines the `AmmInstruction` enum, including `WithdrawPnl` (discriminant `7`) and `SetParams` |
| [`program/src/processor.rs`](https://github.com/raydium-io/raydium-amm/blob/master/program/src/processor.rs) | Contains `process_withdrawpnl`, the PnL accounting logic (`calc_take_pnl`), and the `SetParams`/`SyncNeedTake` handling that was manipulated |
| [`program/src/state.rs`](https://github.com/raydium-io/raydium-amm/blob/master/program/src/state.rs) | Defines `AmmInfo`, `Fees`, and the `need_take_pnl_pc` / `need_take_pnl_coin` fields that were manipulated |
| [`program/src/error.rs`](https://github.com/raydium-io/raydium-amm/blob/master/program/src/error.rs) | Program error definitions |
| [`program/src/lib.rs`](https://github.com/raydium-io/raydium-amm/blob/master/program/src/lib.rs) | Program entrypoint wiring |

**Relevant instruction discriminants (AMM V4):**

```
Initialize2   = 1
Deposit       = 3
Withdraw      = 4
WithdrawPnl   = 7   <-- exploited instruction
SwapBaseIn    = 9
SwapBaseOut   = 11
```

**Example exploit transaction (Solscan):**
https://solscan.io/tx/3iyVofF2PSaVFMzXaUbAwp3J19s43mRg8MuZHwFJs3bHhMCVciuSx5MWnztoXeJfjdTDu2JqWZa7p55LyEiqd8sw

---

## Loss Incurred & Impact

- **Direct financial loss:** ~$4.395M in stolen protocol fees/liquidity across nine affected pools (SOL-USDC, SOL-USDT, RAY-USDC, RAY-USDT, and others involving assets like USDC, ZBC, and UXP). Some estimates including converted/bridged value put the total closer to $5.5M.
- **Fund movement:** ~$2M was bridged to Ethereum (including ~$1.6M in SOL-equivalent value), swapped via Uniswap, and laundered through Tornado Cash. The attacker retained ~109k SOL (~$1.4M) and ~3.2k stSOL (~$44k) on Solana.
- **Market impact:** RAY (Raydium's native token) dropped over 8% shortly after the exploit was disclosed. Raydium's Total Value Locked (TVL) fell more than 27%, from roughly $47.7M to ~$34.7M, as users lost confidence and withdrew liquidity.
- **Ecosystem impact:** The incident renewed scrutiny on Solana DeFi security practices generally, following a string of other Solana-related compromises earlier in 2022.
- **Reputational impact:** Raydium had to publicly disclose the operational failure, pause affected program authority, and rebuild trust through transparency reports and third-party audits.

---

## The Fix

Raydium's remediation was **operational, not a code patch to program logic**, consistent with the root cause being key custody rather than a smart-contract bug:

1. **Immediate containment:** Raydium halted the compromised owner authority on the AMM and farm programs to stop further withdrawals as soon as the exploit was detected.
2. **Authority migration:** The previous (compromised) owner authority was fully revoked. All program admin accounts were migrated to **new hardware-wallet-controlled accounts**, removing the attacker's access entirely.
3. **Third-party review:** Raydium engaged third-party auditors and worked with the broader Solana security community to conduct a full internal security review of the intrusion vector.
4. **Long-term hardening:** The incident pushed Raydium toward stronger operational security practices and, over time, migration toward more heavily audited contract versions (e.g., later CLMM/CPMM programs) with clearer separation of privileged operations.

Notably, **no changes were made to the on-chain business logic** of `withdrawPNL` itself (it still exists and functions as an admin fee-sweep instruction) — the fix was entirely about who is trusted to sign as that admin, and how that key is stored/secured.

---

## Lessons Learned

1. **Privileged keys are a single point of failure.** A single hardcoded owner pubkey with unilateral authority over fee withdrawals and parameter changes is a critical centralization risk — regardless of how well the underlying program logic is written.
2. **Admin functions need guardrails, not just signature checks.** Instructions like `withdrawPNL` and `SetParams` should ideally be protected by multisig authorization, timelocks, withdrawal-rate limits, or on-chain governance — not a single EOA/keypair signature.
3. **Operational security is part of the security surface.** Smart-contract audits alone are insufficient; the infrastructure hosting privileged keys (VMs, servers, CI/CD pipelines) must be treated with the same rigor as the code itself.
4. **Monitoring and anomaly detection matter.** ~1,000 rapid, repeated calls to a single admin instruction is a strong on-chain anomaly signal; real-time monitoring/alerting on privileged-instruction usage patterns could have shortened the exploit window.
5. **Transparent post-mortems build trust.** Raydium's public, detailed incident disclosure (even while root cause was still under investigation) is considered a positive example of crisis communication in DeFi.
6. **Cold storage / hardware wallets for admin keys are essentially mandatory** for any protocol holding meaningful TVL — hot or server-resident admin keys are a high-value target for malware/trojan-based attacks.

---

## References

- Raydium official incident thread: https://twitter.com/RaydiumProtocol (Dec 16–17, 2022)
- CertiK — Raydium Protocol Exploit Incident Analysis: https://www.certik.com/blog/raydium-protocol-exploit-incident-analysis
- HackMD technical writeup ("Raydium Protocol - hacker gains god mode access to steal ~$4.4M"): https://hackmd.io/@prastut/BkbKKIll2
- TokenInsight — "Solana-based DEX Raydium Hacked for Nearly $4.4M due to Private Key Compromised": https://tokeninsight.com/en/news/solana-based-dex-raydium-hacked-for-nearly-4.4m-due-to-private-key-compromised
- Medium — "Raydium Protocol Exploit Analysis | $5.5 million Hacked": https://bartubozkurt35.medium.com/raydium-protocol-exploit-analysis-5-5-million-hacked-5e8b916ff1fa
- DefiTeller — "Raydium shares more details on its recent exploit": https://defiteller.com/raydium-shares-more-details-on-its-recent-exploit
- QuadrigaInitiative case study: https://quadrigainitiative.com/casestudy/raydiumprivatekeycompromised.php
- Raydium AMM source code (GitHub): https://github.com/raydium-io/raydium-amm
- Raydium AMM Bug Bounty / Security scope: https://github.com/raydium-io/raydium-amm/security
- Example exploit transaction (Solscan): https://solscan.io/tx/3iyVofF2PSaVFMzXaUbAwp3J19s43mRg8MuZHwFJs3bHhMCVciuSx5MWnztoXeJfjdTDu2JqWZa7p55LyEiqd8sw

