// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IUniswapV4Initializer
 * @notice Interface for Doppler's UniswapV4Initializer contract
 * @dev Local interface to avoid external dependencies while maintaining compatibility
 */
interface IUniswapV4Initializer {
    /**
     * @notice Event emitted when a new pool/hook is created
     * @param poolOrHook Address of the created pool or hook
     * @param asset Address of the asset token
     * @param numeraire Address of the numeraire token
     */
    event Create(address indexed poolOrHook, address indexed asset, address indexed numeraire);

    /**
     * @notice Get the deployer contract address
     * @return Address of the DopplerDeployer contract
     */
    function deployer() external view returns (address);

    /**
     * @notice Initialize a new Uniswap V4 pool with Doppler hook
     * @param asset Address of the asset token
     * @param numeraire Address of the numeraire token
     * @param numTokensToSell Number of tokens to sell
     * @param salt Salt for CREATE2 deployment
     * @param data Encoded initialization data
     * @return Address of the created hook
     */
    function initialize(address asset, address numeraire, uint256 numTokensToSell, bytes32 salt, bytes calldata data)
        external
        returns (address);

    /**
     * @notice Exit liquidity from a hook
     * @param hook Address of the hook to exit liquidity from
     * @return sqrtPriceX96 Current sqrt price
     * @return token0 Address of token0
     * @return fees0 Fees for token0
     * @return balance0 Balance of token0
     * @return token1 Address of token1
     * @return fees1 Fees for token1
     * @return balance1 Balance of token1
     */
    function exitLiquidity(address hook)
        external
        returns (
            uint160 sqrtPriceX96,
            address token0,
            uint128 fees0,
            uint128 balance0,
            address token1,
            uint128 fees1,
            uint128 balance1
        );
}
