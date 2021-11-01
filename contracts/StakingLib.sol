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

struct TopStakeInfo {
    address user;
    uint256 amount;
}

library StakingLib {
    function add(
        TopStakeInfo[] storage self,
        address user,
        uint256 amount
    ) internal {
        for (uint256 i = 0; i < self.length; i++) {
            if (self[i].user == user) {
                self[i].amount += amount;
                quickSort(self, 0, int256(self.length - 1));
                return;
            }
        }

        self.push(TopStakeInfo(user, amount));
        quickSort(self, 0, int256(self.length - 1));
    }

    function sub(
        TopStakeInfo[] storage self,
        address user,
        uint256 amount
    ) internal {
        for (uint256 i = 0; i < self.length; i++) {
            if (self[i].user == user) {
                self[i].amount -= amount;
                break;
            }
        }

        quickSort(self, 0, int256(self.length - 1));
    }

    function quickSort(
        TopStakeInfo[] memory self,
        int256 left,
        int256 right
    ) internal {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = self[uint256(left + (right - left) / 2)].amount;
        while (i <= j) {
            while (self[uint256(i)].amount < pivot) i++;
            while (pivot < self[uint256(j)].amount) j--;
            if (i <= j) {
                (self[uint256(i)], self[uint256(j)]) = (self[uint256(j)], self[uint256(i)]);
                i++;
                j--;
            }
        }
        if (left < j) quickSort(self, left, j);
        if (i < right) quickSort(self, i, right);
    }

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
