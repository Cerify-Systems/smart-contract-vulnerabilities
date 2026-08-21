# GovernMental — March 2016

**Incident type:** Unbounded loop / gas-limit denial-of-service (Solidity)
**Protocol:** GovernMental (a "last man standing" Ponzi/jackpot game)
**Amount affected:** 1,100 ETH permanently locked (no attacker- self-inflicted design flaw)

## About
GovernMental was a simple game participants sent ETH to join a shared pot. If nobody joined for 12 hours, the last participant to join won the entire pot. To pay out the winner, the contract had to loop through every single participant's record to clear the game's internal arrays before releasing funds. As the participant list grew over the game's run, that loop needed more and more gas to complete. Eventually, the list grew long enough that clearing it required more gas than a single Ethereum block could hold. From that point on, the payout function could never successfully execute again 
1,100 ETH became permanently unreachable, locked in the contract forever.

## The core lesson
Never require an unbounded loop over a growing, user-controlled list before releasing funds. If the list can grow indefinitely, the gas cost of processing it can eventually exceed what's executable in a single transaction permanently bricking the function, with no way to patch a contract that's already deployed and immutable.
