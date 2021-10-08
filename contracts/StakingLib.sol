// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library StakingLib {
    struct StakeEvent {
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        IERC20 token;
        uint256 cliff; // days
        IERC20 rewardToken;
        uint256 rewardPercent;
    }

    struct StakeInfo {
        uint256 stakingEventId;
        uint256 stakeTime;
        uint256 amount;
        bool isClaimed;
    }
}
