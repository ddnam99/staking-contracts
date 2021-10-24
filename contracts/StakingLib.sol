// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library StakingLib {
    /**
        @dev represents one pool
     */
    struct Pool {
        uint256 id;
        uint256 startTime;
        bool isActive;
        address stakeAddress;
        address rewardAddress;
        uint256 minTokenStake; // minimum token user can stake
        uint256 maxTokenStake; // maximum total user can stake
        uint256 maxPoolStake; // maximum total token all user can stake
        uint256 totalStaked;
        uint256 duration; // days
        uint256 redemptionPeriod; // days
        uint256 apr;
        uint256 denominatorAPR;
        bool useWhitelist;
        uint256 minStakeWhitelist; // min token stake to white list
    }

    /**
        @dev represents one user stake in one pool
     */
    struct StakeInfo {
        uint256 poolId;
        uint256 stakeTime;
        uint256 valueDate;
        uint256 amount;
        uint256 withdrawTime;
    }
}
