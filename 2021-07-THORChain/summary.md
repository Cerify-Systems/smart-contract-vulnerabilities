# Summary

THORChain is a cross-chain liquidity protocol whose Ethereum integration used a Solidity Router together with an Ethereum Bifrost component that observed Ethereum transactions and events and translated them into THORChain actions.

The July 2021 incidents exposed a dangerous assumption at that boundary. The Router produced events and accepted calls from contracts, while the Bifrost had to decide whether those observations represented genuine deposits and how much value had actually moved. The Bifrost did not fully account for the degree of control an attacker could exercise over the calling contract, transaction value, and emitted events.

The July 9 whitehat discovery was an ERC-777 reentrancy problem in the Router. ERC-777 transfers can invoke recipient hooks. The hook could recursively call the Router's deposit path before the original accounting was fully protected. THORChain states that this allowed the member allowance to be credited more than once and that recursive deposits could continue until the allowance represented the Router's full balance. The team fixed this class of issue by adding a reentrancy guard.

The more serious incidents occurred later in July. In the first exploit, the attacker deployed a wrapper contract in front of the Router. The wrapper received ETH from the external transaction but called the Router with a zero call value and zero deposit amount. The Ethereum Bifrost nevertheless used the outer transaction's `msg.value` as the deposit amount in a code path that had been intended to support vault-transfer events. This caused the Bifrost to treat ETH that had not actually been deposited into the Router as genuine deposited ETH.

THORChain's post-mortem states that the first exploit drained roughly 4,200 ETH and caused approximately $8 million of losses. The attacker could use the falsely reported ETH to perform swaps and manipulate the internal economic state before ultimately extracting the real ETH balance.

The second exploit occurred after the first issue had been patched. The attacker created a fake Router and used the Router's vault-transfer machinery to generate an apparently legitimate deposit event. The fake environment passed `returnVaultAssets()` with a small ETH amount while presenting the fake contract as an Asgard vault. The Router forwarded the ETH and emitted an event that the Bifrost treated as a normal deposit. A malicious memo then caused the system to issue a refund to the attacker. The second incident extracted economically significant ERC-20 assets including ALCX, XRUNE, USDC, SUSHI, YFI, and USDT.

The critical security lesson is that the Router cannot be evaluated independently from the Bifrost. A Solidity contract may emit a perfectly valid event, but an off-chain component must not automatically treat every such event as proof that the expected economic action occurred. The observer needs to validate the actual state transition and the relationship between the caller, router, vault, asset, amount, and transaction value.

This makes THORChain a particularly useful smart-contract security case study. It demonstrates that a vulnerability can exist at a protocol boundary even when the immediate Solidity operation appears legitimate. The security property must hold across the entire pipeline from EVM execution to event parsing to protocol accounting.
