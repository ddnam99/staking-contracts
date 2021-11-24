// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "./StakingLib.sol";
import "./AddressesLib.sol";
import "./Error.sol";

contract Staking is Context, ReentrancyGuard, AccessControl {
    using StakingLib for StakePool[];
    using StakingLib for StakeInfo[];
    using AddressesLib for address[];
    using StakingLib for TopStakeInfo[];

    StakePool[] private _pools;

    uint256 public daysOfYear;

    // poolId => account => stake info
    mapping(uint256 => mapping(address => StakeInfo)) private _stakeInfoList;
    // amount token holders staked
    mapping(address => uint256) private _stakedAmounts;
    // amount rewards to paid holders
    mapping(address => uint256) private _rewardAmounts;
    // history stake by user
    mapping(address => StakeInfo[]) private _stakeHistories;
    // poolId => TopStakeInfo
    mapping(uint256 => TopStakeInfo[]) private _topStakeInfoList;

    address[] private _lockedAddresses;
    mapping(address => uint256) private _lockedAmounts;

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), Error.ADMIN_ROLE_REQUIRED);
        _;
    }

    event NewPool(uint256 poolId);
    event ClosePool(uint256 poolId);
    event Staked(address user, uint256 poolId, uint256 amount);
    event UnStaked(address user, uint256 poolId);
    event Withdrawn(address user, uint256 poolId, uint256 amount, uint256 reward);

    constructor(address _multiSigAccount) {
        renounceRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(DEFAULT_ADMIN_ROLE, _multiSigAccount);
        daysOfYear = 365;
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
        require(_startTime >= block.timestamp, Error.START_TIME_MUST_IN_FUTURE_DATE);
        require(_duration != 0, Error.DURATION_MUST_NOT_EQUAL_ZERO);
        require(_minTokenStake > 0, Error.MIN_TOKEN_STAKE_MUST_GREATER_ZERO);
        require(_maxTokenStake >= _minTokenStake, Error.MAX_TOKEN_STAKE_MUST_GREATER_MIN_TOKEN_STAKE);
        require(_maxPoolStake > 0, Error.MAX_POOL_STAKE_MUST_GREATER_ZERO);
        require(_denominatorAPR > 0, Error.DENOMINATOR_APR_MUST_GREATER_ZERO);
        require(_apr > 0 && _apr <= _denominatorAPR, Error.REWARD_PERCENT_MUST_IN_RANGE_BETWEEN_ONE_TO_HUNDRED);

        uint256 totalReward = (_maxPoolStake * _duration * _apr) / (daysOfYear * _denominatorAPR);

        require(
            IERC20(_rewardAddress).transferFrom(_msgSender(), address(this), totalReward),
            Error.TRANSFER_REWARD_FAILED
        );

        StakePool memory pool = StakePool(
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

        _lockedAddresses.add(_stakeAddress);

        emit NewPool(_pools.length - 1);
    }

    function closePool(uint256 _poolId) external nonReentrant onlyAdmin {
        require(_poolId < _pools.length, Error.POOL_NOT_FOUND);

        _pools[_poolId].isActive = false;

        emit ClosePool(_poolId);
    }

    function getDetailPool(uint256 _poolId) external view returns (StakePool memory) {
        require(_poolId < _pools.length, Error.POOL_NOT_FOUND);

        return _pools[_poolId];
    }

    function getAllPools() external view returns (StakePool[] memory) {
        return _pools;
    }

    function getCountActivePools() external view returns (uint256) {
        return _pools.countActivePools();
    }

    /**
        @dev list pools is active an staked amount less than max pool token
     */
    function getActivePools() external view returns (StakePool[] memory) {
        return _pools.getActivePools();
    }

    /** 
        @dev value date start 07:00 UTC next day
     */
    function stake(uint256 _poolId, uint256 _amount) external nonReentrant {
        require(_poolId < _pools.length, Error.POOL_NOT_FOUND);

        StakePool memory pool = _pools[_poolId];
        StakeInfo memory stakeInfo = _stakeInfoList[_poolId][_msgSender()];

        require(stakeInfo.amount == 0 || stakeInfo.withdrawTime > 0, Error.DUPLICATE_STAKE);

        require(pool.isActive, Error.POOL_CLOSED);
        require(_amount > 0, Error.AMOUNT_MUST_GREATER_ZERO);
        require(pool.startTime <= block.timestamp, Error.IT_NOT_TIME_STAKE_YET);
        require(pool.minTokenStake <= _amount, Error.AMOUNT_MUST_GREATER_OR_EQUAL_MIN_TOKEN_STAKE);
        require(pool.maxTokenStake >= _amount, Error.AMOUNT_MUST_LESS_OR_EQUAL_MAX_TOKEN_STAKE);
        require(pool.totalStaked + _amount <= pool.maxPoolStake, Error.OVER_MAX_POOL_STAKE);

        require(
            IERC20(pool.stakeAddress).transferFrom(_msgSender(), address(this), _amount),
            Error.TRANSFER_TOKEN_FAILED
        );

        uint256 reward = (_amount * pool.duration * pool.apr) / (daysOfYear * pool.denominatorAPR);

        // 07:00 UTC next day
        uint256 valueDate = (block.timestamp / 1 days) * 1 days + 1 days + 7 hours;

        stakeInfo = StakeInfo(_poolId, block.timestamp, valueDate, _amount, 0);

        _pools[_poolId].totalStaked += _amount;
        _stakeInfoList[_poolId][_msgSender()] = stakeInfo;
        _stakeHistories[_msgSender()].push(stakeInfo);

        _stakedAmounts[pool.stakeAddress] += _amount;
        _rewardAmounts[pool.rewardAddress] += reward;

        _lockedAmounts[pool.stakeAddress] += _amount;

        _topStakeInfoList[_poolId].add(_msgSender(), _amount);

        emit Staked(_msgSender(), _poolId, _amount);
    }

    /**
        @dev if pool include white list and user stake amount qualified 
     */
    function checkWhiteList(uint256 _poolId, address _user) external view returns (bool) {
        require(_poolId < _pools.length, Error.POOL_NOT_FOUND);

        StakePool memory pool = _pools[_poolId];
        StakeInfo memory stakeInfo = _stakeInfoList[_poolId][_user];

        if (!pool.useWhitelist) return false;
        if (stakeInfo.withdrawTime != 0 && stakeInfo.valueDate + pool.duration * 1 days > stakeInfo.withdrawTime)
            return false;
        if (pool.minStakeWhitelist > stakeInfo.amount) return false;

        return true;
    }

    /**
        @dev stake info in pool by user
     */
    function getStakeInfo(uint256 _poolId, address _user) external view returns (StakeInfo memory) {
        return _stakeInfoList[_poolId][_user];
    }

    function getStakeHistories(address _user) external view returns (StakeInfo[] memory) {
        return _stakeHistories[_user];
    }

    function getStakeClaims(address _user) external view returns (RewardInfo[] memory stakeClaims) {
        stakeClaims = new RewardInfo[](_stakeHistories[_user].countStakeAvailable());
        uint256 count = 0;

        for (uint256 i = 0; i < _stakeHistories[_user].length; i++) {
            if (_stakeHistories[_user][i].withdrawTime == 0) {
                StakeInfo memory stakeInfo = _stakeHistories[_user][i];
                StakePool memory pool = _pools[stakeInfo.poolId];

                uint256 rewardAmount = _getRewardClaimable(pool.id, _user);

                uint256 interestEndDate = stakeInfo.valueDate + pool.duration * 1 days;
                bool canClaim = interestEndDate + pool.redemptionPeriod * 1 days <= block.timestamp;

                stakeClaims[count++] = RewardInfo(
                    pool.id,
                    pool.stakeAddress,
                    pool.rewardAddress,
                    stakeInfo.amount,
                    rewardAmount,
                    canClaim
                );
            }
        }
    }

    function _getRewardClaimable(uint256 _poolId, address _user) internal view returns (uint256 rewardClaimable) {
        StakeInfo memory stakeInfo = _stakeInfoList[_poolId][_user];
        StakePool memory pool = _pools[_poolId];

        if (stakeInfo.amount == 0 || stakeInfo.withdrawTime != 0) return 0;
        if (stakeInfo.valueDate > block.timestamp) return 0;

        uint256 lockedDays = (block.timestamp - stakeInfo.valueDate) / 1 days;

        if (lockedDays > pool.duration) lockedDays = pool.duration;

        rewardClaimable = (stakeInfo.amount * lockedDays * pool.apr) / (daysOfYear * pool.denominatorAPR);
    }

    function getRewardClaimable(uint256 _poolId, address _user) external view returns (uint256) {
        require(_poolId < _pools.length, Error.POOL_NOT_FOUND);

        return _getRewardClaimable(_poolId, _user);
    }

    /** 
        @dev user withdraw token staked without reward
     */
    function unStake(uint256 _poolId) external nonReentrant {
        require(_poolId < _pools.length, Error.POOL_NOT_FOUND);

        StakeInfo memory stakeInfo = _stakeInfoList[_poolId][_msgSender()];
        StakePool memory pool = _pools[_poolId];

        require(stakeInfo.amount > 0, Error.NOTHING_TO_WITHDRAW);

        uint256 interestEndDate = stakeInfo.valueDate + pool.duration * 1 days;

        require(block.timestamp < interestEndDate, Error.CANNOT_UN_STAKE_WHEN_OVER_DURATION);

        uint256 rewardFullDuration = (stakeInfo.amount * pool.duration * pool.apr) / (daysOfYear * pool.denominatorAPR);

        require(IERC20(pool.stakeAddress).transfer(_msgSender(), stakeInfo.amount), Error.TRANSFER_TOKEN_FAILED);

        _pools[_poolId].totalStaked -= stakeInfo.amount;

        _stakedAmounts[pool.stakeAddress] -= stakeInfo.amount;
        _rewardAmounts[pool.rewardAddress] -= rewardFullDuration;

        _topStakeInfoList[_poolId].sub(_msgSender(), stakeInfo.amount);

        delete _stakeInfoList[_poolId][_msgSender()];
        require(
            _stakeHistories[_msgSender()].updateWithdrawTimeLastStake(_poolId, block.timestamp),
            Error.UPDATE_WITHDRAW_TIME_LAST_STAKE_FAILED
        );

        emit UnStaked(_msgSender(), _poolId);
    }

    /** 
        @dev user withdraw token & reward
     */
    function withdraw(uint256 _poolId) external nonReentrant {
        require(_poolId < _pools.length, Error.POOL_NOT_FOUND);

        StakeInfo memory stakeInfo = _stakeInfoList[_poolId][_msgSender()];
        StakePool memory pool = _pools[_poolId];

        require(stakeInfo.amount > 0 && stakeInfo.withdrawTime == 0, Error.NOTHING_TO_WITHDRAW);

        uint256 interestEndDate = stakeInfo.valueDate + pool.duration * 1 days;

        require(
            interestEndDate + pool.redemptionPeriod * 1 days <= block.timestamp,
            Error.CANNOT_WITHDRAW_BEFORE_REDEMPTION_PERIOD
        );

        uint256 reward = _getRewardClaimable(_poolId, _msgSender());

        if (pool.stakeAddress == pool.rewardAddress) {
            require(
                IERC20(pool.rewardAddress).transfer(_msgSender(), stakeInfo.amount + reward),
                Error.TRANSFER_REWARD_FAILED
            );
        } else {
            require(IERC20(pool.rewardAddress).transfer(_msgSender(), reward), Error.TRANSFER_REWARD_FAILED);
            require(IERC20(pool.stakeAddress).transfer(_msgSender(), stakeInfo.amount), Error.TRANSFER_TOKEN_FAILED);
        }

        _stakedAmounts[pool.stakeAddress] -= stakeInfo.amount;
        _rewardAmounts[pool.rewardAddress] -= reward;

        _stakeInfoList[_poolId][_msgSender()].withdrawTime = block.timestamp;
        require(
            _stakeHistories[_msgSender()].updateWithdrawTimeLastStake(_poolId, block.timestamp),
            Error.UPDATE_WITHDRAW_TIME_LAST_STAKE_FAILED
        );

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

    function getTotalLocked() external view returns (LockedInfo[] memory lockedInfoList) {
        lockedInfoList = new LockedInfo[](_lockedAddresses.length);
        for (uint256 i = 0; i < _lockedAddresses.length; i++) {
            lockedInfoList[i] = LockedInfo(_lockedAddresses[i], _lockedAmounts[_lockedAddresses[i]]);
        }
    }

    function getTopStakeInfoList(uint256 _poolId) external view returns (TopStakeInfo[] memory) {
        return _topStakeInfoList[_poolId];
    }

    /** 
        @dev admin withdraws excess token
     */
    function withdrawERC20(address _tokenAddress, uint256 _amount) external nonReentrant onlyAdmin {
        require(_amount != 0, Error.AMOUNT_MUST_GREATER_ZERO);

        bool canWithdraw = true;
        StakePool[] memory activePools = _pools.getActivePools();
        for(uint256 i = 0; i < activePools.length; i++){
            if(activePools[i].rewardAddress == _tokenAddress){
                canWithdraw = false;
                break;
            }
        }
        require(canWithdraw, Error.TOKEN_USED_IN_ACTIVE_POOL);

        require(
            IERC20(_tokenAddress).balanceOf(address(this)) >=
                _stakedAmounts[_tokenAddress] + _rewardAmounts[_tokenAddress] + _amount,
            Error.NOT_ENOUGH_TOKEN
        );

        require(IERC20(_tokenAddress).transfer(_msgSender(), _amount), Error.TRANSFER_TOKEN_FAILED);
    }
}
