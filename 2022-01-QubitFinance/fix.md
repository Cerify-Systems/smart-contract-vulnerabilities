# Fix

## Immediate fixes Qubit Finance applied

- Paused the bridge and BSC money market to stop further draining once the exploit was
  detected.
- Removed `address(0)` from the whitelisted `tokenAddress` set for the generic ERC-20 deposit
  branch, so the native-ETH sentinel can no longer be reinterpreted as a valid ERC-20 token
  address.
- Replaced the bespoke `SafeToken` transfer helper with OpenZeppelin's audited
  `SafeERC20`/`Address.functionCall`, which reverts when the target address has no contract
  code, rather than silently treating an empty call as a success.
- Split the native-ETH deposit path and the ERC-20 deposit path into two clearly separate
  functions/branches with independent, non-overlapping validation, instead of overloading a
  single `tokenAddress` parameter to mean two different things.

## Recommended structural fixes for bridges generally

1. **Never reuse a sentinel value (like `address(0)`) to mean two different things** in the
   same validation path. If native assets need a marker, use a dedicated enum/flag rather
   than an address that could also collide with "unset" or "invalid."

2. **Always verify contract code exists before treating a low-level `.call()` as an ERC-20
   transfer.** Use OpenZeppelin's `SafeERC20`, or explicitly check `target.code.length > 0`
   (`extcodesize`) before interpreting a successful call as a real token movement.

3. **Don't trust cross-chain events blindly.** The destination chain should reconcile minted
   supply against verifiable proof of locked/escrowed value on the source chain e.g. via
   Merkle proofs, light-client verification, or at minimum sanity-check the claimed amount
   against the source contract's actual token balance change, not just an emitted event.

4. **Independent audits per code path, not just per contract.** The bridge contracts had
   been audited, but the *new* native-ETH deposit feature was added after the audit and
   reused an old function without re-review feature additions to already-audited contracts
   need their own review pass, especially when they touch access-control or validation logic.

5. **Circuit breakers / anomaly detection.** A rate limit or maximum-mint-per-period guard on
   wrapped-asset minting would have capped the blast radius even if the validation bug
   slipped through.

6. **Prefer battle-tested libraries over custom re-implementations** of security-critical
   primitives (transfer helpers, signature verification, access control) the bug here
   existed specifically because Qubit rolled its own `safeTransferFrom` instead of using
   OpenZeppelin's.
