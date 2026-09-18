# Synthetify DAO Governance Attack — Incident Report

## Overview

| Field | Detail |
|---|---|
| **Date** | October 2023 (attack staged over ~3 months; malicious proposal executed ~Oct 20, 2023) |
| **Target** | Synthetify DAO (Solana-native synthetic-asset DEX, governed via SPL Governance) |
| **Vulnerability Class** | Governance attack / insufficient quorum-security assumptions / social engineering |
| **Loss** | ~$230,000 (USDC, mSOL, stSOL) |
| **Recovered / Remaining** | ~$89,669 remained in the DAO treasury (funds not covered by the malicious proposal) |
| **Funds Destination** | Tornado Cash |
| **Discovered By** | Neodyme (security auditing firm) |

## Description

Synthetify's DAO had gone largely inactive following the FTX collapse in late 2022, which left it with governance-token holders who mostly stopped participating in votes. An attacker exploited this dormancy by acquiring enough of Synthetify's governance token to single-handedly satisfy the DAO's voting quorum — something only possible because real turnout on proposals had dropped to near zero.

The attacker then submitted **ten near-identical proposals** over time. Nine were empty "spam" proposals with no real transactions attached. The tenth looked the same on the surface but contained instructions that transferred the DAO treasury's USDC, mSOL, and stSOL to the attacker's own wallet. Because the DAO had no active reviewers checking proposal contents against their descriptions, and because the preceding spam proposals had conditioned any remaining watchers to disregard yet another look-alike proposal, the malicious proposal passed unopposed and was executed.

## Attack Flow

```
1. RECONNAISSANCE
   Attacker identifies Synthetify DAO as inactive (low voter turnout,
   governance token cheap/liquid enough to acquire a controlling share
   relative to typical participation).

2. POSITION BUILDING
   Attacker acquires enough governance tokens to single-handedly meet
   the DAO's voting quorum/threshold.

3. DESENSITIZATION (SPAM PHASE)
   Attacker submits 9 empty, harmless-looking proposals over ~3 months.
   Purpose:
     a) Test whether anyone is actively monitoring/voting.
     b) Normalize the appearance of proposals from this address, so a
        10th proposal draws no extra scrutiny.

4. THE REAL ATTACK (PROPOSAL #10)
   Attacker submits a proposal that LOOKS like more spam in its
   description/title, but its attached instructions are SPL Token
   Transfer instructions moving USDC, mSOL, and stSOL from the DAO
   treasury to the attacker's wallet.

   Key point: the proposal's description (human-readable text) and its
   instructions (machine-executed payload) are two independent fields.
   Nothing on-chain checks that they match.

5. VOTING
   Attacker votes "Yes" with their own tokens, satisfying quorum alone.
   No other active member reviews the raw instruction data or objects.

6. EXECUTION
   Proposal reaches `Succeeded` state. The governance program's
   ExecuteTransaction instruction runs exactly what was attached at
   creation time — no re-validation, no comparison against the
   description. Treasury funds move to the attacker's wallet.

7. EXFILTRATION
   Stolen funds (~$230K) are routed through Tornado Cash.
```

## Root Cause / The Actual Flaw

This was **not a smart-contract bug** in the traditional sense (no reentrancy, no overflow, no missing check that was later patched). It was a combination of a structural design property and a governance/process weakness:

1. **No binding between proposal description and proposal instructions.**
   SPL Governance stores a proposal's description (free text) and its instructions (structured, executable data) as independent fields. There is no on-chain mechanism verifying the two correspond. A proposer can write anything in the description while attaching arbitrary instructions.

2. **Quorum computed as a fixed % of total token supply, not of "engaged" holders.**
   In an active DAO, meeting quorum requires broad buy-in. In an inactive DAO, typical turnout is a tiny fraction of supply, so the *effective* bar to "win" a vote drops sharply. An attacker only needs enough tokens to beat realistic turnout, not 50%+1 of all tokens.

3. **Human review is the only defense, and it was worn down deliberately.**
   The optional "signatory" review step in SPL Governance is opt-in and depends on active, attentive reviewers. The attacker's spam-proposal phase was specifically designed to erode vigilance before the real payload was submitted.

## Impact

