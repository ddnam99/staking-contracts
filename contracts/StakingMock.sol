// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "hardhat/console.sol";

import "./StakingLib.sol";

contract Staking is Context, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    uint256 public blockTimestamp;

    StakingLib.StakeEvent[] private _stakeEvents;

    // eventId => account => stake info
    mapping(uint256 => mapping(address => StakingLib.StakeInfo)) private _stakeInfoList;
    mapping(IERC20 => uint256) private _stakedAmounts;
    mapping(IERC20 => uint256) private _rewardAmounts;

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ADMIN role required");
        _;
    }

    event NewStakeEvent(uint256 stakeEventId);
    event CloseStakeEvent(uint256 stakeEventId);
    event Staked(address user, uint256 stakeEventId, uint256 amount);
    event Withdrawn(address user, uint256 stakeEventId, uint256 amount, uint256 reward);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        blockTimestamp = block.timestamp;
    }

    function createEvent(
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

        StakingLib.StakeEvent memory stakeEvent = StakingLib.StakeEvent(
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

        _stakeEvents.push(stakeEvent);

        emit NewStakeEvent(_stakeEvents.length - 1);
    }

    /**
        @dev admin close stake event before end time
     */
    function closeStakeEvent(uint256 _stakeEventId) external nonReentrant onlyAdmin {
        _stakeEvents[_stakeEventId].isActive = false;

        emit CloseStakeEvent(_stakeEventId);
    }

    function getStakeEvent(uint256 _stakeEventId) external view returns (StakingLib.StakeEvent memory) {
        return _stakeEvents[_stakeEventId];
    }

    function getAllStakeEvents() external view returns (StakingLib.StakeEvent[] memory) {
        return _stakeEvents;
    }

    function _getCountActiveStakeEvent(uint256 _timestamp) internal view returns (uint256 count) {
        for (uint256 i = 0; i < _stakeEvents.length; i++) {
            if (_stakeEvents[i].isActive && _stakeEvents[i].endTime > _timestamp) {
                count++;
            }
        }
    }

    function getCountActiveStakeEvent() external view returns (uint256) {
        return _getCountActiveStakeEvent(blockTimestamp);
    }

    function getActiveStakeEvents() external view returns (StakingLib.StakeEvent[] memory) {
        uint256 currentTimestamp = blockTimestamp;
        uint256 countActiveStakeEvent = _getCountActiveStakeEvent(currentTimestamp);
        uint256 count = 0;

        StakingLib.StakeEvent[] memory activeStakeEventList = new StakingLib.StakeEvent[](countActiveStakeEvent);

        for (uint256 i = 0; i < _stakeEvents.length; i++) {
            if (_stakeEvents[i].isActive && _stakeEvents[i].endTime > currentTimestamp) {
                activeStakeEventList[count++] = _stakeEvents[i];
            }
        }

        return activeStakeEventList;
    }

    function stake(uint256 _stakeEventId, uint256 _amount) external nonReentrant {
        StakingLib.StakeEvent memory stakeEvent = _stakeEvents[_stakeEventId];

        require(_amount > 0, "Amount must be greater than 0");
        require(stakeEvent.startTime <= blockTimestamp, "It's not time to stake yet");
        require(stakeEvent.isActive && stakeEvent.endTime >= blockTimestamp, "Stake event closed");
        require(stakeEvent.minTokenStake <= _amount, "Amount must be greater or equal min token stake");
        require(stakeEvent.tokenStaked + _amount <= stakeEvent.maxTokenStake, "Over max token stake");
        require(stakeEvent.token.transferFrom(_msgSender(), address(this), _amount), "Transfer failed");

        uint256 reward = (_amount * stakeEvent.rewardPercent) / 100;

        require(
            stakeEvent.rewardToken.balanceOf(address(this)) >=
                _stakedAmounts[stakeEvent.rewardToken] + _rewardAmounts[stakeEvent.rewardToken] + reward,
            "Contract not enough reward"
        );

        StakingLib.StakeInfo memory stakeInfo = StakingLib.StakeInfo(_stakeEventId, blockTimestamp, _amount, 0);

        _stakeEvents[_stakeEventId].tokenStaked += _amount;
        _stakeInfoList[_stakeEventId][_msgSender()] = stakeInfo;

        _stakedAmounts[stakeEvent.token] += _amount;
        _rewardAmounts[stakeEvent.rewardToken] += reward;

        emit Staked(_msgSender(), _stakeEventId, _amount);
    }

    function getStakeInfo(uint256 _stakeEventId, address _user) external view returns (StakingLib.StakeInfo memory) {
        return _stakeInfoList[_stakeEventId][_user];
    }

    function _getRewardClaimable(uint256 _stakeEventId, address _user) internal view returns (uint256 rewardClaimable) {
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_stakeEventId][_user];
        StakingLib.StakeEvent memory stakeEvent = _stakeEvents[_stakeEventId];

        if (stakeInfo.amount == 0 || stakeInfo.withdrawTime != 0) return 0;

        uint256 stakeDays = (blockTimestamp - stakeInfo.stakeTime) / 1 days;

        rewardClaimable = (stakeInfo.amount * stakeDays * stakeEvent.rewardPercent) / (stakeEvent.cliff * 100);
    }

    function getRewardClaimable(uint256 _stakeEventId, address _user) external view returns (uint256) {
        return _getRewardClaimable(_stakeEventId, _user);
    }

    /** 
        @dev user withdraw token & reward
     */
    function withdraw(uint256 _stakeEventId) external nonReentrant {
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_stakeEventId][_msgSender()];
        StakingLib.StakeEvent memory stakeEvent = _stakeEvents[_stakeEventId];

        require(!stakeEvent.isActive || stakeEvent.endTime < blockTimestamp, "It's not time to withdraw yet");
        require(stakeInfo.amount > 0 && stakeInfo.withdrawTime == 0, "Nothing to withdraw");

        uint256 rewardClaimable = _getRewardClaimable(_stakeEventId, _msgSender());

        require(
            stakeEvent.token.balanceOf(address(this)) >= stakeInfo.amount,
            "Staking contract not enough token, contact to dev team"
        );
        require(
            stakeEvent.rewardToken.balanceOf(address(this)) >= rewardClaimable,
            "Staking contract not enough reward, contact to dev team"
        );
        require(stakeEvent.rewardToken.transfer(_msgSender(), rewardClaimable), "Transfer failed");
        require(stakeEvent.token.transfer(_msgSender(), stakeInfo.amount), "Transfer failed");

        uint256 rewardFullCliff = (stakeInfo.amount * stakeEvent.rewardPercent) / 100;

        _stakeInfoList[_stakeEventId][_msgSender()].withdrawTime = blockTimestamp;
        _stakedAmounts[stakeEvent.token] -= stakeInfo.amount;
        _rewardAmounts[stakeEvent.rewardToken] -= rewardFullCliff - rewardClaimable;

        emit Withdrawn(_msgSender(), _stakeEventId, stakeInfo.amount, rewardClaimable);
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
