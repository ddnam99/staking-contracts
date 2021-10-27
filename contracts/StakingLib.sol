// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2;

/**
    @dev represents one pool
    */
struct StakePool {
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

struct RewardInfo {
    uint256 poolId;
    address stakeAddress;
    address rewardAddress;
    uint256 amount;
    uint256 claimableReward;
    bool canClaim;
}

struct LockedInfo {
    address tokenAddress;
    uint256 amount;
}

library StakingLib {
    function updateWithdrawTimeLastStake(
        StakeInfo[] storage self,
        uint256 poolId,
        uint256 withdrawTime
    ) internal returns (bool) {
        for (uint256 i = 0; i < self.length; i++) {
            if (self[i].poolId == poolId && self[i].withdrawTime == 0) {
                self[i].withdrawTime = withdrawTime;
                return true;
            }
        }

        return false;
    }

    /**
        @dev count pools is active and staked amount less than max pool token
     */
    function countActivePools(StakePool[] storage self) internal view returns (uint256 count) {
        for (uint256 i = 0; i < self.length; i++) {
            if (self[i].isActive && self[i].totalStaked < self[i].maxPoolStake) {
                count++;
            }
        }
    }

    function getActivePools(StakePool[] storage self) internal view returns (StakePool[] memory activePools) {
        activePools = new StakePool[](countActivePools(self));
        uint256 count = 0;

        for (uint256 i = 0; i < self.length; i++) {
            if (self[i].isActive && self[i].totalStaked < self[i].maxPoolStake) {
                activePools[count++] = self[i];
            }
        }
    }

    function countStakeAvailable(StakeInfo[] storage self) internal view returns (uint256 count) {
        count = 0;
        for (uint256 i = 0; i < self.length; i++) {
            if (self[i].withdrawTime == 0) count++;
        }
    }
}
