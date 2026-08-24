// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./external/doppler/ITokenFactory.sol";
import "./IGovernanceFactory.sol";
import "./IPoolInitializer.sol";
import "./ILiquidityMigrator.sol";

/**
 * @notice Self-contained replica of Doppler's CreateParams struct and interfaces.
 * @dev This file contains an exact copy of the CreateParams struct from Doppler's Airlock.sol
 *      along with all required interface definitions. This approach eliminates external dependencies
 *      and ensures seamless contract verification on block explorers without complex import trees.
 *
 *      The struct layout is preserved exactly to maintain ABI compatibility with external
 *      Doppler deployments while making our codebase completely independent.
 *
 *      Original source: https://github.com/whetstoneresearch/doppler/blob/main/src/Airlock.sol
 */
struct CreateParams {
    uint256 initialSupply;
    uint256 numTokensToSell;
    address numeraire;
    ITokenFactory tokenFactory;
    bytes tokenFactoryData;
    IGovernanceFactory governanceFactory;
    bytes governanceFactoryData;
    IPoolInitializer poolInitializer;
    bytes poolInitializerData;
    ILiquidityMigrator liquidityMigrator;
    bytes liquidityMigratorData;
    address integrator;
    bytes32 salt;
}
