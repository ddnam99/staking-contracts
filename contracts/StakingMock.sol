// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "hardhat/console.sol";

import "./StakingLib.sol";

contract StakingMock is Context, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    uint256 public blockTimestamp;

    StakingLib.Pool[] private _pools;

    // poolId => account => stake info
    mapping(uint256 => mapping(address => StakingLib.StakeInfo)) private _stakeInfoList;
    mapping(IERC20 => uint256) private _stakedAmounts;
    mapping(IERC20 => uint256) private _rewardAmounts;

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ADMIN role required");
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
        uint256 _endTime,
        IERC20 _token,
        uint256 _minTokenStake,
        uint256 _maxTokenStake,
        uint256 _cliff,
        IERC20 _rewardToken,
        uint256 _rewardPercent
    ) external nonReentrant onlyAdmin {
        require(_startTime >= blockTimestamp, "Start time must be in future date");
        require(_endTime > _startTime, "End time must be greater than start time");
        require(_cliff != 0, "Cliff time must be not equal 0");
        require(_maxTokenStake > 0, "Max token stake must be greater than 0");
        require(_rewardPercent > 0 && _rewardPercent <= 100, "Reward percent must be in range [1, 100]");

        uint256 totalReward = (_maxTokenStake * _rewardPercent) / 100;

        require(_rewardToken.transferFrom(_msgSender(), address(this), totalReward), "Transfer reward token failed");

        StakingLib.Pool memory pool = StakingLib.Pool(
            _startTime,
            _endTime,
            true,
            _token,
            _minTokenStake,
            _maxTokenStake,
            0,
            _cliff,
            _rewardToken,
            _rewardPercent,
            totalReward
        );

        _pools.push(pool);

        emit NewPool(_pools.length - 1);
    }

    /**
        @dev admin close pool before end time
     */
    function closePool(uint256 _poolId) external nonReentrant onlyAdmin {
        _pools[_poolId].isActive = false;

        emit ClosePool(_poolId);
    }

    function getPool(uint256 _poolId) external view returns (StakingLib.Pool memory) {
        return _pools[_poolId];
    }

    function getAllPools() external view returns (StakingLib.Pool[] memory) {
        return _pools;
    }

    function _getCountActivePools(uint256 _timestamp) internal view returns (uint256 count) {
        for (uint256 i = 0; i < _pools.length; i++) {
            if (_pools[i].isActive && _pools[i].endTime > _timestamp) {
                count++;
            }
        }
    }

    function _getCountActivePools() external view returns (uint256) {
        return _getCountActivePools(blockTimestamp);
    }

    function getActivePools() external view returns (StakingLib.Pool[] memory) {
        uint256 currentTimestamp = blockTimestamp;
        uint256 countActivePools = _getCountActivePools(currentTimestamp);
        uint256 count = 0;

        StakingLib.Pool[] memory activePools = new StakingLib.Pool[](countActivePools);

        for (uint256 i = 0; i < _pools.length; i++) {
            if (_pools[i].isActive && _pools[i].endTime > currentTimestamp) {
                activePools[count++] = _pools[i];
            }
        }

        return activePools;
    }

    function stake(uint256 _poolId, uint256 _amount) external nonReentrant {
        StakingLib.Pool memory pool = _pools[_poolId];

        require(_amount > 0, "Amount must be greater than 0");
        require(pool.startTime <= blockTimestamp, "It's not time to stake yet");
        require(pool.isActive && pool.endTime >= blockTimestamp, "Pool closed");
        require(pool.minTokenStake <= _amount, "Amount must be greater or equal min token stake");
        require(pool.tokenStaked + _amount <= pool.maxTokenStake, "Over max token stake");
        require(pool.token.transferFrom(_msgSender(), address(this), _amount), "Transfer failed");

        uint256 reward = (_amount * pool.rewardPercent) / 100;

        require(
            pool.rewardToken.balanceOf(address(this)) >=
                _stakedAmounts[pool.rewardToken] + _rewardAmounts[pool.rewardToken] + reward,
            "Contract not enough reward"
        );

        StakingLib.StakeInfo memory stakeInfo = StakingLib.StakeInfo(_poolId, blockTimestamp, _amount, 0);

        _pools[_poolId].tokenStaked += _amount;
        _stakeInfoList[_poolId][_msgSender()] = stakeInfo;

        _stakedAmounts[pool.token] += _amount;
        _rewardAmounts[pool.rewardToken] += reward;

        emit Staked(_msgSender(), _poolId, _amount);
    }

    function getStakeInfo(uint256 _poolId, address _user) external view returns (StakingLib.StakeInfo memory) {
        return _stakeInfoList[_poolId][_user];
    }

    function _getRewardClaimable(uint256 _poolId, address _user) internal view returns (uint256 rewardClaimable) {
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_poolId][_user];
        StakingLib.Pool memory pool = _pools[_poolId];

        if (stakeInfo.amount == 0 || stakeInfo.withdrawTime != 0) return 0;

        uint256 stakeDays = (blockTimestamp - stakeInfo.stakeTime) / 1 days;

        rewardClaimable = (stakeInfo.amount * stakeDays * pool.rewardPercent) / (pool.cliff * 100);
    }

    function getRewardClaimable(uint256 _poolId, address _user) external view returns (uint256) {
        return _getRewardClaimable(_poolId, _user);
    }

    /** 
        @dev user withdraw token & reward
     */
    function withdraw(uint256 _poolId) external nonReentrant {
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_poolId][_msgSender()];
        StakingLib.Pool memory pool = _pools[_poolId];

        require(!pool.isActive || pool.endTime < blockTimestamp, "It's not time to withdraw yet");
        require(stakeInfo.amount > 0 && stakeInfo.withdrawTime == 0, "Nothing to withdraw");

        uint256 rewardClaimable = _getRewardClaimable(_poolId, _msgSender());

        require(
            pool.token.balanceOf(address(this)) >= stakeInfo.amount,
            "Staking contract not enough token, contact to dev team"
        );
        require(
            pool.rewardToken.balanceOf(address(this)) >= rewardClaimable,
            "Staking contract not enough reward, contact to dev team"
        );
        require(pool.rewardToken.transfer(_msgSender(), rewardClaimable), "Transfer failed");
        require(pool.token.transfer(_msgSender(), stakeInfo.amount), "Transfer failed");

        uint256 rewardFullCliff = (stakeInfo.amount * pool.rewardPercent) / 100;

        _stakeInfoList[_poolId][_msgSender()].withdrawTime = blockTimestamp;
        _stakedAmounts[pool.token] -= stakeInfo.amount;
        _rewardAmounts[pool.rewardToken] -= rewardFullCliff - rewardClaimable;

        emit Withdrawn(_msgSender(), _poolId, stakeInfo.amount, rewardClaimable);
    }

    function getStakedAmount(IERC20 _token) external view returns (uint256) {
        return _stakedAmounts[_token];
    }

    function getRewardAmount(IERC20 _token) external view returns (uint256) {
        return _rewardAmounts[_token];
    }

    /** 
        @dev admin withdraws excess token
     */
    function withdrawERC20(IERC20 _token, uint256 _amount) external nonReentrant onlyAdmin {
        require(_amount != 0, "Amount must be not equal 0");

        require(
            _token.balanceOf(address(this)) >= _stakedAmounts[_token] + _rewardAmounts[_token] + _amount,
            "Not enough token"
        );

        require(_token.transfer(_msgSender(), _amount), "Transfer failed");
    }

    function setBlockTimestamp(uint256 _timestamp) external onlyAdmin {
        blockTimestamp = _timestamp;
    }
}
