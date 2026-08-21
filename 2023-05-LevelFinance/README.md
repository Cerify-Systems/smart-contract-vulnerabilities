# Level Finance Hack — May 1, 2023

**Incident type:** Missing replay protection in a batch claim function (Solidity)
**Protocol:** Level Finance (perpetuals exchange on BNB Chain)
**Vulnerable contract:** LevelReferralControllerV2 (a batch claiming function called claimMultiple, not present in the current patched source)
**Amount stolen:** 214,000 LVL tokens, swapped by the attacker into 3,345 BNB, worth roughly 1 million dollars at the time

##
Level Finance ran a referral rewards program. Traders and their referrers earned reward points each epoch, redeemable for LVL tokens. The referral controller contract offered a claimMultiple function that let a user pass in a list of epoch numbers and claim rewards for all of them in a single transaction, for convenience. That function did not reliably prevent the same epoch number from being processed and paid out more than once, either within one call or across repeated calls. An attacker exploited this by repeatedly calling claimMultiple with epoch numbers that had already been paid out, draining 214,000 LVL tokens before the team noticed and shut the referral program down.

## Folder guide
| File | What it covers |
|---|---|
| `summary.md` | Quick reference: when, where, why, the fix |
| `exploit.md` | Step by step mechanics of the replay style claim exploit |
| `fix.md` | What the team changed and the broader lesson on batch operations |
| `contracts/LevelReferralControllerV2.sol` | The real, current LevelReferralControllerV2.sol from Level Finance's official GitHub repository. Contains a detailed source note explaining this is the post incident version, since it only exposes a single epoch claim function, and describing exactly what the missing claimMultiple function did |
| `writeups/sources-index.md` | Sources referenced, with links |

le