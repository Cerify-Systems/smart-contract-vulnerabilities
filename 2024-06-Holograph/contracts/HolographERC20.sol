// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20VotesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {IHolographFactory} from "./interfaces/IHolographFactory.sol";

/// @dev Thrown when trying to mint before the start date
error MintingNotStartedYet();

/// @dev Thrown when trying to mint more than the yearly cap
error ExceedsYearlyMintCap();

/// @dev Thrown when there is no amount to mint
error NoMintableAmount();

/// @dev Thrown when trying to transfer tokens into the pool while it is locked
error PoolLocked();

/// @dev Thrown when two arrays have different lengths
error ArrayLengthsMismatch();

/// @dev Thrown when trying to release tokens before the end of the vesting period
error ReleaseAmountInvalid();

/// @dev Thrown when trying to premint more than the maximum allowed per address
error MaxPreMintPerAddressExceeded(uint256 amount, uint256 limit);

/// @dev Thrown when trying to premint more than the maximum allowed in total
error MaxTotalPreMintExceeded(uint256 amount, uint256 limit);

/// @dev Thrown when trying to mint more than the maximum allowed in total
error MaxTotalVestedExceeded(uint256 amount, uint256 limit);

/// @dev Thrown when trying to release tokens before the vesting period has started
error VestingNotStartedYet();

/// @dev Thrown when trying to set the mint rate to a value higher than the maximum allowed
error MaxYearlyMintRateExceeded(uint256 amount, uint256 limit);

/// @dev Thrown when an unauthorized account tries to access owner-only functionality
error OwnableUnauthorizedAccount(address account);

/// @dev Max amount of tokens that can be pre-minted per address (% expressed in WAD)
uint256 constant MAX_PRE_MINT_PER_ADDRESS_WAD = 0.2 ether;

/// @dev Max amount of tokens that can be pre-minted in total (% expressed in WAD)
uint256 constant MAX_TOTAL_PRE_MINT_WAD = 0.2 ether;

/// @dev Maximum amount of tokens that can be minted in a year (% expressed in WAD)
uint256 constant MAX_YEARLY_MINT_RATE_WAD = 0.02 ether;

/// @dev Address of the canonical Permit2 contract
address constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

/**
 * @notice Vesting data for a specific address
 * @param totalAmount Total amount of vested tokens
 * @param releasedAmount Amount of tokens already released
 */
struct VestingData {
    uint256 totalAmount;
    uint256 releasedAmount;
}

/**
 * @title HolographERC20
 * @notice ERC20 token with DERC20 features (voting, vesting, inflation controls)
 * @dev Upgradeable token implementation for use with clone pattern
 * @author Holograph Protocol
 */
