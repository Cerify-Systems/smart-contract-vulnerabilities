# Official Postmortem

## Summary

On August 31, 2021, C.R.E.A.M. Finance was exploited through a reentrancy vulnerability involving the AMP token integration.

The attack resulted in the loss of approximately 462,079,976 AMP tokens and 2,804.96 ETH across the main exploit and a smaller copycat attack.

## Root Cause

The AMP token implemented ERC-777 functionality, including a transfer hook that could invoke the recipient's `tokensReceived()` function.

C.R.E.A.M. Finance's lending implementation transferred borrowed tokens before updating the internal borrowing state.

This allowed an attacker to re-enter the borrowing process through the AMP token callback before the original borrow operation had completed its state updates.

The attacker used this reentrancy opportunity to repeatedly borrow assets.

C.R.E.A.M. Finance stated that the AMP token itself was functioning as designed and that the root cause was an error in the way C.R.E.A.M. integrated AMP into its lending protocol.

## Attack Sequence

1. The attacker obtained temporary liquidity through a flash loan.
2. The attacker supplied collateral to the C.R.E.A.M. protocol.
3. The attacker borrowed AMP.
4. AMP's ERC-777 transfer hook triggered `tokensReceived()`.
5. The attacker re-entered another borrowing operation.
6. The original borrow accounting had not yet been updated.
7. The attacker repeated the borrowing process.
8. The borrowed assets were extracted from the protocol.

## Impact

- Approximately 462,079,976 AMP tokens were exploited.
- Approximately 2,804.96 ETH was lost.
- The AMP supply and borrow markets were paused.
- The incident demonstrated the risks of integrating tokens with callback functionality into lending protocols.

## Resolution

C.R.E.A.M. Finance paused the affected AMP supply and borrowing functions after the exploit.

The protocol worked with auditors and technical advisors to develop and deploy a patch before restoring the affected market.

## Source

C.R.E.A.M. Finance Post Mortem: AMP Exploit

https://medium.com/cream-finance/c-r-e-a-m-finance-post-mortem-amp-exploit-6ceb20a630c5