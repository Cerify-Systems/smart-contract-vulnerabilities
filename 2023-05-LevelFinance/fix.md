# fix.md — What Actually Fixed This

## 1. The code level fix
Any batch or looped version of an operation needs to independently re-enforce the exact same safety guarantee the single item version relies on, for every entry in the loop, not just once overall. Concretely for a claim style function processing an array of epoch numbers:
1. For each epoch number in the array, check whether it has already been claimed by this user.
2. If not, calculate the reward and immediately write the updated claimed amount to storage before moving to the next entry in the array.
3. Only after all entries have been processed and their claimed amounts updated, transfer the total combined reward.

The critical detail is step 2 happening inside the loop, for every entry, rather than being skipped or only partially applied. A batch function that reads state at the start, loops through calculations, and only writes updated state once at the very end is at high risk of allowing exactly this kind of duplicate counting.

## 2. What the team actually did in response
- **Immediate:** shut down the referral program as soon as the exploit was detected, stopping further draining within hours.
- **Confirmation:** worked with security firm PeckShield, who published a clear technical breakdown of the claimMultiple bug and the exploiter's on chain activity.
- **Redeployment:** deployed a new implementation of the referral controller. The currently public version of LevelReferralControllerV2 only exposes a single epoch claim function with the correct check, update, transfer ordering, consistent with this fix having been applied.
- **Transparency:** the project's original auditor, Quantstamp, publicly clarified that the exploited code had been introduced after their audit was completed, helping the community understand this was not a case of an audit simply missing an obvious bug.

## Why this incident matters as a teaching example
This incident highlights a governance and process lesson as much as a code level one. An audit is a snapshot of a specific version of a contract's code. Because Level Finance's contracts sat behind an upgradeable proxy, a later implementation upgrade could silently introduce new, unaudited logic under the exact same contract name and address that had previously passed review. Teams operating upgradeable contracts need a process that re-triggers review whenever an implementation changes, not just when a contract is first deployed. On the pure code side, it is also a strong, distinct example of a replay or double claim vulnerability, showing how a safety property that holds for a single operation can quietly break once that operation is generalized into a batch or loop.
