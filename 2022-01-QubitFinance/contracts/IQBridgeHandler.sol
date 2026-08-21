// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;


interface IQBridgeHandler {
    function deposit(bytes32 resourceID, address depositer, bytes calldata data) external payable;
}
