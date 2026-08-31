// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
 * Deus Finance March 2022 incident
 *
 * Exploit-relevant interface/excerpt for the deployed
 * DeiLenderSolidex lending contract.
 *
 * The security-sensitive dependency is:
 *
 *     liquidate()
 *          -> isSolvent()
 *              -> Oracle.getPrice()
 *
 * This file preserves the vulnerable decision boundary rather than
 * pretending that unrelated protocol implementation is necessary
 * to understand the incident.
 */

interface IDeusOracle {
    function getPrice(
        uint256 price,
        uint256 timestamp,
        bytes calldata reqId,
        bytes calldata sigs
    ) external returns (uint256);
}

contract DeiLenderSolidexVulnerable {
    IDeusOracle public oracle;

    /*
     * The real contract maintained debt/collateral state and used the
     * oracle valuation in its solvency checks. The important security
     * property is represented here explicitly: the lending decision
     * trusts the oracle price.
     */
    function isSolvent(
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 price
    ) public view returns (bool) {
        uint256 collateralValue = collateralAmount * price;
        return collateralValue * 80 / 100 >= debtAmount;
    }

    function liquidate(
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 price
    ) external view returns (bool) {
        return !isSolvent(collateralAmount, debtAmount, price);
    }
}
