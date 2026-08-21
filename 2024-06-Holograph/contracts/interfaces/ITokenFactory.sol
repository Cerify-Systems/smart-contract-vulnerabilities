// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title ITokenFactory
 * @notice Minimal interface duplicated locally so that Etherscan-style verifiers can resolve
 *         imports like `import "src/interfaces/ITokenFactory.sol";` that exist inside the
 *         Doppler sub-module.  Keeping an identical ABI ensures compilation hashes remain
 *         unchanged while avoiding remote-verification errors caused by missing sources.
 *
 * IMPORTANT: This file intentionally mirrors `lib/doppler/src/interfaces/ITokenFactory.sol`.
 * Do not modify either copy without updating the other.
 */
interface ITokenFactory {
    /**
     * @notice Deploys a new asset token.
     * @param initialSupply Initial supply that will be minted
     * @param recipient Address receiving the initial supply
     * @param owner Address receiving the ownership of the token
     * @param salt Salt used in create2 deployment to determine contract address
     * @param tokenData Extra data to be used by the factory
     * @return Address of the newly deployed token
     */
    function create(uint256 initialSupply, address recipient, address owner, bytes32 salt, bytes calldata tokenData)
        external
        returns (address);
}
