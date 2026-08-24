// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IUniswapV3Pool {
    function liquidity() external view returns (uint128);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}
