// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/*
 * Reconstructed for educational / post-mortem purposes based on public analyses
 * (CertiK, SlowMist, Halborn, rekt.news) of the January 2022 Qubit Finance QBridge
 * exploit. This is NOT a byte-for-byte copy of the deployed bytecode/source — it is a
 * simplified reproduction of the logic that was reported to be vulnerable, intended to
 * illustrate the bug for security research and training. Original contracts (c) 2021
 * Qubit Finance, MIT License.
 */

import "./IQBridgeHandler.sol";

/// @title QBridge
/// @notice Entry point users call to deposit assets that get relayed to another chain.
contract QBridge {
    address public admin;

    // resourceID => handler contract responsible for that resource
    mapping(bytes32 => address) public resourceIDToHandlerAddress;

    event Deposit(
        uint8 destinationChainID,
        bytes32 resourceID,
        uint64 depositNonce,
        address indexed user,
        bytes data
    );

    uint64 public depositCounter;

    modifier onlyAdmin() {
        require(msg.sender == admin, "QBridge: caller is not admin");
        _;
    }

    constructor() public {
        admin = msg.sender;
    }

    function adminSetResource(bytes32 resourceID, address handlerAddress) external onlyAdmin {
        resourceIDToHandlerAddress[resourceID] = handlerAddress;
    }

    /// @notice Users call this to deposit an asset that will be relayed / minted on the
    /// destination chain. `data` is handler-specific ABI-encoded payload (amount, token, etc).
    ///
    /// NOTE: this is the function the attacker called with a spoofed `data` payload and
    /// resourceID mapped to a handler whose `deposit()` implementation is shown in
    /// QBridgeHandler.sol.
    function deposit(uint8 destinationChainID, bytes32 resourceID, bytes calldata data)
        external
        payable
    {
        address handler = resourceIDToHandlerAddress[resourceID];
        require(handler != address(0), "QBridge: resourceID not mapped to a handler");

        IQBridgeHandler(handler).deposit{value: msg.value}(resourceID, msg.sender, data);

        emit Deposit(destinationChainID, resourceID, ++depositCounter, msg.sender, data);
    }
}
