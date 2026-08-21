// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IPoolInitializer
 * @notice Mirror of Doppler's pool initializer interface needed for explorer verification.
 */
interface IPoolInitializer {
    function initialize(address asset, address numeraire, uint256 numTokensToSell, bytes32 salt, bytes calldata data)
        external
        returns (address pool);

    function exitLiquidity(address pool)
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

    event Create(address indexed poolOrHook, address indexed asset, address indexed numeraire);
}

interface IHook {
    function migrate(address recipient) external returns (uint256);
}
