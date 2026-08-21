// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

/*
 * Reconstructed for educational / post-mortem purposes. Represents the BSC-side wrapped
 * token (e.g. qXETH) minted when a Deposit event is observed on the Ethereum side. See
 * exploit.md for how this mint step was reached without any real ETH being deposited.
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title QBridgeToken
/// @notice Minted 1:1 by the bridge relayer/validator upon observing a source-chain
/// Deposit event. VULNERABLE DESIGN: minting is authorized purely by trusting that the
/// relayer correctly verified the source-chain deposit -- there is no on-chain proof
/// (e.g. Merkle proof against a light client) tying a mint to actual locked collateral.
contract QBridgeToken is ERC20, Ownable {
    address public bridgeHandler;

    constructor(string memory name_, string memory symbol_) public ERC20(name_, symbol_) {}

    function setBridgeHandler(address _bridgeHandler) external onlyOwner {
        bridgeHandler = _bridgeHandler;
    }

    /// @notice Called by the relayer-controlled handler after observing a Deposit event
    /// on the source chain. If that event was emitted for a spoofed zero-value deposit
    /// (see QBridgeHandler.sol), this mints fully-collateral-free tokens.
    function mint(address to, uint256 amount) external {
        require(msg.sender == bridgeHandler, "QBridgeToken: caller is not the bridge handler");
        _mint(to, amount);
    }
}
