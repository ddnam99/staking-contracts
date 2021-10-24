// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "hardhat/console.sol";

import "./StakingLib.sol";
import "./Error.sol";

contract StakingMock is Context, ReentrancyGuard, AccessControl {
    uint256 public blockTimestamp;

    StakingLib.Pool[] private _pools;

    uint256 public daysOfYear = 365;

    // poolId => account => stake info
    mapping(uint256 => mapping(address => StakingLib.StakeInfo)) private _stakeInfoList;
    // amount token holders staked
    mapping(address => uint256) private _stakedAmounts;
    // amount rewards to paid holders
    mapping(address => uint256) private _rewardAmounts;

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), Error.ADMIN_ROLE_REQUIRED);
        _;
    }

    event NewPool(uint256 poolId);
    event ClosePool(uint256 poolId);
    event Staked(address user, uint256 poolId, uint256 amount);
    event Withdrawn(address user, uint256 poolId, uint256 amount, uint256 reward);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        blockTimestamp = block.timestamp;
    }

    function createPool(
        uint256 _startTime,
        address _stakeAddress,
        address _rewardAddress,
        uint256 _minTokenStake,
        uint256 _maxTokenStake,
        uint256 _maxPoolStake,
        uint256 _duration,
        uint256 _redemptionPeriod,
        uint256 _apr,
        uint256 _denominatorAPR,
        bool _useWhitelist,
        uint256 _minStakeWhitelist
    ) external nonReentrant onlyAdmin {
        require(_startTime >= blockTimestamp, Error.START_TIME_MUST_IN_FUTURE_DATE);
        require(_duration != 0, Error.DURATION_MUST_NOT_EQUAL_ZERO);
        require(_minTokenStake > 0, Error.MIN_TOKEN_STAKE_MUST_GREATER_ZERO);
        require(_maxTokenStake > 0, Error.MAX_TOKEN_STAKE_MUST_GREATER_ZERO);
        require(_maxPoolStake > 0, Error.MAX_POOL_STAKE_MUST_GREATER_ZERO);
        require(_denominatorAPR > 0, Error.DENOMINATOR_APR_MUST_GREATER_ZERO);
        require(_apr > 0 && _apr <= _denominatorAPR, Error.REWARD_PERCENT_MUST_IN_RANGE_BETWEEN_ONE_TO_HUNDRED);

        uint256 totalReward = (_maxPoolStake * _duration * _apr) / (daysOfYear * _denominatorAPR);

        require(
            IERC20(_rewardAddress).transferFrom(_msgSender(), address(this), totalReward),
            Error.TRANSFER_REWARD_FAILED
        );

        StakingLib.Pool memory pool = StakingLib.Pool(
            _pools.length,
            _startTime,
            true,
            _stakeAddress,
            _rewardAddress,
            _minTokenStake,
            _maxTokenStake,
            _maxPoolStake,
            0,
            _duration,
            _redemptionPeriod,
            _apr,
            _denominatorAPR,
            _useWhitelist,
            _minStakeWhitelist
        );

        _pools.push(pool);

        emit NewPool(_pools.length - 1);
    }

    function closePool(uint256 _poolId) external nonReentrant onlyAdmin {
        _pools[_poolId].isActive = false;

        emit ClosePool(_poolId);
    }

    function getDetailPool(uint256 _poolId) external view returns (StakingLib.Pool memory) {
        return _pools[_poolId];
    }

    function getAllPools() external view returns (StakingLib.Pool[] memory) {
        return _pools;
    }

    /**
        @dev count pools is active and staked amount less than max pool token
     */
    function _getCountActivePools() internal view returns (uint256 count) {
        for (uint256 i = 0; i < _pools.length; i++) {
            if (_pools[i].isActive && _pools[i].totalStaked < _pools[i].maxPoolStake) {
                count++;
            }
        }
    }

    function getCountActivePools() external view returns (uint256) {
        return _getCountActivePools();
    }

    /**
        @dev list pools is active an staked amount less than max pool token
     */
    function getActivePools() external view returns (StakingLib.Pool[] memory) {
        uint256 countActivePools = _getCountActivePools();
        uint256 count = 0;

        StakingLib.Pool[] memory activePools = new StakingLib.Pool[](countActivePools);

        for (uint256 i = 0; i < _pools.length; i++) {
            if (_pools[i].isActive && _pools[i].totalStaked < _pools[i].maxPoolStake) {
                activePools[count++] = _pools[i];
            }
        }

        return activePools;
    }

    /** 
        @dev value date start 07:00 UTC next day
     */
    function stake(uint256 _poolId, uint256 _amount) external nonReentrant {
        StakingLib.Pool memory pool = _pools[_poolId];
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_poolId][_msgSender()];

        require(stakeInfo.amount == 0 || stakeInfo.withdrawTime > 0, Error.DUPLICATE_STAKE);

        require(_amount > 0, Error.AMOUNT_MUST_GREATER_ZERO);
        require(pool.startTime <= blockTimestamp, Error.IT_NOT_TIME_STAKE_YET);
        require(pool.isActive && pool.totalStaked < pool.maxPoolStake, Error.POOL_CLOSED);
        require(pool.minTokenStake <= _amount, Error.AMOUNT_MUST_GREATER_OR_EQUAL_MIN_TOKEN_STAKE);
        require(pool.maxTokenStake >= _amount, Error.AMOUNT_MUST_LESS_OR_EQUAL_MAX_TOKEN_STAKE);
        require(pool.totalStaked + _amount <= pool.maxPoolStake, Error.OVER_MAX_POOL_STAKE);
        require(
            IERC20(pool.stakeAddress).transferFrom(_msgSender(), address(this), _amount),
            Error.TRANSFER_TOKEN_FAILED
        );

        uint256 reward = (_amount * pool.duration * pool.apr) / (daysOfYear * pool.denominatorAPR);

        require(
            IERC20(pool.rewardAddress).balanceOf(address(this)) >=
                _stakedAmounts[pool.rewardAddress] + _rewardAmounts[pool.rewardAddress] + reward,
            Error.CONTRACT_NOT_ENOUGH_REWARD
        );

        // 07:00 UTC next day
        uint256 valueDate = (blockTimestamp / 1 days) * 1 days + 1 days + 7 hours;

        stakeInfo = StakingLib.StakeInfo(_poolId, blockTimestamp, valueDate, _amount, 0);

        _pools[_poolId].totalStaked += _amount;
        _stakeInfoList[_poolId][_msgSender()] = stakeInfo;

        _stakedAmounts[pool.stakeAddress] += _amount;
        _rewardAmounts[pool.rewardAddress] += reward;

        emit Staked(_msgSender(), _poolId, _amount);
    }

    /**
        @dev if pool include white list and user stake amount qualified 
     */
    function checkWhiteList(uint256 _poolId, address _user) external view returns (bool) {
        StakingLib.Pool memory pool = _pools[_poolId];
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_poolId][_user];

        if (!pool.useWhitelist) return false;
        if (stakeInfo.withdrawTime != 0 && stakeInfo.stakeTime + pool.duration * 1 days > stakeInfo.withdrawTime)
            return false;
        if (pool.minStakeWhitelist > stakeInfo.amount) return false;

        return true;
    }

    /**
        @dev stake info in pool by user
     */
    function getStakeInfo(uint256 _poolId, address _user) external view returns (StakingLib.StakeInfo memory) {
        return _stakeInfoList[_poolId][_user];
    }

    function _getRewardClaimable(uint256 _poolId, address _user) internal view returns (uint256 rewardClaimable) {
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_poolId][_user];
        StakingLib.Pool memory pool = _pools[_poolId];

        if (stakeInfo.amount == 0 || stakeInfo.withdrawTime != 0) return 0;
        if (stakeInfo.valueDate > blockTimestamp) return 0;

        uint256 stakeDays = (blockTimestamp - stakeInfo.valueDate) / 1 days;

        if (stakeDays > pool.duration) stakeDays = pool.duration;

        rewardClaimable = (stakeInfo.amount * stakeDays * pool.apr) / (daysOfYear * pool.denominatorAPR);
    }

    function getRewardClaimable(uint256 _poolId, address _user) external view returns (uint256) {
        return _getRewardClaimable(_poolId, _user);
    }

    /** 
        @dev user withdraw token & reward (reward is 0 when withdraw before duration)
     */
    function withdraw(uint256 _poolId) external nonReentrant {
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_poolId][_msgSender()];
        StakingLib.Pool memory pool = _pools[_poolId];

        require(stakeInfo.amount > 0 && stakeInfo.withdrawTime == 0, Error.NOTHING_TO_WITHDRAW);

        uint256 interestEndDate = stakeInfo.valueDate + pool.duration * 1 days;

        require(
            blockTimestamp < interestEndDate || interestEndDate + pool.redemptionPeriod * 1 days <= blockTimestamp,
            Error.CANNOT_WITHDRAW_IN_REDEMPTION_PERIOD
        );

        uint256 reward = 0;
        uint256 rewardFullDuration = (stakeInfo.amount * pool.duration * pool.apr) / (daysOfYear * pool.denominatorAPR);
        if (stakeInfo.valueDate + pool.duration * 1 days <= blockTimestamp) {
            reward = rewardFullDuration;
        }

        require(IERC20(pool.stakeAddress).balanceOf(address(this)) >= stakeInfo.amount, Error.NOT_ENOUGH_TOKEN);
        require(IERC20(pool.rewardAddress).balanceOf(address(this)) >= reward, Error.NOT_ENOUGH_REWARD);

        require(IERC20(pool.rewardAddress).transfer(_msgSender(), reward), Error.TRANSFER_REWARD_FAILED);
        require(IERC20(pool.stakeAddress).transfer(_msgSender(), stakeInfo.amount), Error.TRANSFER_TOKEN_FAILED);

        _stakeInfoList[_poolId][_msgSender()].withdrawTime = blockTimestamp;
        _stakedAmounts[pool.stakeAddress] -= stakeInfo.amount;
        _rewardAmounts[pool.rewardAddress] -= rewardFullDuration;

        emit Withdrawn(_msgSender(), _poolId, stakeInfo.amount, reward);
    }

    /**
        @dev all token in all pools holders staked
     */
    function getStakedAmount(address _tokenAddress) external view returns (uint256) {
        return _stakedAmounts[_tokenAddress];
    }

    /**
        @dev all rewards in all pools to paid holders
     */
    function getRewardAmount(address _tokenAddress) external view returns (uint256) {
        return _rewardAmounts[_tokenAddress];
    }

    /** 
        @dev admin withdraws excess token
     */
    function withdrawERC20(address _tokenAddress, uint256 _amount) external nonReentrant onlyAdmin {
        require(_amount != 0, Error.AMOUNT_MUST_GREATER_ZERO);

        require(
            IERC20(_tokenAddress).balanceOf(address(this)) >=
                _stakedAmounts[_tokenAddress] + _rewardAmounts[_tokenAddress] + _amount,
            Error.NOT_ENOUGH_TOKEN
        );

        require(IERC20(_tokenAddress).transfer(_msgSender(), _amount), Error.TRANSFER_TOKEN_FAILED);
    }

    function setBlockTimestamp(uint256 _timestamp) external {
        blockTimestamp = _timestamp;
    }
}
