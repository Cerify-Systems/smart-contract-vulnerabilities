# summary.md — Level Finance Hack (May 1, 2023)

## What happened
Level Finance is a decentralized perpetuals exchange on BNB Chain. It ran a referral program where traders and the people who referred them earned points each epoch, which could later be claimed as LVL tokens. To make claiming convenient across several past epochs at once, the referral controller contract offered a function called claimMultiple, which accepted an array of epoch numbers and paid out rewards for each one in a single transaction. This function did not properly guarantee that a given epoch number could only be paid out once. An attacker exploited this by repeatedly claiming against epoch numbers that had already been paid, draining 214,000 LVL tokens, which they immediately swapped into 3,345 BNB, worth roughly 1 million dollars at the time.

## When
- **April 18, 2023** — an upgrade to the LevelReferralControllerV2 proxy deployed a new implementation. According to the project's own auditor, Quantstamp, this new implementation differed from the version they had originally audited.
- **May 1, 2023** — the exploit occurred. PeckShield flagged unusual activity, observing multiple calls to claimMultiple over roughly 48 hours draining LVL tokens.
- **Same day** — Level Finance confirmed the exploit publicly, shut down the referral program to stop further draining, and stated that liquidity pools and the DAO treasury were unaffected, since the exploit was isolated to the referral controller contract.

## Where the vulnerable logic lives
The bug was in LevelReferralControllerV2's claimMultiple function, which accepted a list of epoch numbers and paid out rewards for each. The current, publicly available version of this contract only exposes a single epoch claim function, which strongly suggests claimMultiple was removed or reworked after the incident. See contracts/LevelReferralControllerV2.sol for the real, current source and a detailed note on what changed.

## Why it happened
Level's own audits by Quantstamp and Obelisk had reviewed LevelReferralControllerV2 as part of the project's core contracts without finding this issue. According to Quantstamp, the vulnerability was introduced by an upgrade deployed on April 18, after their audit had already been completed, meaning the exploited code was never actually reviewed by either auditor. The underlying mistake was a missing replay check: claimMultiple needed to guarantee that once an epoch's reward had been paid to a user, that same epoch could never be paid out to them again, whether through a second entry in the same array or a later call. That guarantee was not reliably enforced.

## What the fix was
- **Code level fix:** every individual epoch claim, whether processed one at a time or as part of a batch, needs to check whether it has already been paid before paying it again, and needs to record that it has been paid before moving on to the next item, exactly the discipline visible in the current single epoch claim function.
- **What the team actually did:** paused the referral program within hours of detecting the exploit to stop further losses, confirmed the root cause, and deployed a new implementation of the referral contract.

## Why this matters beyond 2023
This incident is a clean example of how convenience features, like letting a user claim several epochs in one transaction instead of one at a time, can quietly reintroduce a class of bug that the simpler, single item version of the same function already correctly guarded against. It also illustrates a governance lesson distinct from the code itself: an audit only covers the exact code it reviewed, and any later upgrade to a proxy's implementation effectively ships new, unaudited code even if the proxy address and the contract's name never change.
