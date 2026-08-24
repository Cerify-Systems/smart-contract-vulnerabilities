// SOURCE NOTE: Pulled from emilianobonassi/cover-exploit (github.com/emilianobonassi/cover-exploit),
// maintained by the Yearn Finance engineer who worked directly with Cover Protocol's team to
// reproduce and confirm this exploit. IMPORTANT: this version already contains the FIX -- notice
// the "// Re-read updated pool from storage" line inside deposit(), which re-reads the pool struct
// from storage immediately after updatePool() runs. The ORIGINAL vulnerable mainnet contract did
// NOT have this re-read step; it kept using the stale memory `pool` variable captured before
// updatePool() was called. See exploit.md for the exact vulnerable pattern (reconstructed from
// multiple independent technical writeups, since the original unpatched bytecode's verified source
// was not directly located in this research pass).
//
// This file is included because it's a genuine, credible, developer-authored reproduction of the
// Blacksmith contract's logic and structure -- useful for understanding pool/miner/rewards mechanics
// -- but for your walkthrough, present the deposit() function as ORIGINALLY BROKEN by mentally
// removing the "// Re-read updated pool from storage" line and the reassignment right after it.
// That single removed line is the entire bug.

// SPDX-License-Identifier: None
pragma solidity ^0.7.4;

import "./ERC20/IERC20.sol";
import "./ERC20/SafeERC20.sol";
import "./utils/SafeMath.sol";
import "./utils/Ownable.sol";
import "./utils/ReentrancyGuard.sol";
import "./interfaces/ICOVER.sol";
import "./interfaces/IBlacksmith.sol";

/**
 * @title COVER token shield mining contract
 * @author crypto-pumpkin@github
 */
