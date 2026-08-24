// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CreateParams} from "./DopplerStructs.sol";

interface IAirlock {
    enum ModuleState {
        NotWhitelisted,
        TokenFactory,
        GovernanceFactory,
        PoolInitializer,
        LiquidityMigrator
    }

    function owner() external view returns (address);
    function setModuleState(address[] calldata modules, ModuleState[] calldata states) external;
    function getModuleState(address module) external view returns (ModuleState);
    function create(CreateParams calldata params)
        external
        returns (address asset, address pool, address governance, address timelock, address migrationPool);

    function collectIntegratorFees(address to, address token, uint256 amount) external;
}
