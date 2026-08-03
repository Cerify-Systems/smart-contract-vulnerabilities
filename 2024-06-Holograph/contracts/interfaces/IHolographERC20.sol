// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IHolographERC20
 * @notice Interface for HolographERC20 omnichain tokens
 * @dev Extends IERC20 interface with additional Holograph-specific functions
 */
interface IHolographERC20 is IERC20 {
    /* -------------------------------------------------------------------------- */
    /*                                  Events                                    */
    /* -------------------------------------------------------------------------- */
    /// @notice Emitted when tokens are minted to an address
    event TokensMinted(address indexed to, uint256 amount);

    /* -------------------------------------------------------------------------- */
    /*                              Initialization                              */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Initialize the token (for clone pattern)
     * @param name Token name
     * @param symbol Token symbol
     * @param initialSupply Initial supply of the token
     * @param recipient Address receiving the initial supply
     * @param owner Address receiving the ownership of the token
     * @param yearlyMintRate Maximum inflation rate of token in a year
     * @param vestingDuration Duration of the vesting period (in seconds)
     * @param recipients Array of addresses receiving vested tokens
     * @param amounts Array of amounts of tokens to be vested
     * @param tokenURI_ Uniform Resource Identifier (URI)
     */
    function initialize(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address recipient,
        address owner,
        uint256 yearlyMintRate,
        uint256 vestingDuration,
        address[] memory recipients,
        uint256[] memory amounts,
        string memory tokenURI_
    ) external;

    /* -------------------------------------------------------------------------- */
    /*                              Token Functions                              */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Mint new tokens to a specified address
     * @param to Address to receive the minted tokens
     * @param amount Number of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /* -------------------------------------------------------------------------- */
    /*                              ERC20 Metadata                              */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Get the token name
     * @return The token name
     */
    function name() external view returns (string memory);

    /**
     * @notice Get the token symbol
     * @return The token symbol
     */
    function symbol() external view returns (string memory);

    /* -------------------------------------------------------------------------- */
    /*                              DERC20 Features                             */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Get the yearly mint rate
     * @return The yearly mint rate
     */
    function yearlyMintRate() external view returns (uint256);

    /**
     * @notice Get the vesting duration
     * @return The vesting duration
     */
    function vestingDuration() external view returns (uint256);

    /**
     * @notice Get the token URI
     * @return The token URI
     */
    function tokenURI() external view returns (string memory);
}
