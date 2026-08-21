# Aftermath — The Hard Fork and the ETH/ETC Split

Sources: Ethereum Foundation blog ("Hard Fork Completed," July 20 2016), Ethereum Classic blog, EIP-779.

## Timeline
- **June 17, 2016** — attack executed; ~3.6M ETH drained into a child DAO.
- **June 24, 2016** — a "soft fork" proposal was floated to delay withdrawals from the attacker's child DAO while the community decided what to do, buying time without rewriting any balances.
- **June 28, 2016** — developers found the soft-fork approach itself had a denial-of-service exploit, and abandoned it in favor of a hard fork instead.

## What the hard fork actually did
Unusually, this hard fork didn't change any EVM opcodes, transaction formats, or protocol rules. Instead, it performed what the community called an "irregular state change" at block 1,920,000, the balances of a specific, pre-enumerated list of accounts (The DAO itself, its extraBalance account, the attacker's child DAO, and related accounts) were moved wholesale into a new `WithdrawDAO` recovery contract. From there, original DAO token holders could call a `withdraw()` function to reclaim their ether 1:1.

This was fundamentally a judgment call by the Ethereum developer community and mining majority not a smart-contract bug fix, but a protocol-level decision to reverse the effects of the theft.

## The controversy and the split
Rewriting balances outside of normal transaction rules directly conflicted with the principle that blockchain history should be immutable. A portion of the community rejected the fork on principle, continuing to mine the original, unaltered chain this became Ethereum Classic (ETC), where the DAO attacker's funds remained in their control. The majority chain that adopted the state change is what's now called Ethereum (ETH).