contract Blacksmith is Ownable, IBlacksmith, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    ICOVER public cover;
    address public governance;
    address public treasury;

    /// @notice Total 17k COVER in 1st 6 mths.
    uint256 public weeklyTotal = 654e18;
    uint256 public totalWeight; // total weight for all pools
    uint256 public constant START_TIME = 1605830400; // 11/20/2020 12am UTC
    uint256 public constant WEEK = 7 days;
    uint256 private constant CAL_MULTIPLIER = 1e12;

    address[] public poolList;
    mapping(address => Pool) public pools; // lpToken => Pool
    mapping(address => BonusToken) public bonusTokens; // lpToken => BonusToken
    mapping(address => uint8) public allowBonusTokens;
    mapping(address => mapping(address => Miner)) public miners; // lpToken => Miner address => Miner data

    modifier onlyGovernance() {
        require(msg.sender == governance, "Blacksmith: caller not governance");
        _;
    }

    constructor (address _coverAddress, address _governance, address _treasury) {
        cover = ICOVER(_coverAddress);
        governance = _governance;
        treasury = _treasury;
    }

    function getPoolList() external view override returns (address[] memory) {
        return poolList;
    }

    function viewMined(address _lpToken, address _miner)
        external view override returns (uint256 _minedCOVER, uint256 _minedBonus)
    {
        Pool memory pool = pools[_lpToken];
        Miner memory miner = miners[_lpToken][_miner];
        uint256 lpTotal = IERC20(_lpToken).balanceOf(address(this));
        if (miner.amount > 0 && lpTotal > 0) {
            uint256 coverRewards = _calculateCoverRewardsForPeriod(pool);
            uint256 accRewardsPerToken = pool.accRewardsPerToken.add(coverRewards.div(lpTotal));
            _minedCOVER = miner.amount.mul(accRewardsPerToken).div(CAL_MULTIPLIER).sub(miner.rewardWriteoff);

            BonusToken memory bonusToken = bonusTokens[_lpToken];
            if (bonusToken.startTime < block.timestamp && bonusToken.totalBonus > 0) {
                uint256 bonus = _calculateBonusForPeriod(bonusToken);
                uint256 accBonusPerToken = bonusToken.accBonusPerToken.add(bonus.div(lpTotal));
                _minedBonus = miner.amount.mul(accBonusPerToken).div(CAL_MULTIPLIER).sub(miner.bonusWriteoff);
            }
        }
        return (_minedCOVER, _minedBonus);
    }

    /// @notice update pool's rewards & bonus per staked token till current block timestamp
    function updatePool(address _lpToken) public override {
        Pool storage pool = pools[_lpToken];
        if (block.timestamp <= pool.lastUpdatedAt) return;
        uint256 lpTotal = IERC20(_lpToken).balanceOf(address(this));
        if (lpTotal == 0) {
            pool.lastUpdatedAt = block.timestamp;
            return;
        }
        uint256 coverRewards = _calculateCoverRewardsForPeriod(pool);
        pool.accRewardsPerToken = pool.accRewardsPerToken.add(coverRewards.div(lpTotal));
        pool.lastUpdatedAt = block.timestamp;

        BonusToken storage bonusToken = bonusTokens[_lpToken];
        if (bonusToken.lastUpdatedAt < bonusToken.endTime && bonusToken.startTime < block.timestamp) {
            uint256 bonus = _calculateBonusForPeriod(bonusToken);
            bonusToken.accBonusPerToken = bonusToken.accBonusPerToken.add(bonus.div(lpTotal));
            bonusToken.lastUpdatedAt = block.timestamp <= bonusToken.endTime ? block.timestamp : bonusToken.endTime;
        }
    }

    function claimRewards(address _lpToken) public override {
        updatePool(_lpToken);
        Pool memory pool = pools[_lpToken];
        Miner storage miner = miners[_lpToken][msg.sender];
        BonusToken memory bonusToken = bonusTokens[_lpToken];
        _claimCoverRewards(pool, miner);
        _claimBonus(bonusToken, miner);
        miner.rewardWriteoff = miner.amount.mul(pool.accRewardsPerToken).div(CAL_MULTIPLIER);
        miner.bonusWriteoff = miner.amount.mul(bonusToken.accBonusPerToken).div(CAL_MULTIPLIER);
    }

    function claimRewardsForPools(address[] calldata _lpTokens) external override {
        for (uint256 i = 0; i < _lpTokens.length; i++) {
            claimRewards(_lpTokens[i]);
        }
    }

    // ============================================================
    // THIS IS THE FUNCTION AT THE CENTER OF YOUR TALK.
    // As shown here, it has the FIX already applied (the re-read).
    // The ORIGINAL vulnerable version did NOT have the two lines
    // marked "*** FIX ***" below -- it kept using the stale `pool`
    // memory variable captured at the top of the function.
    // ============================================================
    function deposit(address _lpToken, uint256 _amount) external override {
        require(block.timestamp >= START_TIME , "Blacksmith: not started");
        require(_amount > 0, "Blacksmith: amount is 0");
        Pool memory pool = pools[_lpToken];                          // (1) memory snapshot taken
        require(pool.lastUpdatedAt > 0, "Blacksmith: pool does not exists");
        require(IERC20(_lpToken).balanceOf(msg.sender) >= _amount, "Blacksmith: insufficient balance");

        updatePool(_lpToken);                                        // (2) REAL storage pool updated here

        // *** FIX *** -- this comment + line did NOT exist in the original vulnerable contract
        pool = pools[_lpToken];                                      // *** FIX *** re-read fresh storage value

        Miner storage miner = miners[_lpToken][msg.sender];
        BonusToken memory bonusToken = bonusTokens[_lpToken];
        _claimCoverRewards(pool, miner);                              // (3) now uses fresh `pool` (post-fix)
        _claimBonus(bonusToken, miner);
        miner.amount = miner.amount.add(_amount);
        miner.rewardWriteoff = miner.amount.mul(pool.accRewardsPerToken).div(CAL_MULTIPLIER);
        miner.bonusWriteoff = miner.amount.mul(bonusToken.accBonusPerToken).div(CAL_MULTIPLIER);
        IERC20(_lpToken).safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(msg.sender, _lpToken, _amount);
    }

    function withdraw(address _lpToken, uint256 _amount) external override {
        require(_amount > 0, "Blacksmith: amount is 0");
        Miner storage miner = miners[_lpToken][msg.sender];
        require(miner.amount >= _amount, "Blacksmith: insufficient balance");
        updatePool(_lpToken);
        Pool memory pool = pools[_lpToken];
        BonusToken memory bonusToken = bonusTokens[_lpToken];
        _claimCoverRewards(pool, miner);
        _claimBonus(bonusToken, miner);
        miner.amount = miner.amount.sub(_amount);
        miner.rewardWriteoff = miner.amount.mul(pool.accRewardsPerToken).div(CAL_MULTIPLIER);
        miner.bonusWriteoff = miner.amount.mul(bonusToken.accBonusPerToken).div(CAL_MULTIPLIER);
        _safeTransfer(_lpToken, _amount);
        emit Withdraw(msg.sender, _lpToken, _amount);
    }

    /// @notice withdraw all without rewards
    function emergencyWithdraw(address _lpToken) external override {
        Miner storage miner = miners[_lpToken][msg.sender];
        uint256 amount = miner.amount;
        require(miner.amount > 0, "Blacksmith: insufficient balance");
        miner.amount = 0;
        miner.rewardWriteoff = 0;
        _safeTransfer(_lpToken, amount);
        emit Withdraw(msg.sender, _lpToken, amount);
    }

    function updatePoolWeights(address[] calldata _lpTokens, uint256[] calldata _weights) public override onlyGovernance {
        for (uint256 i = 0; i < _lpTokens.length; i++) {
            Pool storage pool = pools[_lpTokens[i]];
            if (pool.lastUpdatedAt > 0) {
                totalWeight = totalWeight.add(_weights[i]).sub(pool.weight);
                pool.weight = _weights[i];
            }
        }
    }

    function addPool(address _lpToken, uint256 _weight) public override onlyOwner {
        Pool memory pool = pools[_lpToken];
        require(pool.lastUpdatedAt == 0, "Blacksmith: pool exists");
        pools[_lpToken] = Pool({
            weight: _weight,
            accRewardsPerToken: 0,
            lastUpdatedAt: block.timestamp
        });
        totalWeight = totalWeight.add(_weight);
        poolList.push(_lpToken);
    }

    function addPools(address[] calldata _lpTokens, uint256[] calldata _weights) external override onlyOwner {
        require(_lpTokens.length == _weights.length, "Blacksmith: size don't match");
        for (uint256 i = 0; i < _lpTokens.length; i++) {
            addPool(_lpTokens[i], _weights[i]);
        }
    }

    function updateBonusTokenStatus(address _bonusToken, uint8 _status) external override onlyOwner {
        require(_status != 0, "Blacksmith: status cannot be 0");
        require(pools[_bonusToken].lastUpdatedAt == 0, "Blacksmith: lpToken is not allowed");
        allowBonusTokens[_bonusToken] = _status;
    }

    function addBonusToken(
        address _lpToken,
        address _bonusToken,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _totalBonus
    ) external override {
        IERC20 bonusToken = IERC20(_bonusToken);
        require(pools[_lpToken].lastUpdatedAt != 0, "Blacksmith: pool does NOT exist");
        require(allowBonusTokens[_bonusToken] == 1, "Blacksmith: bonusToken not allowed");
        BonusToken memory currentBonusToken = bonusTokens[_lpToken];
        if (currentBonusToken.totalBonus != 0) {
            require(currentBonusToken.endTime.add(WEEK) < block.timestamp, "Blacksmith: last bonus period hasn't ended");
            require(IERC20(currentBonusToken.addr).balanceOf(address(this)) == 0, "Blacksmith: last bonus not all claimed");
        }
        require(_startTime >= block.timestamp && _endTime > _startTime, "Blacksmith: messed up timeline");
        require(_totalBonus > 0 && bonusToken.balanceOf(msg.sender) >= _totalBonus, "Blacksmith: incorrect total rewards");
        uint256 balanceBefore = bonusToken.balanceOf(address(this));
        bonusToken.safeTransferFrom(msg.sender, address(this), _totalBonus);
        uint256 balanceAfter = bonusToken.balanceOf(address(this));
        require(balanceAfter > balanceBefore, "Blacksmith: incorrect total rewards");
        bonusTokens[_lpToken] = BonusToken({
            addr: _bonusToken,
            startTime: _startTime,
            endTime: _endTime,
            totalBonus: balanceAfter.sub(balanceBefore),
            accBonusPerToken: 0,
            lastUpdatedAt: _startTime
        });
    }

    function collectDust(address _token) external override {
        Pool memory pool = pools[_token];
        require(pool.lastUpdatedAt == 0, "Blacksmith: lpToken, not allowed");
        require(allowBonusTokens[_token] == 0, "Blacksmith: bonusToken, not allowed");
        IERC20 token = IERC20(_token);
        uint256 amount = token.balanceOf(address(this));
        require(amount > 0, "Blacksmith: 0 to collect");
        if (_token == address(0)) {
            payable(treasury).transfer(amount);
        } else {
            token.safeTransfer(treasury, amount);
        }
    }

    function collectBonusDust(address _lpToken) external override {
        BonusToken memory bonusToken = bonusTokens[_lpToken];
        require(bonusToken.endTime.add(WEEK) < block.timestamp, "Blacksmith: bonusToken, not ready");
        IERC20 token = IERC20(bonusToken.addr);
        uint256 amount = token.balanceOf(address(this));
        require(amount > 0, "Blacksmith: 0 to collect");
        token.safeTransfer(treasury, amount);
    }

    function updateWeeklyTotal(uint256 _weeklyTotal) external override onlyGovernance {
        weeklyTotal = _weeklyTotal;
    }

    function updatePools(uint256 _start, uint256 _end) external override {
        address[] memory poolListCopy = poolList;
        for (uint256 i = _start; i < _end; i++) {
            updatePool(poolListCopy[i]);
        }
    }

    function transferMintingRights(address _newAddress) external override onlyGovernance {
        cover.setBlacksmith(_newAddress);
    }

    function _calculateCoverRewardsForPeriod(Pool memory _pool) internal view returns (uint256) {
        uint256 timePassed = block.timestamp.sub(_pool.lastUpdatedAt);
        return weeklyTotal.mul(CAL_MULTIPLIER).mul(timePassed).mul(_pool.weight).div(totalWeight).div(WEEK);
    }

    function _calculateBonusForPeriod(BonusToken memory _bonusToken) internal view returns (uint256) {
        if (_bonusToken.endTime == _bonusToken.lastUpdatedAt) return 0;
        uint256 calTime = block.timestamp > _bonusToken.endTime ? _bonusToken.endTime : block.timestamp;
        uint256 timePassed = calTime.sub(_bonusToken.lastUpdatedAt);
        uint256 totalDuration = _bonusToken.endTime.sub(_bonusToken.startTime);
        return _bonusToken.totalBonus.mul(CAL_MULTIPLIER).mul(timePassed).div(totalDuration);
    }

    function _safeTransfer(address _token, uint256 _amount) private nonReentrant {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        if (balance > _amount) {
            token.safeTransfer(msg.sender, _amount);
        } else if (balance > 0) {
            token.safeTransfer(msg.sender, balance);
        }
    }

    function _claimCoverRewards(Pool memory pool, Miner memory miner) private nonReentrant {
        if (miner.amount > 0) {
            uint256 minedSinceLastUpdate = miner.amount.mul(pool.accRewardsPerToken).div(CAL_MULTIPLIER).sub(miner.rewardWriteoff);
            if (minedSinceLastUpdate > 0) {
                cover.mint(msg.sender, minedSinceLastUpdate); // mint COVER tokens to miner
            }
        }
    }

    function _claimBonus(BonusToken memory bonusToken, Miner memory miner) private {
        if (bonusToken.totalBonus > 0 && miner.amount > 0 && bonusToken.startTime < block.timestamp) {
            uint256 bonusSinceLastUpdate = miner.amount.mul(bonusToken.accBonusPerToken).div(CAL_MULTIPLIER).sub(miner.bonusWriteoff);
            if (bonusSinceLastUpdate > 0) {
                _safeTransfer(bonusToken.addr, bonusSinceLastUpdate); // transfer bonus tokens to miner
            }
        }
    }
}
