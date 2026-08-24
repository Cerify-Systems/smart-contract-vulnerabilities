// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IFeeRouter
 * @notice Interface for fee collection and distribution with Doppler integration
 * @dev Handles configurable protocol/treasury split and cross-chain bridging
 * @author Holograph Protocol
 */
interface IFeeRouter {
    /* -------------------------------------------------------------------------- */
    /*                                  Events                                    */
    /* -------------------------------------------------------------------------- */
    event FeesCollected(address indexed airlock, address indexed token, uint256 protocolAmount, uint256 treasuryAmount);
    event TokenBridged(address indexed token, uint256 amount, uint64 nonce);
    event TrustedRemoteSet(uint32 indexed eid, bytes32 remote);
    event TreasuryUpdated(address indexed newTreasury);
    event TrustedAirlockSet(address indexed airlock, bool trusted);

    /* -------------------------------------------------------------------------- */
    /*                                  Errors                                    */
    /* -------------------------------------------------------------------------- */
    error NotEndpoint();
    error UntrustedRemote();
    error ZeroAddress();
    error ZeroAmount();
    error UnauthorizedAirlock();

    /* -------------------------------------------------------------------------- */
    /*                               Functions                                    */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Collect accumulated fees from Doppler Airlock contracts
     * @param airlock Airlock contract holding the fees
     * @param token Token to collect (address(0) for ETH)
     * @param amt Amount to collect from the Airlock
     */
    function collectAirlockFees(address airlock, address token, uint256 amt) external;

    /**
     * @notice Bridge accumulated ETH to remote chain for HLG conversion
     * @param minGas Minimum gas units for lzReceive execution on destination
     * @param minHlg Minimum HLG tokens expected from swap (slippage protection)
     */
    function bridge(uint256 minGas, uint256 minHlg) external;

    /**
     * @notice Bridge accumulated ERC20 tokens to remote chain
     * @param token ERC20 token contract address to bridge
     * @param minGas Minimum gas units for lzReceive execution on destination
     * @param minHlg Minimum HLG tokens expected from swap (slippage protection)
     */
    function bridgeToken(address token, uint256 minGas, uint256 minHlg) external;

    function setTrustedRemote(uint32 eid, bytes32 remote) external;
    function setTreasury(address newTreasury) external;
    function setHolographFee(uint16 newFeeBps) external;
    function getBalances() external view returns (uint256 ethBalance, uint256 hlgBalance);
    function calculateFeeSplit(uint256 amount) external view returns (uint256 protocolFee, uint256 treasuryFee);
    function setTrustedAirlock(address airlock, bool trusted) external;

    /**
     * @notice Check if an Airlock is whitelisted for ETH transfers
     * @param airlock Airlock contract address to check
     * @return Whether the Airlock is trusted
     */
    function trustedAirlocks(address airlock) external view returns (bool);
}
