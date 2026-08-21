// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

/*
 * Reconstructed for educational / post-mortem purposes based on public analyses of the
 * January 2022 Qubit Finance QBridge exploit. Illustrates the reported root-cause
 * pattern: a custom "safe transfer" helper that calls .call() directly instead of using
 * OpenZeppelin's Address.functionCall(), and therefore never reverts when the target
 * address contains no contract code (e.g. address(0)).
 */

library SafeToken {
    /// @dev VULNERABLE: does not verify `token` has contract code before calling it.
    /// A call to an address with no code (like address(0)) returns `success = true`
    /// with empty `data`, which this function treats as a valid transfer.
    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd /* transferFrom(address,address,uint256) */, from, to, value)
        );
        require(success, "SafeToken: transferFrom failed");
        require(data.length == 0 || abi.decode(data, (bool)), "SafeToken: transferFrom returned false");
        // BUG: when `token` has no code, `token.call(...)` succeeds trivially with
        // data.length == 0, so both require()s above pass even though nothing happened.
        //
        // The fix is to first assert `token` is a contract, e.g.:
        //   require(token.code.length > 0, "SafeToken: not a contract");
        // or to route through OpenZeppelin's Address.functionCall(), which performs
        // this check internally and reverts with "Address: call to non-contract".
    }
}