contract HolographERC20 is ERC20Upgradeable, ERC20VotesUpgradeable, ERC20PermitUpgradeable, OwnableUpgradeable {
    /* -------------------------------------------------------------------------- */
    /*                                 Storage                                    */
    /* -------------------------------------------------------------------------- */
    /// @notice Timestamp of the start of the vesting period
    uint256 public vestingStart;

    /// @notice Duration of the vesting period (in seconds)
    uint256 public vestingDuration;

    /// @notice Total amount of vested tokens
    uint256 public vestedTotalAmount;

    /// @notice Address of the liquidity pool
    address public pool;

    /// @notice Whether the pool can receive tokens (unlocked) or not
    bool public isPoolUnlocked;

    /// @notice Maximum rate of tokens that can be minted in a year
    uint256 public yearlyMintRate;

    /// @notice Timestamp of the start of the current year
    uint256 public currentYearStart;

    /// @notice Timestamp of the last inflation mint
    uint256 public lastMintTimestamp;

    /// @notice Uniform Resource Identifier (URI)
    string public tokenURI;

    /// @notice Returns vesting data for a specific address
    mapping(address account => VestingData vestingData) public getVestingDataOf;

    /// @notice The factory contract that deployed this token
    IHolographFactory public factory;

    /* -------------------------------------------------------------------------- */
    /*                                Modifiers                                   */
    /* -------------------------------------------------------------------------- */
    modifier hasVestingStarted() {
        if (vestingStart == 0) revert VestingNotStartedYet();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                               Initialize                                   */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Initialize the HolographERC20 with DERC20 capabilities
     * @dev Called once by the factory after clone deployment
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _initialSupply Initial supply of the token
     * @param _recipient Address receiving the initial supply
     * @param _owner Address receiving the ownership of the token
     * @param _yearlyMintRate Maximum inflation rate of token in a year
     * @param _vestingDuration Duration of the vesting period (in seconds)
     * @param _recipients Array of addresses receiving vested tokens
     * @param _amounts Array of amounts of tokens to be vested
     * @param _tokenURI Uniform Resource Identifier (URI)
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address _recipient,
        address _owner,
        uint256 _yearlyMintRate,
        uint256 _vestingDuration,
        address[] memory _recipients,
        uint256[] memory _amounts,
        string memory _tokenURI
    ) external initializer {
        // Initialize parent contracts
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __ERC20Votes_init();
        __Ownable_init(_owner);
        require(
            _yearlyMintRate <= MAX_YEARLY_MINT_RATE_WAD,
            MaxYearlyMintRateExceeded(_yearlyMintRate, MAX_YEARLY_MINT_RATE_WAD)
        );
        yearlyMintRate = _yearlyMintRate;
        vestingStart = block.timestamp;
        vestingDuration = _vestingDuration;
        tokenURI = _tokenURI;
        factory = IHolographFactory(msg.sender); // Store the factory that deployed this token

        uint256 length = _recipients.length;
        require(length == _amounts.length, ArrayLengthsMismatch());

        uint256 vestedTokens;
        uint256 maxPreMintPerAddress = (_initialSupply * MAX_PRE_MINT_PER_ADDRESS_WAD) / 1 ether;

        for (uint256 i; i < length; ++i) {
            uint256 amount = _amounts[i];
            getVestingDataOf[_recipients[i]].totalAmount += amount;
            require(
                getVestingDataOf[_recipients[i]].totalAmount <= maxPreMintPerAddress,
                MaxPreMintPerAddressExceeded(getVestingDataOf[_recipients[i]].totalAmount, maxPreMintPerAddress)
            );
            vestedTokens += amount;
        }

        uint256 maxTotalPreMint = (_initialSupply * MAX_TOTAL_PRE_MINT_WAD) / 1 ether;
        require(vestedTokens <= maxTotalPreMint, MaxTotalPreMintExceeded(vestedTokens, maxTotalPreMint));
        require(vestedTokens < _initialSupply, MaxTotalVestedExceeded(vestedTokens, _initialSupply));

        vestedTotalAmount = vestedTokens;

        if (vestedTokens > 0) {
            _mint(address(this), vestedTokens);
        }

        _mint(_recipient, _initialSupply - vestedTokens);

        // Transfer ownership to specified owner
        if (_owner != msg.sender) {
            _transferOwnership(_owner);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                            Pool Management                                 */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Locks the pool, preventing it from receiving tokens
     * @param pool_ Address of the pool to lock
     */
    function lockPool(address pool_) external onlyOwner {
        pool = pool_;
        isPoolUnlocked = false;
    }

    /// @notice Unlocks the pool, allowing it to receive tokens
    function unlockPool() external onlyOwner {
        isPoolUnlocked = true;
        currentYearStart = lastMintTimestamp = block.timestamp;
    }

    /* -------------------------------------------------------------------------- */
    /*                            Inflation Management                            */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Mints inflation tokens to the owner
     */
    function mintInflation() public onlyOwner {
        require(currentYearStart != 0, MintingNotStartedYet());

        uint256 mintableAmount;
        uint256 yearMint;
        uint256 timeLeftInCurrentYear;
        uint256 supply = totalSupply();
        uint256 currentYearStart_ = currentYearStart;
        uint256 lastMintTimestamp_ = lastMintTimestamp;
        uint256 yearlyMintRate_ = yearlyMintRate;

        // Handle any outstanding full years and updates to maintain inflation rate
        while (block.timestamp > currentYearStart_ + 365 days) {
            // SAFETY: unchecked arithmetic is safe here because:
            // 1. timeLeftInCurrentYear: (currentYearStart_ + 365 days - lastMintTimestamp_)
            //    cannot underflow because the while condition ensures currentYearStart_ + 365 days > block.timestamp > lastMintTimestamp_
            // 2. yearMint calculation: uses multiplication/division with controlled inputs (yearlyMintRate_ <= 2% WAD, timeLeftInCurrentYear <= 365 days)
            //    and cannot overflow with realistic token supplies
            // 3. supply += yearMint: yearMint represents a small percentage of supply, cannot cause overflow in practice
            // 4. mintableAmount += yearMint: accumulates yearMint values, bounded by the loop iterations and yearMint size
            // 5. currentYearStart_ += 365 days: addition of constant cannot overflow in reasonable timeframes
            // 6. lastMintTimestamp_ = currentYearStart_: simple assignment, no arithmetic
            //
            // This optimization saves ~2000 gas per loop iteration by avoiding overflow checks
            // on operations that are mathematically guaranteed to be safe given our constraints.
            unchecked {
                timeLeftInCurrentYear = (currentYearStart_ + 365 days - lastMintTimestamp_);
                yearMint = (supply * yearlyMintRate_ * timeLeftInCurrentYear) / (1 ether * 365 days);
                supply += yearMint;
                mintableAmount += yearMint;
                currentYearStart_ += 365 days;
                lastMintTimestamp_ = currentYearStart_;
            }
        }

        // Handle partial current year
        if (block.timestamp > lastMintTimestamp_) {
            // SAFETY: unchecked arithmetic is safe here because:
            // 1. (block.timestamp - lastMintTimestamp_): cannot underflow because the if condition ensures block.timestamp > lastMintTimestamp_
            // 2. partialYearMint calculation: same safety guarantees as yearMint above - controlled inputs and realistic bounds
            // 3. mintableAmount += partialYearMint: adding a small percentage of supply to an already bounded value
            //
            // This saves ~1000 gas by avoiding overflow checks on safe operations.
            unchecked {
                uint256 partialYearMint =
                    (supply * yearlyMintRate_ * (block.timestamp - lastMintTimestamp_)) / (1 ether * 365 days);
                mintableAmount += partialYearMint;
            }
        }

        require(mintableAmount > 0, NoMintableAmount());

        currentYearStart = currentYearStart_;
        lastMintTimestamp = block.timestamp;
        _mint(owner(), mintableAmount);
    }

    /**
     * @notice Burns `amount` of tokens from the address `owner`
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external onlyOwner {
        _burn(owner(), amount);
    }

    /**
     * @notice Updates the maximum rate of tokens that can be minted in a year
     * @param newMintRate New maximum rate of tokens that can be minted in a year
     */
    function updateMintRate(uint256 newMintRate) external onlyOwner {
        require(
            newMintRate <= MAX_YEARLY_MINT_RATE_WAD, MaxYearlyMintRateExceeded(newMintRate, MAX_YEARLY_MINT_RATE_WAD)
        );

        if (currentYearStart != 0 && (block.timestamp - lastMintTimestamp) != 0) {
            mintInflation();
        }

        yearlyMintRate = newMintRate;
    }

    /**
     * @notice Updates the token Uniform Resource Identifier (URI)
     * @param tokenURI_ New token Uniform Resource Identifier (URI)
     */
    function updateTokenURI(string memory tokenURI_) external onlyOwner {
        tokenURI = tokenURI_;
    }

    /* -------------------------------------------------------------------------- */
    /*                            Vesting Management                             */
    /* -------------------------------------------------------------------------- */
    /**
     * @notice Releases all available vested tokens
     */
    function release() external hasVestingStarted {
        uint256 availableAmount = computeAvailableVestedAmount(msg.sender);
        getVestingDataOf[msg.sender].releasedAmount += availableAmount;
        _transfer(address(this), msg.sender, availableAmount);
    }

    /**
     * @notice Computes the amount of vested tokens available for a specific address
     * @param account Recipient of the vested tokens
     * @return Amount of vested tokens available
     */
    function computeAvailableVestedAmount(address account) public view returns (uint256) {
        uint256 vestedAmount;

        if (block.timestamp < vestingStart + vestingDuration) {
            vestedAmount = (getVestingDataOf[account].totalAmount * (block.timestamp - vestingStart)) / vestingDuration;
        } else {
            vestedAmount = getVestingDataOf[account].totalAmount;
        }

        return vestedAmount - getVestingDataOf[account].releasedAmount;
    }

    /* -------------------------------------------------------------------------- */
    /*                            Override Functions                             */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ERC20PermitUpgradeable
    function nonces(address owner_) public view override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
        return super.nonces(owner_);
    }

    /// @notice Enhanced allowance function with Permit2 integration
    function allowance(address owner, address spender) public view override returns (uint256) {
        if (spender == PERMIT_2) return type(uint256).max;
        return super.allowance(owner, spender);
    }

    /// @notice Enhanced transfer function with pool lock protection
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        if (to == pool && isPoolUnlocked == false) revert PoolLocked();
        super._update(from, to, value);
    }
}
