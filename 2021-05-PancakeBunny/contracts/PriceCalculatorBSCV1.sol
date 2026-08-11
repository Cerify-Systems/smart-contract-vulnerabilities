// Exploit-relevant source excerpt
// Deployed PriceCalculatorBSCV1:
// 0x81ef2bc1e02fee5414e46accc6ae14d833eebba0
//
// Technical reconstruction:
// https://cmichel.io/bsc-pancake-bunny-exploit-post-mortem/

pragma solidity ^0.6.12;

interface IPancakePair {
    function symbol() external view returns (string memory);
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint);
}

contract PriceCalculatorBSCV1_ExploitExcerpt {
    address public constant WBNB =
        0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    function valueOfAsset(address asset, uint amount)
        public
        view
        returns (uint valueInBNB, uint valueInUSD)
    {
        if (
            keccak256(
                abi.encodePacked(IPancakePair(asset).symbol())
            ) == keccak256("Cake-LP")
        ) {
            (
                uint reserve0,
                uint reserve1,

            ) = IPancakePair(asset).getReserves();

            if (IPancakePair(asset).token0() == WBNB) {
                valueInBNB =
                    amount.mul(reserve0).mul(2)
                    .div(IPancakePair(asset).totalSupply());
            } else if (IPancakePair(asset).token1() == WBNB) {
                valueInBNB =
                    amount.mul(reserve1).mul(2)
                    .div(IPancakePair(asset).totalSupply());
            }
        }
    }
}
