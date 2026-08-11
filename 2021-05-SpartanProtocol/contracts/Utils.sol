

function calcLiquidityShare(
    uint units,
    address token,
    address pool,
    address member
) external view returns (uint share) {
    uint amount = iBEP20(token).balanceOf(pool);
    uint totalUnits = iBEP20(pool).totalSupply();
    share = amount * units / totalUnits;
}
