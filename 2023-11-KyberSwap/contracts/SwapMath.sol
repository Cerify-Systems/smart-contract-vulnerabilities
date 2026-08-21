// SOURCE NOTE: pulled from KyberNetwork/ks-elastic-sc, main branch,
// path contracts/libraries/SwapMath.sol
// (github.com/KyberNetwork/ks-elastic-sc)
//
// This is the exact library identified in KyberSwap's own official
// post-mortem as the source of the November 2023 exploit. The critical
// function is computeSwapStep() near the top of this file.
//
// According to KyberSwap's post-mortem, the documented invariant is:
// "nextSqrtP should not exceed targetSqrtP" (see the @notice comment
// directly above computeSwapStep below). Under a very specific, rare
// combination of inputs, calcReachAmount() and the rounding performed
// inside estimateIncrementalLiquidity() / calcFinalPrice() could combine
// to produce a nextSqrtP that violated this invariant, i.e. nextSqrtP
// ended up on the WRONG SIDE of targetSqrtP. See exploit.md for the full
// walkthrough of how that single broken invariant led to double-counted
// liquidity in the calling Pool.sol contract.

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {MathConstants as C} from './MathConstants.sol';
import {FullMath} from './FullMath.sol';
import {QuadMath} from './QuadMath.sol';
import {SafeCast} from './SafeCast.sol';

