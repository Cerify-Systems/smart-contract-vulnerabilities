// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IHolographFactory
 * @notice Interface for the HolographFactory contract
 * @dev Defines the core factory functionality for token creation and creator tracking
 * @author Holograph Protocol
 */
interface IHolographFactory {
    /**
     * @notice Check if a user is the creator of a specific token
     * @param token The token address to check
     * @param user The user address to verify as creator
     * @return True if the user is the creator of the token, false otherwise
     */
    function isTokenCreator(address token, address user) external view returns (bool);

    /**
     * @notice Check if a token was deployed by this factory
     * @param token The token address to check
     * @return True if the token was deployed by this factory, false otherwise
     */
    function isDeployedToken(address token) external view returns (bool);

    /**
     * @notice Create a new token with specified parameters
     * @param initialSupply Initial supply of the token
     * @param recipient Address receiving the initial supply
     * @param owner Address receiving ownership of the token
     * @param salt Salt for CREATE2 deployment
     * @param tokenData Encoded token creation parameters
     * @return token Address of the created token
     */
    function create(uint256 initialSupply, address recipient, address owner, bytes32 salt, bytes memory tokenData)
        external
        returns (address token);
}
