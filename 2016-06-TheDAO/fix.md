# fix.md — What Actually Fixed This


## 1. The code-level fix

always finish updating your own internal state before making any external call or sending any money.This is called the checks-effects-interactions pattern
1. **Checks** — validate the request (permissions, balances, deadlines, etc.)
2. **Effects** — update your own contract's state (balances, flags, counters)
3. **Interactions** — only now, talk to the outside world (send ETH, call another contract)

Applied to The DAO's actual code, the fix would have looked like flipping the order of these lines:

**Vulnerable (actual) order:**
```solidity
Transfer(msg.sender, 0, balances[msg.sender]);
withdrawRewardFor(msg.sender);     
totalSupply -= balances[msg.sender];
balances[msg.sender] = 0;          
paidOut[msg.sender] = 0;
```

**Corrected order (checks-effects-interactions applied):**
```solidity
Transfer(msg.sender, 0, balances[msg.sender]);
totalSupply -= balances[msg.sender];
balances[msg.sender] = 0;         
paidOut[msg.sender] = 0;
withdrawRewardFor(msg.sender);    
```

With this order, if the attacker's contract tried to reenter and call `splitDAO()` again mid-payout, the balance would already read 0, so the recalculated `fundsToBeMoved` would come out to 0 as well. No extra funds. Attack neutralized.


## 2. What actually happened in real life (this was NOT a code patch)

the buggy contract itself was never fixed, because smart contracts on Ethereum are immutable once deployed here's no way to edit code that's already live on-chain. Patching `DAO.sol` was never on the table for the funds already at risk.

Instead, the fix was a protocol-level intervention- a hard fork:

- **June 24, 2016** — a "soft fork" was proposed, which would have simply delayed the attacker's ability to withdraw, without rewriting any balances. This was found to have its own denial-of-service exploit and was abandoned.
- **July 15, 2016** — a community vote (via Carbonvote) gauged sentiment on doing a full hard fork instead.
- **July 20, 2016, block 1,920,000** — the hard fork activated. It performed what's called an **"irregular state change"**: no EVM rules or transaction formats changed, but at that specific block, the balances of a pre-defined list of accounts (The DAO, its extraBalance account, the attacker's child DAO, and related accounts) were moved wholesale into a new `WithdrawDAO` recovery contract. From there, original token holders could call `withdraw()` to reclaim their ETH 1:1.


## Why this was so controversial and why it split Ethereum in two

Rewriting balances outside of normal transaction rules directly conflicted with the principle that blockchain history should be permanent and untouchable ("immutability" is often considered blockchain's core value proposition). A portion of the community rejected the fork on principle and continued mining the original, unaltered chain, this became Ethereum Classic (ETC), where the attacker's funds technically remained under their control. The majority chain that adopted the state change became today's Ethereum (ETH). Roughly 85% of miners moved to the forked chain at the time.
