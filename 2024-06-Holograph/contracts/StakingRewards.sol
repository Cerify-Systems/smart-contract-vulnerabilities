// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title StakingRewards
 * @notice HLG staking with automatic reward compounding and configurable burn/reward split.
 * @dev
 * - Rewards automatically compound using a reward tracking system with high precision math.
 * - When paused, users can still withdraw but cannot stake; reward distributors are also blocked.
 * - When rewards are distributed, they're immediately tracked for all stakers proportionally.
 * - Extra HLG tokens sent directly to the contract can be recovered with `recoverExtraHLG`.
 * - If no one is staking, reward distributions are skipped to save gas.
 * - Token burning works by transferring to address(0). The HLG token at
 *   0x740dF024Ce73F589AcD5E8756B377eF8C6558BaB reduces its total supply when tokens are burned.
 */
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract StakingRewards is
    Initializable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /* -------------------------------------------------------------------------- */
    /*                                  Errors                                    */
    /* -------------------------------------------------------------------------- */
    error ZeroAmount();
    error ZeroAddress();
    error NoStake();
    error Unauthorized();
    error CannotRecoverStakeToken();
    error NoEtherAccepted();
    error InvalidCall();
    error FeeOnTransferNotSupported();
    error InsufficientToken();
    error EthTransferFailed();
    error InvalidBurnPercentage();
    error ArrayLengthMismatch();
    error EndIndexOutOfBounds();
    error InvalidIndexRange();
    error NoTokensReceived();
    error NotWhitelistedDistributor();
    error BurnFailed();
    error NotEnoughExtraTokens();
    error NotEnoughRewardsAvailable();
    error ActiveStakeExists();
    error RewardTooSmall();
    error StakingCooldownNotMet();

    /* -------------------------------------------------------------------------- */
    /*                                  Storage                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice Precision multiplier for reward calculations (1e12 scaling)
    uint256 private constant INDEX_PRECISION = 1e12;

    /// @notice Maximum percentage value in basis points (100%)
    uint256 public constant MAX_PERCENTAGE = 10000;

    /// @notice HLG token that users stake and receive as rewards
    IERC20 public HLG;

    /// @notice Total HLG staked in the contract (includes compounded rewards)
    uint256 public totalStaked;

    /// @notice Count of unique addresses with nonzero stake
    uint256 public totalStakers;

    /// @notice User stake balances (includes original stake + compounded rewards)
    mapping(address => uint256) public balanceOf;

    /// @notice FeeRouter address (future automated rewards source)
    address public feeRouter;

    /// @notice Percentage of rewards that get burned (in basis points, 10000 = 100%)
    uint256 public burnPercentage;

    /// @notice Global cumulative reward index (scaled by INDEX_PRECISION for precision)
    uint256 public globalRewardIndex;

    /// @notice Tracks each user's reward snapshot to prevent double-claiming
    mapping(address => uint256) public userIndexSnapshot;

    /// @notice Rewards that have been distributed but not yet claimed by users
    uint256 public unallocatedRewards;

    /// @notice Registry of approved distributors (Merkle drop contracts, quest engines, etc.)
    mapping(address => bool) public isDistributor;

    /// @notice Cooldown period before users can unstake (default: 7 days)
    uint256 public stakingCooldown;

    /// @notice Tracks when each user last staked tokens
    mapping(address => uint256) public lastStakeTimestamp;

    /// @notice Total rewards forfeited via emergency exits (reclaimable by owner)
    uint256 public forfeitedRewards;

    /* -------------------------------------------------------------------------- */
    /*                                  Events                                    */
    /* -------------------------------------------------------------------------- */
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event EmergencyExit(address indexed user, uint256 amount);
    event RewardsForfeited(address indexed user, uint256 forfeitedAmount);
    event RewardsCompounded(address indexed user, uint256 rewardAmount);
    event RewardsDistributed(uint256 totalAmount, uint256 burnAmount, uint256 rewardAmount);
    event FeeRouterUpdated(address indexed newFeeRouter);
    event BurnPercentageUpdated(uint256 oldPercentage, uint256 newPercentage);
    event TokensRecovered(address indexed token, uint256 amount, address indexed to);
    event EthSwept(uint256 amount, address indexed to);
    event DistributorUpdated(address indexed distributor, bool status);
    event BoostedStake(address indexed distributor, address indexed user, uint256 amount);
    event StakingCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);

    /* -------------------------------------------------------------------------- */
    /*                               Constructor                                  */
    /* -------------------------------------------------------------------------- */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the upgradeable StakingRewards contract
     * @param _hlg HLG token address
     * @param _owner Initial owner address
     */
    function initialize(address _hlg, address _owner) external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);

        if (_hlg == address(0)) revert ZeroAddress();
        if (_owner == address(0)) revert ZeroAddress();

        HLG = IERC20(_hlg);
        burnPercentage = 5000; // Default to 50% burn, 50% rewards
        stakingCooldown = 7 days; // Default to 7-day cooldown

        _pause(); // Start paused until ready
    }

    /* -------------------------------------------------------------------------- */
    /*                                    User                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Stake HLG tokens to earn auto-compounding rewards
     * @param amount Amount of HLG to stake
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        uint256 actualAmount = _pullHLG(msg.sender, amount);
        _updateUser(msg.sender);

        // Track new staker
        if (balanceOf[msg.sender] == 0) {
            totalStakers++;
        }

        balanceOf[msg.sender] += actualAmount;
        totalStaked += actualAmount;

        // Record staking timestamp to enforce cooldown
        lastStakeTimestamp[msg.sender] = block.timestamp;

        emit Staked(msg.sender, actualAmount);
    }

    /**
     * @notice Unstake entire HLG balance including all accumulated rewards
     * @dev Auto-compounds first, then transfers full balance. Can be called while paused.
     */
    function unstake() external nonReentrant {
        _updateUser(msg.sender);

        uint256 userBalance = balanceOf[msg.sender];
        if (userBalance == 0) revert NoStake();

        // Check if cooldown period has passed since last stake (skip if no timestamp set)
        if (lastStakeTimestamp[msg.sender] != 0 && block.timestamp < lastStakeTimestamp[msg.sender] + stakingCooldown) {
            revert StakingCooldownNotMet();
        }

        balanceOf[msg.sender] = 0;
        userIndexSnapshot[msg.sender] = 0;
        lastStakeTimestamp[msg.sender] = 0; // Reset timestamp on unstake
        totalStaked -= userBalance;
        unchecked {
            totalStakers -= 1;
        }
        HLG.safeTransfer(msg.sender, userBalance);
        emit Unstaked(msg.sender, userBalance);
    }

    /**
     * @notice Emergency exit without compounding pending rewards
     * @dev Does not call updateUser; returns current recorded balance. Can be called while paused.
     */
    function emergencyExit() external nonReentrant whenPaused {
        uint256 userBalance = balanceOf[msg.sender];
        if (userBalance == 0) revert NoStake();

        // Calculate forfeited pending rewards
        uint256 pendingRewardsAmount = _pendingRewards(msg.sender);
        if (pendingRewardsAmount > 0) {
            forfeitedRewards += pendingRewardsAmount;
            emit RewardsForfeited(msg.sender, pendingRewardsAmount);
        }

        balanceOf[msg.sender] = 0;
        userIndexSnapshot[msg.sender] = 0;
        lastStakeTimestamp[msg.sender] = 0; // Reset timestamp on emergency exit
        totalStaked -= userBalance;
        unchecked {
            totalStakers -= 1;
        }
        HLG.safeTransfer(msg.sender, userBalance);
        emit EmergencyExit(msg.sender, userBalance);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Funding                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Deposit HLG and distribute according to burn/reward split.
     * @param hlgAmount HLG to pull from caller
     * @dev Splits burn/reward and updates the index. If there are no stakers,
     *      this call is a no-op.
     */
    function depositAndDistribute(uint256 hlgAmount) external onlyOwner nonReentrant whenNotPaused {
        uint256 staked = _activeStaked();
        if (staked == 0) return;
        if (hlgAmount == 0) revert ZeroAmount();

        // Pull tokens first to get the exact received amount
        uint256 received = _pullHLG(msg.sender, hlgAmount);
        uint256 burnAmount = (received * burnPercentage) / MAX_PERCENTAGE;
        uint256 rewardAmount = received - burnAmount;

        // If there is a positive rewardAmount, ensure it will move the index
        if (rewardAmount > 0) {
            if ((rewardAmount * INDEX_PRECISION) / staked == 0) revert RewardTooSmall();
            _addRewards(rewardAmount);
        }

        // Perform burn after validation to avoid partial side effects on revert
        _burnHLG(burnAmount);

        emit RewardsDistributed(received, burnAmount, rewardAmount);
    }

    /**
     * @notice Add rewards from FeeRouter (automated flow).
     * @param amount HLG to pull from FeeRouter
     * @dev Splits burn/reward and updates the index. If there are no stakers,
     *      rewards become extra tokens recoverable by owner.
     */
    function addRewards(uint256 amount) external nonReentrant {
        if (msg.sender != feeRouter) revert Unauthorized();

        // Pull tokens first to get the exact received amount
        uint256 received = _pullHLG(msg.sender, amount);
        uint256 staked = _activeStaked();
        if (staked == 0) return;
        if (amount == 0) revert ZeroAmount();

        uint256 burnAmount = (received * burnPercentage) / MAX_PERCENTAGE;
        uint256 rewardAmount = received - burnAmount;

        // If there is a positive rewardAmount, ensure it will move the index
        if (rewardAmount > 0) {
            if ((rewardAmount * INDEX_PRECISION) / staked != 0) {
                _addRewards(rewardAmount);
            }
        }

        // Perform burn after validation to avoid partial side effects on revert
        _burnHLG(burnAmount);

        emit RewardsDistributed(received, burnAmount, rewardAmount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Internals                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Get active staked amount (excluding unallocated rewards)
     * @return Amount of HLG actively staked by users
     */
    function _activeStaked() internal view returns (uint256) {
        return totalStaked - unallocatedRewards;
    }

    /**
     * @notice Internal helper to pull HLG tokens with safety checks
     * @dev Rejects fee-on-transfer tokens; requires exact amount received
     * @param from Address to pull tokens from
     * @param amount Expected amount to receive
     * @return actualAmount Amount actually received (equals amount or reverts)
     */
    function _pullHLG(address from, uint256 amount) internal returns (uint256 actualAmount) {
        uint256 balanceBefore = HLG.balanceOf(address(this));
        HLG.safeTransferFrom(from, address(this), amount);
        uint256 balanceAfter = HLG.balanceOf(address(this));
        actualAmount = balanceAfter - balanceBefore;
        if (actualAmount == 0) revert NoTokensReceived();
        if (actualAmount != amount) revert FeeOnTransferNotSupported();
    }

    /**
     * @notice Updates reward state for an account, compounding any pending amount.
     * @dev Sets the snapshot to the current index after compounding.
     * @param account Address to update rewards for
     */
    function _updateUser(address account) internal {
        uint256 userBalance = balanceOf[account];
        uint256 currentIndex = globalRewardIndex;
        uint256 snapshot = userIndexSnapshot[account];

        if (userBalance > 0) {
            uint256 indexDelta = currentIndex - snapshot;
            if (indexDelta != 0) {
                uint256 rewardAmount = (userBalance * indexDelta) / INDEX_PRECISION;
                if (rewardAmount > 0) {
                    // Make sure we have enough rewards available to give to the user
                    uint256 unallocated = unallocatedRewards;
                    if (rewardAmount > unallocated) revert NotEnoughRewardsAvailable();

                    balanceOf[account] = userBalance + rewardAmount;
                    unallocatedRewards = unallocated - rewardAmount;
                    emit RewardsCompounded(account, rewardAmount);
                }
            }
        }
        userIndexSnapshot[account] = currentIndex;
    }

    /**
     * @notice Safely burn HLG tokens with supply reduction verification
     * @param amount Amount of HLG to burn
     */
    function _burnHLG(uint256 amount) internal {
        if (amount == 0) return;

        // HolographERC20 has a burn() function that burns from msg.sender
        // At this point, the tokens have been pulled to this contract via _pullHLG
        uint256 supplyBefore = HLG.totalSupply();

        // Cast to ERC20Burnable interface and burn from this contract's balance
        ERC20Burnable(address(HLG)).burn(amount);
        uint256 supplyAfter = HLG.totalSupply();

        // Verify supply was reduced by the burn amount
        if (supplyBefore != supplyAfter + amount) revert BurnFailed();
    }

    /**
     * @notice Add rewards to the pool for immediate distribution
     * @param rewardAmount Amount of HLG rewards to distribute to stakers
     */
    function _addRewards(uint256 rewardAmount) internal {
        uint256 staked = _activeStaked();
        // index bump uses active stake
        globalRewardIndex += (rewardAmount * INDEX_PRECISION) / staked;

        // Track the full reward amount for distribution to users
        unallocatedRewards += rewardAmount;
        totalStaked += rewardAmount;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Views                                   */
    /* -------------------------------------------------------------------------- */

    function _pendingRewards(address account) internal view returns (uint256) {
        uint256 userBalance = balanceOf[account];
        if (userBalance == 0) return 0;
        return (userBalance * (globalRewardIndex - userIndexSnapshot[account])) / INDEX_PRECISION;
    }

    /**
     * @notice Calculate pending rewards for a user (not yet compounded)
     * @param account Address to check pending rewards for
     * @return Amount of pending auto-compound rewards
     */
    function pendingRewards(address account) external view returns (uint256) {
        return _pendingRewards(account);
    }

    /**
     * @notice Get current global reward index
     * @return Current global reward index (1e12 scaling)
     */
    function rewardPerToken() external view returns (uint256) {
        return globalRewardIndex;
    }

    /**
     * @notice Get user's share of active staked pool (excluding unallocated rewards)
     * @param user Address to check
     * @return User's percentage share in basis points (10000 = 100%)
     */
    function getUserShareBps(address user) external view returns (uint256) {
        uint256 staked = _activeStaked();
        if (staked == 0) return 0;
        return (balanceOf[user] * MAX_PERCENTAGE) / staked;
    }

    /**
     * @notice Calculate user's total balance including pending rewards
     * @param user Address to check
     * @return Total balance (current stake + pending compounded rewards)
     */
    function balanceWithPendingRewards(address user) external view returns (uint256) {
        return balanceOf[user] + _pendingRewards(user);
    }

    /**
     * @notice Returns extra HLG tokens that can be recovered
     * @dev Shows HLG.balanceOf(this) - totalStaked
     * @return Amount of extra HLG tokens available for recovery
     */
    function getExtraTokens() external view returns (uint256) {
        uint256 contractBalance = HLG.balanceOf(address(this));
        return contractBalance > totalStaked ? contractBalance - totalStaked : 0;
    }

    /**
     * @notice Check if a user can unstake (cooldown period passed)
     * @param user Address to check
     * @return true if user can unstake, false if still in cooldown
     */
    function canUnstake(address user) external view returns (bool) {
        if (balanceOf[user] == 0) return false;
        // If no timestamp set (owner staking), user can unstake immediately
        if (lastStakeTimestamp[user] == 0) return true;
        return block.timestamp >= lastStakeTimestamp[user] + stakingCooldown;
    }

    /**
     * @notice The version of the contract
     * @return Semantic version string
     */
    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }

    /**
     * @notice Get remaining cooldown time for a user in seconds
     * @param user Address to check
     * @return seconds remaining in cooldown period (0 if can unstake)
     */
    function getCooldownTimeRemaining(address user) external view returns (uint256) {
        if (balanceOf[user] == 0 || lastStakeTimestamp[user] == 0) return 0;

        uint256 cooldownEndTime = lastStakeTimestamp[user] + stakingCooldown;
        return block.timestamp >= cooldownEndTime ? 0 : cooldownEndTime - block.timestamp;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Admin                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Set FeeRouter address for future automation
     * @param _feeRouter New FeeRouter address
     */
    function setFeeRouter(address _feeRouter) external onlyOwner {
        if (_feeRouter == address(0)) revert ZeroAddress();
        feeRouter = _feeRouter;
        emit FeeRouterUpdated(_feeRouter);
    }

    /**
     * @notice Set burn percentage for reward distribution
     * @param _burnPercentage Percentage of rewards to burn (in basis points, 10000 = 100%)
     */
    function setBurnPercentage(uint256 _burnPercentage) external onlyOwner {
        if (_burnPercentage > MAX_PERCENTAGE) revert InvalidBurnPercentage();

        uint256 oldPercentage = burnPercentage;
        burnPercentage = _burnPercentage;

        emit BurnPercentageUpdated(oldPercentage, _burnPercentage);
    }

    /**
     * @notice Pause staking operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause staking operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Set staking cooldown period to prevent sandwich attacks
     * @param _stakingCooldown New cooldown period in seconds
     */
    function setStakingCooldown(uint256 _stakingCooldown) external onlyOwner {
        uint256 oldCooldown = stakingCooldown;
        stakingCooldown = _stakingCooldown;
        emit StakingCooldownUpdated(oldCooldown, _stakingCooldown);
    }

    /**
     * @notice Emergency function to recover tokens (not HLG)
     * @param token Token address to recover
     * @param to Address to send recovered tokens to
     * @param amountMinimum Minimum amount that must be available to recover
     */
    function recoverToken(address token, address to, uint256 amountMinimum) external onlyOwner nonReentrant {
        if (token == address(HLG)) revert CannotRecoverStakeToken();
        if (to == address(0)) revert ZeroAddress();
        if (amountMinimum == 0) revert ZeroAmount();

        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount < amountMinimum) revert InsufficientToken();

        IERC20(token).safeTransfer(to, amount);
        emit TokensRecovered(token, amount, to);
    }

    /**
     * @notice Recover extra HLG tokens that were sent directly to contract
     * @param to Address to send extra HLG to
     * @param amount Amount of extra HLG to recover
     */
    function recoverExtraHLG(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 bal = HLG.balanceOf(address(this));
        uint256 free = bal > totalStaked ? bal - totalStaked : 0;
        if (amount > free) revert NotEnoughExtraTokens();
        HLG.safeTransfer(to, amount);
        emit TokensRecovered(address(HLG), amount, to);
    }

    /**
     * @notice Reclaim unallocated rewards, prioritizing forfeited rewards
     * @param to Address to send rewards to
     * @dev Can reclaim forfeited rewards even with active stakers, but requires no active stakers for full unallocated rewards
     */
    function reclaimUnallocatedRewards(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();

        uint256 forfeited = forfeitedRewards;
        uint256 activeStake = _activeStaked();
        uint256 reclaimAmount;

        if (forfeited > 0) {
            // Can always reclaim forfeited rewards up to total forfeited amount
            reclaimAmount = forfeited;
            forfeitedRewards = 0;
        } else if (activeStake == 0) {
            // Can only reclaim full unallocated when no active stakers
            uint256 unallocated = unallocatedRewards;
            if (unallocated == 0) revert ZeroAmount();
            reclaimAmount = unallocated;
            unallocatedRewards = 0;
        } else {
            revert ActiveStakeExists();
        }

        if (reclaimAmount == 0) revert ZeroAmount();

        // Only subtract from unallocated if we're not resetting it to 0
        if (forfeited > 0) {
            unallocatedRewards -= reclaimAmount;
        }

        unchecked {
            totalStaked -= reclaimAmount;
        }
        HLG.safeTransfer(to, reclaimAmount);

        emit TokensRecovered(address(HLG), reclaimAmount, to);
    }

    /**
     * @notice Sweep ETH that may have been force-sent to the contract
     * @param to Address to send the ETH to
     */
    function sweepETH(address payable to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();

        uint256 balance = address(this).balance;
        if (balance == 0) revert ZeroAmount();

        (bool success,) = to.call{value: balance}("");
        if (!success) revert EthTransferFailed();

        emit EthSwept(balance, to);
    }

    /**
     * @notice Credit HLG stake on behalf of a user (owner-only, paused-only)
     * @param user Address to receive the stake credit
     * @param amount Amount of HLG to stake
     */
    function stakeFor(address user, uint256 amount) public nonReentrant onlyOwner whenPaused {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _pullHLG(msg.sender, amount);
        _updateUser(user);

        // Track new staker
        if (balanceOf[user] == 0) {
            totalStakers++;
        }

        balanceOf[user] += amount;
        totalStaked += amount;

        emit Staked(user, amount);
    }

    /**
     * @notice Batch stake HLG tokens for multiple users (gas optimized)
     * @param users Array of user addresses to stake for
     * @param amounts Array of amounts to stake for each user
     * @param startIndex Starting index in the arrays to process
     * @param endIndex Ending index (exclusive) in the arrays to process
     */
    function batchStakeFor(address[] calldata users, uint256[] calldata amounts, uint256 startIndex, uint256 endIndex)
        external
        onlyOwner
        whenPaused
        nonReentrant
    {
        if (users.length != amounts.length) revert ArrayLengthMismatch();
        if (endIndex > users.length) revert EndIndexOutOfBounds();
        if (startIndex >= endIndex) revert InvalidIndexRange();

        // Validate all inputs and calculate total amount
        uint256 totalAmount;
        for (uint256 i = startIndex; i < endIndex;) {
            if (users[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) revert ZeroAmount();
            totalAmount += amounts[i];
            unchecked {
                ++i;
            }
        }

        _pullHLG(msg.sender, totalAmount);

        // Process each user: compound existing rewards, add new stake
        for (uint256 i = startIndex; i < endIndex;) {
            address user = users[i];
            uint256 amount = amounts[i];

            _updateUser(user);

            // Track new staker
            if (balanceOf[user] == 0) {
                totalStakers++;
            }

            balanceOf[user] += amount;
            totalStaked += amount;

            emit Staked(user, amount);
            unchecked {
                ++i;
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                Distributors                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Whitelist/delist a distributor contract for future campaigns
     * @param distributor Address of the distributor contract
     * @param status True to whitelist, false to delist
     */
    function setDistributor(address distributor, bool status) external onlyOwner {
        if (distributor == address(0)) revert ZeroAddress();
        isDistributor[distributor] = status;
        emit DistributorUpdated(distributor, status);
    }

    /**
     * @notice Credit stake on behalf of user (called by whitelisted distributors)
     * @param user Wallet to receive the staked HLG
     * @param amount HLG amount to stake (pulled from distributor)
     */
    function stakeFromDistributor(address user, uint256 amount) external nonReentrant whenNotPaused {
        if (!isDistributor[msg.sender]) revert NotWhitelistedDistributor();
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _pullHLG(msg.sender, amount);
        _updateUser(user);

        // Track new staker
        if (balanceOf[user] == 0) {
            totalStakers++;
        }

        balanceOf[user] += amount;
        totalStaked += amount;

        emit Staked(user, amount);
        emit BoostedStake(msg.sender, user, amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Upgrades                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Authorize contract upgrades (UUPS pattern)
     * @param newImplementation Address of the new implementation
     * @dev Only the owner can authorize upgrades
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* -------------------------------------------------------------------------- */
    /*                                    Fallback                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Reject ETH sent to the contract
     * @dev Prevents accidental ETH transfers to the contract
     */
    receive() external payable {
        revert NoEtherAccepted();
    }

    /**
     * @notice Reject calls to the contract
     * @dev Prevents accidental calls to the contract
     */
    fallback() external payable {
        revert InvalidCall();
    }
}
