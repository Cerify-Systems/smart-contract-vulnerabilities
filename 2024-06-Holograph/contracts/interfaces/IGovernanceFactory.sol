// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IGovernanceFactory
 * @notice Local mirror of Doppler's governance factory interface so that explorers can resolve
 *         imports like `import "src/interfaces/IGovernanceFactory.sol"` during verification.
 */
interface IGovernanceFactory {
    function create(address asset, bytes calldata governanceData)
        external
        returns (address governance, address timelockController);
}