/// @title Contains helper functions for swaps
library SwapMath {
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @dev Computes the actual swap input / output amounts to be deducted or added,
    /// the swap fee to be collected and the resulting sqrtP.
    /// @notice nextSqrtP should not exceed targetSqrtP.
    /// @param liquidity active base liquidity + reinvest liquidity
    /// @param currentSqrtP current sqrt price
    /// @param targetSqrtP sqrt price limit the new sqrt price can take
    /// @param feeInFeeUnits swap fee in basis points
    /// @param specifiedAmount the amount remaining to be used for the swap
    /// @param isExactInput true if specifiedAmount refers to input amount, false if specifiedAmount refers to output amount
    /// @param isToken0 true if specifiedAmount is in token0, false if specifiedAmount is in token1
    /// @return usedAmount actual amount to be used for the swap
    /// @return returnedAmount output qty to be accumulated if isExactInput = true, input qty if isExactInput = false
    /// @return deltaL collected swap fee, to be incremented to reinvest liquidity
    /// @return nextSqrtP the new sqrt price after the computed swap step
    //
    // ============================================================
    // THIS IS THE FUNCTION AT THE CENTER OF YOUR TALK. Its own
    // @notice comment states the invariant that was violated:
    // "nextSqrtP should not exceed targetSqrtP." Under a rare,
    // precisely-crafted combination of swap amount and pool state,
    // the calculation below could return a nextSqrtP that crossed
    // PAST targetSqrtP instead of stopping at or before it, due to
    // a rounding error compounding across calcReachAmount(),
    // estimateIncrementalLiquidity(), and calcFinalPrice(). See
    // exploit.md for how that single broken guarantee, three
    // function calls deep, led to double-counted pool liquidity.
    // ============================================================
    function computeSwapStep(
        uint256 liquidity,
        uint160 currentSqrtP,
        uint160 targetSqrtP,
        uint256 feeInFeeUnits,
        int256 specifiedAmount,
        bool isExactInput,
        bool isToken0
    )
        internal
        pure
        returns (
            int256 usedAmount,
            int256 returnedAmount,
            uint256 deltaL,
            uint160 nextSqrtP
        )
    {
        // in the event currentSqrtP == targetSqrtP because of tick movements, return
        // eg. swapped up tick where specified price limit is on an initialised tick
        // then swapping down tick will cause next tick to be the same as the current tick
        if (currentSqrtP == targetSqrtP) return (0, 0, 0, currentSqrtP);
        usedAmount = calcReachAmount(
            liquidity,
            currentSqrtP,
            targetSqrtP,
            feeInFeeUnits,
            isExactInput,
            isToken0
        );

        if (
            (isExactInput && usedAmount > specifiedAmount) ||
            (!isExactInput && usedAmount <= specifiedAmount)
        ) {
            usedAmount = specifiedAmount;
        } else {
            nextSqrtP = targetSqrtP;
        }

        uint256 absDelta = usedAmount >= 0 ? uint256(usedAmount) : usedAmount.revToUint256();
        if (nextSqrtP == 0) {
            deltaL = estimateIncrementalLiquidity(
                absDelta,
                liquidity,
                currentSqrtP,
                feeInFeeUnits,
                isExactInput,
                isToken0
            );
            nextSqrtP = calcFinalPrice(absDelta, liquidity, deltaL, currentSqrtP, isExactInput, isToken0)
                .toUint160();
        } else {
            deltaL = calcIncrementalLiquidity(
                absDelta,
                liquidity,
                currentSqrtP,
                nextSqrtP,
                isExactInput,
                isToken0
            );
        }

        returnedAmount = calcReturnedAmount(
            liquidity,
            currentSqrtP,
            nextSqrtP,
            deltaL,
            isExactInput,
            isToken0
        );
    }

    /// @dev calculates the amount needed to reach targetSqrtP from currentSqrtP
    /// @dev we cast currentSqrtP and targetSqrtP to uint256 as they are multiplied by TWO_FEE_UNITS or feeInFeeUnits
    function calcReachAmount(
        uint256 liquidity,
        uint256 currentSqrtP,
        uint256 targetSqrtP,
        uint256 feeInFeeUnits,
        bool isExactInput,
        bool isToken0
    ) internal pure returns (int256 reachAmount) {
        uint256 absPriceDiff;
        unchecked {
            absPriceDiff = (currentSqrtP >= targetSqrtP)
                ? (currentSqrtP - targetSqrtP)
                : (targetSqrtP - currentSqrtP);
        }
        if (isExactInput) {
            // we round down so that we avoid taking giving away too much for the specified input
            // ie. require less input qty to move ticks
            if (isToken0) {
                uint256 denominator = C.TWO_FEE_UNITS * targetSqrtP - feeInFeeUnits * currentSqrtP;
                uint256 numerator = FullMath.mulDivFloor(
                    liquidity,
                    C.TWO_FEE_UNITS * absPriceDiff,
                    denominator
                );
                reachAmount = FullMath.mulDivFloor(numerator, C.TWO_POW_96, currentSqrtP).toInt256();
            } else {
                uint256 denominator = C.TWO_FEE_UNITS * currentSqrtP - feeInFeeUnits * targetSqrtP;
                uint256 numerator = FullMath.mulDivFloor(
                    liquidity,
                    C.TWO_FEE_UNITS * absPriceDiff,
                    denominator
                );
                reachAmount = FullMath.mulDivFloor(numerator, currentSqrtP, C.TWO_POW_96).toInt256();
            }
        } else {
            if (isToken0) {
                uint256 denominator = C.TWO_FEE_UNITS * currentSqrtP - feeInFeeUnits * targetSqrtP;
                uint256 numerator = denominator - feeInFeeUnits * currentSqrtP;
                numerator = FullMath.mulDivFloor(liquidity << C.RES_96, numerator, denominator);
                reachAmount = (FullMath.mulDivFloor(numerator, absPriceDiff, currentSqrtP) / targetSqrtP)
                    .revToInt256();
            } else {
                uint256 denominator = C.TWO_FEE_UNITS * targetSqrtP - feeInFeeUnits * currentSqrtP;
                uint256 numerator = denominator - feeInFeeUnits * targetSqrtP;
                numerator = FullMath.mulDivFloor(liquidity, numerator, denominator);
                reachAmount = FullMath.mulDivFloor(numerator, absPriceDiff, C.TWO_POW_96).revToInt256();
            }
        }
    }

    /// @dev estimates deltaL, the swap fee to be collected based on amount specified
    /// for the final swap step to be performed,
    /// where the next (temporary) tick will not be crossed
    //
    // This function, along with calcFinalPrice() below, is where the
    // rounding error KyberSwap's post-mortem describes actually occurs.
    function estimateIncrementalLiquidity(
        uint256 absDelta,
        uint256 liquidity,
        uint160 currentSqrtP,
        uint256 feeInFeeUnits,
        bool isExactInput,
        bool isToken0
    ) internal pure returns (uint256 deltaL) {
        if (isExactInput) {
            if (isToken0) {
                deltaL = FullMath.mulDivFloor(
                    currentSqrtP,
                    absDelta * feeInFeeUnits,
                    C.TWO_FEE_UNITS << C.RES_96
                );
            } else {
                deltaL = FullMath.mulDivFloor(
                    C.TWO_POW_96,
                    absDelta * feeInFeeUnits,
                    C.TWO_FEE_UNITS * currentSqrtP
                );
            }
        } else {
            uint256 a = feeInFeeUnits;
            uint256 b = (C.FEE_UNITS - feeInFeeUnits) * liquidity;
            uint256 c = feeInFeeUnits * liquidity * absDelta;
            if (isToken0) {
                b -= FullMath.mulDivFloor(C.FEE_UNITS * absDelta, currentSqrtP, C.TWO_POW_96);
                c = FullMath.mulDivFloor(c, currentSqrtP, C.TWO_POW_96);
            } else {
                b -= FullMath.mulDivFloor(C.FEE_UNITS * absDelta, C.TWO_POW_96, currentSqrtP);
                c = FullMath.mulDivFloor(c, C.TWO_POW_96, currentSqrtP);
            }
            deltaL = QuadMath.getSmallerRootOfQuadEqn(a, b, c);
        }
    }

    /// @dev calculates deltaL, the swap fee to be collected for an intermediate swap step,
    /// where the next (temporary) tick will be crossed
    function calcIncrementalLiquidity(
        uint256 absDelta,
        uint256 liquidity,
        uint160 currentSqrtP,
        uint160 nextSqrtP,
        bool isExactInput,
        bool isToken0
    ) internal pure returns (uint256 deltaL) {
        if (isToken0) {
            uint256 tmp1 = FullMath.mulDivFloor(liquidity, C.TWO_POW_96, currentSqrtP);
            uint256 tmp2 = isExactInput ? tmp1 + absDelta : tmp1 - absDelta;
            uint256 tmp3 = FullMath.mulDivFloor(nextSqrtP, tmp2, C.TWO_POW_96);
            deltaL = (tmp3 > liquidity) ? tmp3 - liquidity : 0;
        } else {
            uint256 tmp1 = FullMath.mulDivFloor(liquidity, currentSqrtP, C.TWO_POW_96);
            uint256 tmp2 = isExactInput ? tmp1 + absDelta : tmp1 - absDelta;
            uint256 tmp3 = FullMath.mulDivFloor(tmp2, C.TWO_POW_96, nextSqrtP);
            deltaL = (tmp3 > liquidity) ? tmp3 - liquidity : 0;
        }
    }

    /// @dev calculates the sqrt price of the final swap step
    /// where the next (temporary) tick will not be crossed
    //
    // This is the other half of where the rounding error lives, per
    // KyberSwap's post-mortem: "a double rounding error that is high
    // enough to make the result price pass the targetSqrtP."
    function calcFinalPrice(
        uint256 absDelta,
        uint256 liquidity,
        uint256 deltaL,
        uint160 currentSqrtP,
        bool isExactInput,
        bool isToken0
    ) internal pure returns (uint256) {
        if (isToken0) {
            uint256 tmp = FullMath.mulDivFloor(absDelta, currentSqrtP, C.TWO_POW_96);
            if (isExactInput) {
                return FullMath.mulDivCeiling(liquidity + deltaL, currentSqrtP, liquidity + tmp);
            } else {
                return FullMath.mulDivFloor(liquidity + deltaL, currentSqrtP, liquidity - tmp);
            }
        } else {
            uint256 tmp = FullMath.mulDivFloor(absDelta, C.TWO_POW_96, currentSqrtP);
            if (isExactInput) {
                return FullMath.mulDivFloor(liquidity + tmp, currentSqrtP, liquidity + deltaL);
            } else {
                return FullMath.mulDivCeiling(liquidity - tmp, currentSqrtP, liquidity + deltaL);
            }
        }
    }

    /// @dev calculates returned output | input tokens in exchange for specified amount
    /// @dev round down when calculating returned output (isExactInput) so we avoid sending too much
    /// @dev round up when calculating returned input (!isExactInput) so we get desired output amount
    function calcReturnedAmount(
        uint256 liquidity,
        uint160 currentSqrtP,
        uint160 nextSqrtP,
        uint256 deltaL,
        bool isExactInput,
        bool isToken0
    ) internal pure returns (int256 returnedAmount) {
        if (isToken0) {
            if (isExactInput) {
                returnedAmount =
                    FullMath.mulDivCeiling(deltaL, nextSqrtP, C.TWO_POW_96).toInt256() +
                    FullMath.mulDivFloor(liquidity, currentSqrtP - nextSqrtP, C.TWO_POW_96).revToInt256();
            } else {
                returnedAmount =
                    FullMath.mulDivCeiling(deltaL, nextSqrtP, C.TWO_POW_96).toInt256() +
                    FullMath.mulDivCeiling(liquidity, nextSqrtP - currentSqrtP, C.TWO_POW_96).toInt256();
            }
        } else {
            returnedAmount =
                FullMath.mulDivCeiling(liquidity + deltaL, C.TWO_POW_96, nextSqrtP).toInt256() +
                FullMath.mulDivFloor(liquidity, C.TWO_POW_96, currentSqrtP).revToInt256();
        }
        if (isExactInput && returnedAmount == 1) {
            returnedAmount = 0;
        }
    }
}
