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
    event Withdrawn(address user, uint stakeEventid, uint256 amount, uint256 reward);

    constructor(address _multiSigAccount) {
        _setupRole(DEFAULT_ADMIN_ROLE, _multiSigAccount);
        renounceRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function createEvent(
        uint256 _startTime,
        uint256 _endTime,
        address _token,
        uint256 _cliff,
        address _rewardToken,
        uint256 _rewardPercent
    ) external nonReentrant onlyAdmin {
        StakingLib.StakeEvent memory stakeEvent = StakingLib.StakeEvent(
            _startTime,
            _endTime,
            true,
            IERC20(_token),
            _cliff,
            IERC20(_rewardToken),
            _rewardPercent
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

        require(_amount != 0, "Amount must greater 0");
        require(stakeEvent.isActive && stakeEvent.endTime >= block.timestamp, "Stake event closed");
        require(stakeEvent.token.transferFrom(_msgSender(), address(this), _amount), "transfer failed");

        StakingLib.StakeInfo memory stakeInfo = StakingLib.StakeInfo(_stakeEventId, block.timestamp, _amount, false);

        _stakeInfoList[_stakeEventId][_msgSender()] = stakeInfo;

        emit Staked(_msgSender(), _stakeEventId, _amount);
    }

    function _getRewardClaimable(uint256 _stakeEventId) internal view returns (uint256 rewardClaimable) {
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_stakeEventId][_msgSender()];
        StakingLib.StakeEvent memory stakeEvent = _stakeEvents[_stakeEventId];

        if (stakeInfo.amount == 0 || stakeInfo.isClaimed) return 0;

        uint256 stakeDays = (block.timestamp - stakeInfo.stakeTime) / 1 days;

        rewardClaimable = (stakeInfo.amount * stakeDays * stakeEvent.rewardPercent) / (stakeEvent.cliff * 100);
    }

    function getRewardClaimable(uint256 _stakeEventId) external view returns (uint256) {
        return _getRewardClaimable(_stakeEventId);
    }

    function withrraw(uint256 _stakeEventId) external nonReentrant {
        StakingLib.StakeInfo memory stakeInfo = _stakeInfoList[_stakeEventId][_msgSender()];
        StakingLib.StakeEvent memory stakeEvent = _stakeEvents[_stakeEventId];

        require(stakeInfo.amount > 0 || stakeInfo.isClaimed, "Nothing to withdraw");

        uint256 rewardClaimable = _getRewardClaimable(_stakeEventId);
        require(stakeEvent.rewardToken.transfer(_msgSender(), rewardClaimable), "transfer failed");
        require(stakeEvent.token.transfer(_msgSender(), stakeInfo.amount), "transfer failed");

        _stakeInfoList[_stakeEventId][_msgSender()].isClaimed = true;

        emit Withdrawn(_msgSender(), _stakeEventId, stakeInfo.amount, rewardClaimable);
    }
}
