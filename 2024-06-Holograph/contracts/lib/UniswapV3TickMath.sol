// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title UniswapV3TickMath
 * @notice Library for Uniswap V3 tick calculations and range management
 *
 * This library provides reusable functions for tick math operations commonly
 * needed when working with Uniswap V3 pools, especially for single-sided
 * liquidity positioning and range calculations.
 *
 * Key concepts:
 * - Ticks represent discrete price points in Uniswap V3
 * - Tick spacing determines the granularity of price ranges
 * - Different fee tiers have different tick spacings
 * - Single-sided liquidity requires ranges entirely above/below current price
 */
library UniswapV3TickMath {
    /// @notice Minimum tick value across all Uniswap V3 pools
    int24 internal constant MIN_TICK = -887272;
    /// @notice Maximum tick value across all Uniswap V3 pools
    int24 internal constant MAX_TICK = 887272;

    /**
     * @notice Calculate optimal tick range for single-sided liquidity provision
     *
     * Single-sided liquidity must be positioned entirely above or below the current
     * price to ensure only one token is required at mint time:
     * - Token0-only: Range above current price (current < tickLower < tickUpper)
     * - Token1-only: Range below current price (tickLower < tickUpper < current)
     *
     * @param currentTick Current pool tick (from slot0)
     * @param tickSpacing Tick spacing for the fee tier
     * @param isToken0Only True for token0-only, false for token1-only
     * @param rangeSpacings Number of tick spacings for the range width
     * @return tickLower Lower bound of the range
     * @return tickUpper Upper bound of the range
     */
    function calculateSingleSidedRange(int24 currentTick, int24 tickSpacing, bool isToken0Only, int24 rangeSpacings)
        external
        pure
        returns (int24 tickLower, int24 tickUpper)
    {
        // Floor current tick to valid tick spacing
        int24 currentFloored = floorToSpacing(currentTick, tickSpacing);

        // Calculate min/max ticks for this spacing
        int24 minTick = minTickForSpacing(tickSpacing);
        int24 maxTick = maxTickForSpacing(tickSpacing);

        if (isToken0Only) {
            // Token0-only: place range ABOVE current price
            // This ensures current price < tickLower, so only token0 is needed
            tickLower = clampToBounds(add(currentFloored, oneSpacing(tickSpacing)), minTick, maxTick);
            tickUpper = clampToBounds(add(tickLower, mulSpacing(rangeSpacings, tickSpacing)), minTick, maxTick);
        } else {
            // Token1-only: place range BELOW current price
            // This ensures tickUpper < current price, so only token1 is needed
            tickUpper = clampToBounds(add(currentFloored, -oneSpacing(tickSpacing)), minTick, maxTick);
            tickLower = clampToBounds(add(tickUpper, -mulSpacing(rangeSpacings, tickSpacing)), minTick, maxTick);
        }
    }

    /**
     * @notice Calculate balanced liquidity range around current price
     *
     * Balanced liquidity straddles the current price, requiring both tokens
     * at mint time but providing active liquidity immediately.
     *
     * @param currentTick Current pool tick
     * @param tickSpacing Tick spacing for the fee tier
     * @param rangeSpacings Number of tick spacings for range width (each side)
     * @return tickLower Lower bound of the range
     * @return tickUpper Upper bound of the range
     */
    function calculateBalancedRange(int24 currentTick, int24 tickSpacing, int24 rangeSpacings)
        external
        pure
        returns (int24 tickLower, int24 tickUpper)
    {
        int24 currentFloored = floorToSpacing(currentTick, tickSpacing);
        int24 minTick = minTickForSpacing(tickSpacing);
        int24 maxTick = maxTickForSpacing(tickSpacing);

        // Symmetric range around current price
        tickLower = clampToBounds(add(currentFloored, -mulSpacing(rangeSpacings, tickSpacing)), minTick, maxTick);
        tickUpper = clampToBounds(add(currentFloored, mulSpacing(rangeSpacings, tickSpacing)), minTick, maxTick);
    }

    /**
     * @notice Get tick spacing for a given fee tier
     *
     * Uniswap V3 uses different tick spacings for different fee tiers:
     * - 100 (0.01%): 1 tick spacing (maximum precision)
     * - 500 (0.05%): 10 tick spacing
     * - 3000 (0.3%): 60 tick spacing
     * - 10000 (1%): 200 tick spacing
     *
     * @param fee Fee tier in basis points
     * @return Tick spacing for the fee tier
     */
    function tickSpacingForFee(uint24 fee) external pure returns (int24) {
        if (fee == 100) return 1;
        if (fee == 500) return 10;
        if (fee == 3000) return 60;
        if (fee == 10000) return 200;
        revert("unsupported fee tier");
    }

    /**
     * @notice Calculate minimum valid tick for a given tick spacing
     *
     * Valid ticks must be multiples of the tick spacing within the global bounds.
     *
     * @param spacing Tick spacing
     * @return Minimum valid tick for this spacing
     */
    function minTickForSpacing(int24 spacing) public pure returns (int24) {
        // Find the largest multiple of spacing that is <= MIN_TICK
        int24 q = int24((int256(MIN_TICK) / int256(spacing)) * int256(spacing));
        return q;
    }

    /**
     * @notice Calculate maximum valid tick for a given tick spacing
     *
     * @param spacing Tick spacing
     * @return Maximum valid tick for this spacing
     */
    function maxTickForSpacing(int24 spacing) public pure returns (int24) {
        int24 minTick = minTickForSpacing(spacing);
        return int24(-minTick);
    }

    /**
     * @notice Floor a tick to the nearest valid tick for the given spacing
     *
     * @param tick Tick to floor
     * @param spacing Tick spacing
     * @return Floored tick
     */
    function floorToSpacing(int24 tick, int24 spacing) public pure returns (int24) {
        int24 rem = tick % spacing;
        if (rem == 0) return tick;
        if (rem > 0) return tick - rem;
        // rem < 0
        return tick - rem - spacing;
    }

    /**
     * @notice Add two int24 values with overflow protection
     *
     * @param a First value
     * @param b Second value
     * @return Sum of a and b
     */
    function add(int24 a, int24 b) internal pure returns (int24) {
        int256 r = int256(a) + int256(b);
        require(r >= type(int24).min && r <= type(int24).max, "tick add overflow");
        return int24(r);
    }

    /**
     * @notice Multiply tick spacing by count with overflow protection
     *
     * @param count Number of spacings
     * @param spacing Tick spacing
     * @return Product of count and spacing
     */
    function mulSpacing(int24 count, int24 spacing) internal pure returns (int24) {
        int256 r = int256(spacing) * int256(count);
        require(r >= type(int24).min && r <= type(int24).max, "tick mul overflow");
        return int24(r);
    }

    /**
     * @notice Return one unit of tick spacing
     *
     * @param spacing Tick spacing
     * @return The spacing value itself
     */
    function oneSpacing(int24 spacing) internal pure returns (int24) {
        return spacing;
    }

    /**
     * @notice Clamp a tick value to valid bounds
     *
     * @param tick Tick to clamp
     * @param minTick Minimum allowed tick
     * @param maxTick Maximum allowed tick
     * @return Clamped tick value
     */
    function clampToBounds(int24 tick, int24 minTick, int24 maxTick) internal pure returns (int24) {
        if (tick < minTick) return minTick;
        if (tick > maxTick) return maxTick;
        return tick;
    }

    /**
     * @notice Check if a tick is valid for the given spacing
     *
     * @param tick Tick to validate
     * @param spacing Tick spacing
     * @return True if tick is valid for the spacing
     */
    function isValidTick(int24 tick, int24 spacing) external pure returns (bool) {
        return tick % spacing == 0 && tick >= minTickForSpacing(spacing) && tick <= maxTickForSpacing(spacing);
    }

    /**
     * @notice Get the next valid tick above the given tick
     *
     * @param tick Current tick
     * @param spacing Tick spacing
     * @return Next valid tick
     */
    function nextTick(int24 tick, int24 spacing) external pure returns (int24) {
        int24 current = floorToSpacing(tick, spacing);
        int24 maxTick = maxTickForSpacing(spacing);

        if (current == tick && current < maxTick) {
            return add(current, spacing);
        } else {
            return clampToBounds(add(current, spacing), minTickForSpacing(spacing), maxTick);
        }
    }

    /**
     * @notice Get the previous valid tick below the given tick
     *
     * @param tick Current tick
     * @param spacing Tick spacing
     * @return Previous valid tick
     */
    function prevTick(int24 tick, int24 spacing) external pure returns (int24) {
        int24 current = floorToSpacing(tick, spacing);
        int24 minTick = minTickForSpacing(spacing);

        if (current > minTick) {
            return add(current, -spacing);
        } else {
            return minTick;
        }
    }
}
