// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title ILiquidityMigrator
 * @notice Mirror of Doppler's liquidity migrator interface for verification purposes.
 */
interface ILiquidityMigrator {
    function initialize(address asset, address numeraire, bytes calldata data) external returns (address pool);

    function migrate(uint160 sqrtPriceX96, address token0, address token1, address recipient)
        external
        payable
        returns (uint256 liquidity);
}
