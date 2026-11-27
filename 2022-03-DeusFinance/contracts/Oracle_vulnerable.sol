// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
 * Deus Finance March 2022 incident
 *
 * Exploit-relevant Oracle logic reconstructed from the deployed
 * DeiLenderSolidex oracle implementation documented in contemporary
 * incident analysis.
 *
 * The critical design is that the LP valuation is derived directly
 * from the live USDC/DEI pair reserves.
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IBaseV1Pair {
    function getAmountOut(uint256 amountIn, address tokenIn)
        external
        view
        returns (uint256 amount);
    function totalSupply() external view returns (uint256);
}

contract OracleVulnerable {
    IERC20 public dei;
    IERC20 public usdc;
    IBaseV1Pair public pair;

    /*
     * Vulnerable price calculation.
     *
     * The value of the LP token is derived from the current balances
     * of the underlying pair. Those balances can be temporarily
     * manipulated within a transaction.
     */
    function getOnChainPrice() public view returns (uint256) {
        return
            (
                (
                    dei.balanceOf(address(pair)) *
                        pair.getAmountOut(1e18, address(dei)) *
                        1e12 /
                        1e18
                ) +
                    (usdc.balanceOf(address(pair)) * 1e12)
            ) *
                1e18 /
                pair.totalSupply();
    }
}
