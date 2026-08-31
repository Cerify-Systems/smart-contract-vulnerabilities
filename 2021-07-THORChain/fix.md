# Fix

THORChain's remediation addressed both the immediate Router issues and the larger architectural problem.

For the July 16 transaction-value exploit, the Bifrost was changed so that the transaction-value override was used only for the specific `vaultTransferEvent` case for which it was required. A generic deposit should not have its amount replaced by the outer transaction's value simply because ETH exists in the transaction.

For the July 22 exploit, the system needed stronger validation of the relationship between Router events and genuine vault actions. The Router should not be treated as a free-form event generator for security-critical accounting. Calls that move vault-controlled assets must be restricted to authorized vaults and expected Router instances.

THORChain also introduced stronger operational controls, including the ability to halt an entire chain and programmatically stop withdrawals. The team subsequently pursued additional audits and security reviews.

For the ERC-777 reentrancy issue, the Router was upgraded with a reentrancy guard. The guard ensures that a token callback cannot recursively execute sensitive Router accounting before the outer operation finishes.

## Secure Design Principles

The first principle is to validate asset movement directly. If a deposit is supposed to credit 100 ETH, the system should verify that 100 ETH actually reached the expected contract rather than relying solely on an event or outer transaction value.

The second principle is to distinguish transaction-level value from internal-call value. A contract called through a wrapper does not automatically have access to the wrapper's `msg.value`. Off-chain systems must preserve this distinction instead of assuming that the outer transaction's value belongs to the inner call.

The third principle is authorization. Vault-management functions should be callable only by the intended vaults or through a tightly controlled migration mechanism. The existence of a valid-looking event is not enough to establish that the caller had authority.

The fourth principle is reentrancy protection. Any function that updates allowances or credits value and then interacts with an external token or contract must either follow strict checks-effects-interactions discipline or use a proven reentrancy guard.

The fifth principle is cross-component testing. The EVM Router and Bifrost should be tested together. Tests should include wrapper contracts, fake Routers, malicious vault addresses, ERC-777 callbacks, non-standard ERC-20 behavior, nested calls, transaction-value mismatches, and malformed memos.

## Architectural Lesson

The biggest remediation is architectural rather than syntactic. THORChain's security model depended on both Solidity contracts and off-chain chain clients. A security review that examines only the Router can miss the actual exploit because the final trust decision was made by the Bifrost.

Cross-chain systems should therefore treat event parsing, transaction decoding, and smart-contract authorization as one security boundary.
