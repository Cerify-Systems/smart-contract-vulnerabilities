// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/*
 * Reconstructed for educational / post-mortem purposes based on public analyses
 * (CertiK "Qubit Bridge Collapse Exploited to the Tune of $80 Million", SlowMist,
 * Halborn, rekt.news) of the January 2022 Qubit Finance QBridge exploit. This
 * reproduces the *pattern* of the reported vulnerability, not the verbatim deployed
 * bytecode/source. Original contracts (c) 2021 Qubit Finance, MIT License.
 */

import "./IQBridgeHandler.sol";
import "./SafeToken.sol";

/// @title QBridgeHandler
/// @notice Handles per-resource deposit accounting for QBridge. THIS VERSION
/// reproduces the bug that allowed a spoofed zero-value deposit to be treated as valid.
contract QBridgeHandler is IQBridgeHandler {
    using SafeToken for address;

    address public constant ETH = address(0); // native-ETH sentinel

    address public owner;
    address public bridgeAddress;

    // resourceID => token contract address (== ETH sentinel for the native-ETH resource)
    mapping(bytes32 => address) public resourceIDToTokenContractAddress;

    // VULNERABLE: address(0) ends up in this whitelist because it is a legitimate
    // resource (native ETH), but the whitelist is also consulted by the generic
    // ERC-20 branch below, which was never taught to exclude it.
    mapping(address => bool) public contractWhitelist;

    event DepositRecord(bytes32 resourceID, address indexed depositer, uint256 amount);

    modifier onlyBridge() {
        require(msg.sender == bridgeAddress, "QBridgeHandler: caller is not the bridge");
        _;
    }

    constructor(address _bridgeAddress) public {
        owner = msg.sender;
        bridgeAddress = _bridgeAddress;
    }

    function setResource(bytes32 resourceID, address tokenAddress) external {
        require(msg.sender == owner, "QBridgeHandler: not owner");
        resourceIDToTokenContractAddress[resourceID] = tokenAddress;
        contractWhitelist[tokenAddress] = true; // e.g. called once with tokenAddress == ETH (0x0)
    }

    /// @notice Called by QBridge.deposit(). `data` is expected to ABI-encode `amount`.
    ///
    /// THE BUG (mirrors the reported root cause):
    ///  1. `tokenAddress` is looked up from `resourceIDToTokenContractAddress[resourceID]`.
    ///  2. Because `address(0)` (native ETH) is a legitimately whitelisted resource,
    ///     `contractWhitelist[tokenAddress]` is `true` even though this call path is the
    ///     *generic ERC-20* branch, not the native-ETH branch.
    ///  3. `tokenAddress.safeTransferFrom(depositer, address(this), amount)` is called on
    ///     `address(0)`. `SafeToken.safeTransferFrom` (see SafeToken.sol) performs a raw
    ///     `.call()` without first checking `tokenAddress` has contract code, so the call
    ///     "succeeds" trivially (there is no code to run) and is treated as a real transfer.
    ///  4. No ETH was required to be attached (`msg.value` is never checked in this
    ///     branch), so the attacker deposits nothing but is recorded as depositing
    ///     `amount`.
    function deposit(bytes32 resourceID, address depositer, bytes calldata data)
        external
        payable
        override
        onlyBridge
    {
        address tokenAddress = resourceIDToTokenContractAddress[resourceID];
        uint256 amount = abi.decode(data, (uint256));

        // (1) resourceID must be registered -- PASSES: attacker uses the whitelisted
        //     native-ETH resourceID.
        require(tokenAddress != address(0) || contractWhitelist[tokenAddress],
            "QBridgeHandler: token not whitelisted"); // <-- always true for tokenAddress == 0x0

        if (tokenAddress != ETH) {
            // Legacy ERC-20 branch (originally the *only* branch, before native-ETH
            // deposits were added). Uses a custom helper instead of OpenZeppelin's
            // SafeERC20 -- this is the branch the exploit actually falls into for
            // resourceID's whose tokenAddress mapping is address(0).
            tokenAddress.safeTransferFrom(depositer, address(this), amount);
        }
        // else: native ETH branch -- correctly checks msg.value elsewhere in the real
        // contract, but that check is irrelevant here because tokenAddress == ETH takes
        // the *other* branch above only when the mapping is exactly ETH AND resourceID
        // logic treats it natively; the reported bug was that a resourceID could be
        // crafted/registered such that tokenAddress resolved to address(0) while still
        // being routed through the ERC-20 branch's whitelist check instead of a
        // native-ETH-specific one.

        emit DepositRecord(resourceID, depositer, amount);
    }
}
