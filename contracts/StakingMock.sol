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
    mapping(uint256 => mapping(address => StakingLib.StakeInfo)) _stakeInfoList;

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
        require(_startTime > blockTimestamp, "Start time must be in future date");
        require(_endTime > _startTime, "End time must be greater than start time");
        require(_cliff != 0, "Cliff time must be not equal 0");
        require(_maxTokenStake > 0, "Max token stake must be grater than 0");
        require(_rewardPercent > 0 && _rewardPercent <= 100, "Reward percent must be in range [1, 100]");

        uint256 totalReward = (_maxTokenStake * _rewardPercent) / 100;

        require(_rewardToken.transferFrom(_msgSender(), address(this), totalReward), "Transfer reward token faild");

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

    function closeStakeEvent(uint256 _stakeEventId) external nonReentrant onlyAdmin {
        _stakeEvents[_stakeEventId].isActive = false;

        emit CloseStakeEvent(_stakeEventId);
    }

    function getStakeEventInfo(uint256 _stakeEventId) external view returns (StakingLib.StakeEvent memory) {
        return _stakeEvents[_stakeEventId];
    }

    function getStakeEventList() external view returns (StakingLib.StakeEvent[] memory) {
        return _stakeEvents;
    }

    function stake(uint256 _stakeEventId, uint256 _amount) external nonReentrant {
        StakingLib.StakeEvent memory stakeEvent = _stakeEvents[_stakeEventId];

        require(_amount > 0, "Amount must greater 0");
        require(stakeEvent.startTime <= blockTimestamp, "It's not time to stake yet");
        require(stakeEvent.isActive && stakeEvent.endTime >= blockTimestamp, "Stake event closed");
        require(stakeEvent.minTokenStake <= _amount, "Amount must be greater or equal minTokenStake");
        require(stakeEvent.tokenStaked + _amount <= stakeEvent.maxTokenStake, "Over max token stake");
        require(stakeEvent.token.transferFrom(_msgSender(), address(this), _amount), "Transfer failed");

        StakingLib.StakeInfo memory stakeInfo = StakingLib.StakeInfo(_stakeEventId, blockTimestamp, _amount, false);

        _stakeEvents[_stakeEventId].tokenStaked += _amount;
        _stakeInfoList[_stakeEventId][_msgSender()] = stakeInfo;

        emit Staked(_msgSender(), _stakeEventId, _amount);
    }

    function _getRewardClaimable(uint256 _stakeEventId) internal view returns (uint256 rewardClaimable) {
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_stakeEventId][_msgSender()];
        StakingLib.StakeEvent memory stakeEvent = _stakeEvents[_stakeEventId];

        if (stakeInfo.amount == 0 || stakeInfo.isClaimed) return 0;

        uint256 stakeDays = (blockTimestamp - stakeInfo.stakeTime) / 1 days;

        rewardClaimable = (stakeInfo.amount * stakeDays * stakeEvent.rewardPercent) / (stakeEvent.cliff * 100);
    }

    function getRewardClaimable(uint256 _stakeEventId) external view returns (uint256) {
        return _getRewardClaimable(_stakeEventId);
    }

    function withdraw(uint256 _stakeEventId) external nonReentrant {
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_stakeEventId][_msgSender()];
        StakingLib.StakeEvent memory stakeEvent = _stakeEvents[_stakeEventId];

        require(stakeInfo.amount > 0 || stakeInfo.isClaimed, "Nothing to withdraw");
        require(!stakeEvent.isActive || stakeEvent.endTime < blockTimestamp, "It's not time to withdraw yet");

        uint256 rewardClaimable = _getRewardClaimable(_stakeEventId);

        require(stakeEvent.rewardToken.balanceOf(address(this)) >= rewardClaimable, "Not enough reward");
        require(stakeEvent.rewardToken.transfer(_msgSender(), rewardClaimable), "Transfer failed");
        require(stakeEvent.token.transfer(_msgSender(), stakeInfo.amount), "Transfer failed");

        _stakeInfoList[_stakeEventId][_msgSender()].isClaimed = true;

        emit Withdrawn(_msgSender(), _stakeEventId, stakeInfo.amount, rewardClaimable);
    }

    function withdrawReward(IERC20 _token, uint256 _amount) external nonReentrant onlyAdmin {
        require(_amount != 0, "Amount must be not equal 0");
        require(_token.transfer(_msgSender(), _amount), "Transfer failed");
    }

    function setBlockTimestamp(uint256 _timestamp) external onlyAdmin {
        blockTimestamp = _timestamp;
    }
}
