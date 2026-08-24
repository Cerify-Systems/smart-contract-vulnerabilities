// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title HolographFactoryProxy
 * @notice Minimal proxy contract for HolographFactory using ERC1967 standard
 * @dev This proxy delegates all calls to the HolographFactory implementation
 */
contract HolographFactoryProxy is ERC1967Proxy {
    /// @dev The name field here is used to distinguish this proxy from others for verification purposes
    bytes32 internal immutable name;

    /**
     * @notice Constructor for the HolographFactory proxy
     * @param _implementation Address of the HolographFactory implementation contract
     * @dev Initialize must be called in a separate transaction to maintain same address across chains
     */
    constructor(address _implementation) ERC1967Proxy(_implementation, "") {
        name = keccak256("HolographFactoryProxy");
    }
}
