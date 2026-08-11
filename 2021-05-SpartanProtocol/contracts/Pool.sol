

function removeLiquidityForMember(address member)
    public
    returns (uint outputBase, uint outputToken)
{
    uint units = balanceOf(address(this));
    outputBase = _DAO().UTILS().calcLiquidityShare(
        units, BASE, address(this), member
    );
    outputToken = _DAO().UTILS().calcLiquidityShare(
        units, TOKEN, address(this), member
    );

    // Stored reserve accounting was updated after the share calculation.
    _decrementPoolBalances(outputBase, outputToken);
    _burn(address(this), units);
    iBEP20(BASE).transfer(member, outputBase);
    iBEP20(TOKEN).transfer(member, outputToken);
}
