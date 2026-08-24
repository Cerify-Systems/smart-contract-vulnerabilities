# Attack Analysis- The DAO 

Primary sources referenced:
Phil Daian, "Analysis of the DAO Exploit," Hacking, Distributed, June 18, 2016- http://hackingdistributed.com/2016/06/18/analysis-of-the-dao-exploit/
Peter Vessenes, "Deconstructing the DAO Attack: A Brief Code Tour"- http://vessenes.com/deconstructing-thedao-attack-a-brief-code-tour/
Ethereum Foundation blog, "Hard Fork Completed," July 20, 2016- https://blog.ethereum.org/2016/07/20/hard-fork-completed
EIP-779, "Hardfork Meta: DAO Fork" — https://eips.ethereum.org/EIPS/eip-779

## What actually happened,step by step

1. **Setup.** The attacker created a proposal to "split" off part of The DAO into a new child DAO- a completely normal, supported action (proposal #59, publicly titled something like "Lonely, so Lonely"). Splits require a mandatory minimum debate period (1 week), so the attacker had to simply wait it out like any legitimate proposer would.

2. **Triggering the split.** Once the proposal passed, the attacker called `splitDAO()`. This function calculates how much ether and how many reward tokens the caller is entitled to move into the new child DAO, based on the caller's current token balance and only clears that balance at the very end of the function.

3. **The reentrancy hook.** Partway through `splitDAO()`, the code calls `withdrawRewardFor(msg.sender)` "to be nice" and pay out any pending reward. That function in turn calls `ManagedAccount.payOut()`, which sends ether via a low-level `.call.value(...)()`. In Solidity at the time, this call would forward all remaining gas to the recipient and, critically, execute the recipient's fallback function if the recipient was a contract.

4. **The reentry.** The attacker's "recipient" was itself a malicious contract whose fallback function simply called `splitDAO()` again, with the same proposal ID. Because none of the original call's state updates (balance zeroing, totalSupply decrement) had happened yet, the calculation of "how much ether/tokens to move" evaluated to the exact same number again. This let the attacker repeat the fund transfer many times within a single outer transaction.

5. **Getting around the stack depth limit.** The EVM at the time capped call stack depth at 1024 (effectively giving roughly a 30x amplification per outer transaction through recursion alone). To get past this and drain far more, the attacker used the DAO's ordinary token `transfer()` function to shuttle their balance to a second, cooperating malicious contract right as the stack was maxing out since `transfer()` zeroes the sender's balance immediately, this let `splitDAO()`'s own end-of-function balance-clearing logic run "successfully" against an account that had already been drained by transfer, while the second contract picked up where the first left off. This is why blockchain analysis showed two cooperating malicious contracts alternating calls.

6. **Reward-check bypass detail.** The first guard inside `withdrawRewardFor()` (a check comparing expected reward against `paidOut`) could be trivially satisfied by sending a tiny amount of ether directly to the reward account beforehand (its fallback function just accumulated any ether sent to it with no other logic), or even skipped it entirely if the reward account balance was zero, since the inequality being checked would still evaluate to "no problem, pay out" in that case too.

7. **Result:** roughly 3.6 million ETH (about a third of The DAO's ~$150M in locked value at the time) was drained into a "child DAO" the attacker fully controlled, structurally identical to the original DAO and therefore also gated by the same 27+ day waiting period before funds could be withdrawn to a personal wallet which is what gave the Ethereum community a window to respond before the attacker could cash out.

## Why it wasn't caught in review
The individual functions each look reasonable in isolation. `splitDAO()` alone isn't obviously exploitable `withdrawRewardFor()` alone isn't obviously exploitable. The vulnerability only appears when you trace what happens when one function's external call re-enters a different function that hasn't yet finished its own bookkeeping, a pattern security reviewers of the time were not yet systematically checking for. Ironically, a related recursive-call issue was fixed elsewhere in the framework shortly before the attack, but this particular combination was missed.

