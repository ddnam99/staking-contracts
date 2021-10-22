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
        uint256 endTime;
        bool isActive; // isActive = false when admin close before end time
        IERC20 token; // token stake
        uint256 minTokenStake; // minimum token user can stake
        uint256 maxTokenStake; // maximum total user can stake
        uint256 maxPoolToken; // maximum total token all user can stake
        uint256 tokenStaked;
        uint256 duration; // days
        IERC20 rewardToken;
        uint256 rewardPercent;
        bool isIncludeWL;
        uint256 conditionWL; // min token stake to white list
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
