// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * Simplified representation of the malicious BIP-18
 * initialization contract used for vulnerability analysis.
 *
 * This contract is intended for local educational testing.
 */

contract InitBip18 {
    address public recipient;

    event Initialized(address indexed recipient);

    function init(address _recipient) external {
        require(recipient == address(0), "already initialized");

        recipient = _recipient;

        emit Initialized(_recipient);
    }
}