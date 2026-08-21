// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import {ITokenFactory} from "./interfaces/external/doppler/ITokenFactory.sol";
import {IHolographERC20} from "./interfaces/IHolographERC20.sol";

/**
 * @title HolographFactory
 * @notice Custom token factory for deploying HolographERC20 omnichain tokens via Doppler Airlock
 * @dev Implements ITokenFactory interface to integrate with Doppler ecosystem
 * @author Holograph Protocol
 */
contract HolographFactory is ITokenFactory, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /* -------------------------------------------------------------------------- */
    /*                                  Errors                                    */
    /* -------------------------------------------------------------------------- */
    error ZeroAddress();
    error UnauthorizedCaller();
    error InvalidTokenData();
    error SaltAlreadyUsed();

    /* -------------------------------------------------------------------------- */
    /*                                 Storage                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice HolographERC20 implementation address for cloning
     * @dev This is immutable for gas efficiency and security:
     * - Immutable variables are read directly from bytecode (~3 gas) vs storage reads (~100-2100 gas)
     * - Cannot be changed after deployment, preventing accidental updates that could break tokens
     * - Provides clear separation between upgradeable logic and fixed infrastructure
     *
     * When upgrading the factory to support new token versions:
     * 1. Deploy new token implementation
     * 2. Deploy new factory implementation with updated immutable address
     * 3. Upgrade proxy to point to new factory implementation
     */
    address public immutable erc20Implementation;

    /// @notice Authorized Doppler Airlock contracts allowed to call create()
    mapping(address => bool) public authorizedAirlocks;

    /// @notice Mapping to track deployed tokens
    mapping(address => bool) public deployedTokens;

    /// @notice Mapping to track used CREATE2 salts to prevent reuse attacks
    mapping(bytes32 => bool) public usedSalts;

    /// @notice Mapping to track token creators (original transaction initiators)
    mapping(address => address) public tokenCreators;

    /* -------------------------------------------------------------------------- */
    /*                                  Events                                    */
    /* -------------------------------------------------------------------------- */
    /// @notice Emitted when a new HolographERC20 token is deployed
    event TokenDeployed(
        address indexed token,
        string name,
        string symbol,
        uint256 initialSupply,
        address indexed recipient,
        address indexed owner,
        address creator
    );

    /// @notice Emitted when an Airlock is authorized or deauthorized
    event AirlockAuthorizationSet(address indexed airlock, bool authorized);

    /* -------------------------------------------------------------------------- */
    /*                               Constructor                                  */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Constructor sets immutable implementation address
     * @param _erc20Implementation Address of the HolographERC20 implementation for cloning
     * @dev Using immutable for gas efficiency - reads cost ~3 gas vs ~100-2100 for storage
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _erc20Implementation) {
        if (_erc20Implementation == address(0)) revert ZeroAddress();
        erc20Implementation = _erc20Implementation;
        _disableInitializers();
    }

    /**
     * @notice Initialize the HolographFactory
     * @param _owner Owner address
     */
    function initialize(address _owner) external initializer {
        if (_owner == address(0)) revert ZeroAddress();

        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    /* -------------------------------------------------------------------------- */
    /*                            ITokenFactory Implementation                   */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Deploy a new HolographERC20 token via CREATE2
     * @dev Called by authorized Doppler Airlock contracts during token creation
     * @param initialSupply Initial supply of tokens to mint
     * @param recipient Address to receive the initial token supply
     * @param owner Address that will own the deployed token contract
     * @param salt CREATE2 salt for deterministic address generation
     * @param tokenData Encoded token metadata (matches DERC20 format)
     * @return token Address of the newly deployed HolographERC20 token
     */
    function create(uint256 initialSupply, address recipient, address owner, bytes32 salt, bytes calldata tokenData)
        external
        override
        nonReentrant
        returns (address token)
    {
        // Verify caller is an authorized Airlock
        if (!authorizedAirlocks[msg.sender]) revert UnauthorizedCaller();

        // Prevent salt reuse attacks
        if (usedSalts[salt]) revert SaltAlreadyUsed();
        usedSalts[salt] = true;

        // Decode token metadata from tokenData (matches Doppler DERC20 format)
        (
            string memory name,
            string memory symbol,
            uint256 yearlyMintCap,
            uint256 vestingDuration,
            address[] memory recipients,
            uint256[] memory amounts,
            string memory tokenURI
        ) = _decodeTokenData(tokenData);

        // Deploy HolographERC20 clone with CREATE2 for deterministic address
        token = Clones.cloneDeterministic(erc20Implementation, salt);

        // Initialize the clone
        IHolographERC20(token).initialize(
            name, symbol, initialSupply, recipient, owner, yearlyMintCap, vestingDuration, recipients, amounts, tokenURI
        );

        // Track the deployed token
        deployedTokens[token] = true;

        // Track the original creator (transaction initiator)
        tokenCreators[token] = tx.origin;

        emit TokenDeployed(token, name, symbol, initialSupply, recipient, owner, tx.origin);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Token Metadata Decoding                      */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Decode token metadata from tokenData bytes (matches Doppler DERC20 format)
     * @dev Expects tokenData format: (string, string, uint256, uint256, address[], uint256[], string)
     * @param tokenData Encoded token metadata
     * @return name Token name
     * @return symbol Token symbol
     * @return yearlyMintCap Yearly mint cap
     * @return vestingDuration Vesting duration
     * @return recipients Vesting recipients
     * @return amounts Vesting amounts
     * @return tokenURI Token URI
     */
    function _decodeTokenData(bytes calldata tokenData)
        internal
        pure
        returns (
            string memory name,
            string memory symbol,
            uint256 yearlyMintCap,
            uint256 vestingDuration,
            address[] memory recipients,
            uint256[] memory amounts,
            string memory tokenURI
        )
    {
        if (tokenData.length == 0) revert InvalidTokenData();

        (name, symbol, yearlyMintCap, vestingDuration, recipients, amounts, tokenURI) =
            abi.decode(tokenData, (string, string, uint256, uint256, address[], uint256[], string));
    }

    /* -------------------------------------------------------------------------- */
    /*                                Admin Functions                            */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Authorize or deauthorize a Doppler Airlock contract
     * @param airlock Address of the Airlock contract
     * @param authorized Whether the Airlock is authorized to deploy tokens
     */
    function setAirlockAuthorization(address airlock, bool authorized) external onlyOwner {
        if (airlock == address(0)) revert ZeroAddress();
        authorizedAirlocks[airlock] = authorized;
        emit AirlockAuthorizationSet(airlock, authorized);
    }

    /* -------------------------------------------------------------------------- */
    /*                                View Functions                             */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Check if an address is a token deployed by this factory
     * @param token Address to check
     * @return True if the token was deployed by this factory
     */
    function isDeployedToken(address token) external view returns (bool) {
        return deployedTokens[token];
    }

    /**
     * @notice Check if an Airlock is authorized to deploy tokens
     * @param airlock Address to check
     * @return True if the Airlock is authorized
     */
    function isAuthorizedAirlock(address airlock) external view returns (bool) {
        return authorizedAirlocks[airlock];
    }

    /**
     * @notice Check if a user is the creator of a token
     * @param token Address of the token to check
     * @param user Address of the user to check
     * @return True if the user is the creator of the token
     */
    function isTokenCreator(address token, address user) external view returns (bool) {
        return tokenCreators[token] == user;
    }

    /**
     * @notice Authorize contract upgrades (required by UUPS)
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Get the current implementation version
     * @return Version string
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}