- **Direct financial loss:** ~$230,000 in USDC, mSOL, and stSOL drained from the DAO treasury.
- **Treasury depletion:** Reduced Synthetify DAO's remaining assets to ~$89,669.
- **Reputational/operational impact:** Reinforced the narrative that abandoned/inactive DAOs are high-value, low-effort targets — cited alongside similar incidents (Tornado Cash DAO, May 2023; Indexed Finance DAO, November 2023) as part of a recognized attack pattern against dormant governance systems.
- **Industry impact:** Became a widely referenced case study (Neodyme's "How to Hack a DAO") for governance security across the Solana ecosystem and beyond, informing subsequent DAO security guidance.

## Real-World Contract / Code References

Synthetify's DAO ran on **SPL Governance**, Solana's standard, open-source DAO framework (not a bespoke Synthetify contract). The relevant modules:

- **Repository:** https://github.com/solana-labs/solana-program-library

- **`process_execute_transaction.rs`** — executes an approved proposal's bundled instructions with the Governance PDA as signer. This is the function that carried out the actual treasury transfer, faithfully running whatever was attached at proposal creation:
  https://github.com/solana-labs/solana-program-library/blob/governance-v3.1.0/governance/program/src/processor/process_execute_transaction.rs

- **`process_insert_transaction.rs`** — where a proposal's executable instructions are attached (separately from its description):
  https://github.com/solana-labs/solana-program-library/blob/governance-v3.1.0/governance/program/src/processor/process_insert_transaction.rs

- **`process_cast_vote.rs`** — vote casting and threshold/quorum evaluation, the mechanism the attacker satisfied alone due to low DAO participation:
  https://github.com/solana-labs/solana-program-library/blob/governance-v3.1.0/governance/program/src/processor/process_cast_vote.rs

- **`process_create_proposal.rs`** — where a proposal's description and metadata are set (independently of its instructions):
  https://github.com/solana-labs/solana-program-library/tree/governance-v3.1.0/governance/program/src/processor

> **Note:** None of the above files were patched or altered specifically as a result of this incident. They represent the intended, documented design of SPL Governance. The "flaw" is a structural characteristic (proposals require human review to catch description/instruction mismatches), not a coding defect with a corresponding bugfix commit.

## References

- Blockworks — "DAO on Solana loses $230K after 'attack proposal' goes unnoticed": https://blockworks.co/news/solana-exploit-dao-hacker
- Neodyme's original disclosure thread (X/Twitter): https://twitter.com/Neodyme/status/1715149044794655145
- Neodyme — "How to Hack a DAO" (full technical write-up covering this and related governance attacks): https://neodyme.io/en/blog/how_to_hack_a_dao
- SPL Governance source repository: https://github.com/solana-labs/solana-program-library
- SPL Governance technical overview series (background reading): https://paragraph.xyz/@xentoshi/spl-governance-a-technical-overview

## Fix / Mitigations

There was **no code patch** issued in direct response to this incident — the exploited behavior is inherent to how SPL Governance (and most token-voting DAO frameworks) are designed. Instead, Neodyme's write-up and the broader Solana governance community converged on **process and tooling mitigations**, several of which pre-existed but were underused, and others proposed going forward:

1. **Use signatories actively.** SPL Governance already supports a "signatory" role — trusted reviewers who must sign off before a proposal advances to voting. This feature existed but wasn't being actively used/enforced by Synthetify's dormant DAO. Recommendation: require signatory sign-off before any treasury-moving proposal can proceed.

2. **Cool-off voting periods.** A window near the end of voting during which only "No" votes or vote withdrawals are allowed (no new "Yes" votes), preventing last-second sway attacks and giving more time for review of suspicious proposals.

3. **UI-level scrutiny tools.** Interfaces like Realms already separate proposal description from instruction metadata more clearly than some competitors (e.g., Nouns DAO), but further improvements were recommended: highlighting proposals that call unfamiliar/unverified programs, flagging upgradeable-program calls, and surfacing destination-account details prominently rather than requiring manual instruction decoding.

4. **Proposal bonds / anti-spam measures.** Requiring a bond or stake to submit a proposal raises the cost of the "spam desensitization" phase of this style of attack, and batch-voting/mass-rejection features in the UI reduce the burden on defenders trying to reject many spam proposals at once.

5. **Active monitoring.** DAOs should run (or use) automated alerting for new proposals, large/unusual token deposits, and swayed votes — Neodyme noted no open-source monitoring solution was standard practice at the time.

6. **DAO parameter review for dormant projects.** Projects expecting reduced future engagement (e.g., post-restructuring, winding-down protocols) should proactively raise quorum thresholds, transfer remaining treasury to a multisig, or otherwise reduce the attack surface rather than leaving a token-voting DAO live with no active oversight.

## Lessons Learned

1. **An abandoned or low-activity DAO is not "safe by neglect" — it's a target.** Once real participation drops below the threshold needed to contest a vote, the DAO's quorum defense collapses in practice even though it's unchanged on paper.
2. **Voting on descriptions instead of instructions is a systemic risk**, not unique to Synthetify — the same pattern (backdoored/mismatched proposal) also hit Tornado Cash DAO (May 2023) and was attempted against Indexed Finance DAO (November 2023).
3. **Spam has a psychological function, not just a nuisance function.** Repeated, harmless-looking proposals can be a deliberate softening tactic before a real attack, not just noise to be filtered out.
4. **Treasury security shouldn't rely solely on token-weighted voting** for projects with shrinking or disengaged communities. Multisig custody, elevated thresholds, or winding-down procedures are more appropriate for DAOs past their active lifecycle.
5. **Optional security features (like signatories) only work if actively used.** A framework offering a safeguard is not the same as a DAO actually enforcing it.