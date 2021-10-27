## Staking

This contract locks ERC-20 tokens and issues back staked tokens. These staked tokens are not transferrable, but they can be delegated to other users. Tokens unlock linearly.

User locks tokens on `startTime` moment.

## Features

- **stake** - create new `Stake`. Initial bias of the `Stake` depends on locked token amount and other parameters of the `Stake`
- **withdraw** - withdraw tokens. Cannot withdraw if stake in duration redemptionPeriod.

## Functions to read the data

- **getAllPools**() - get all pools
- **getDetailPool**() - get detail pool
- **getCountActivePools**() - get count active pools
- **getActivePools**() - get pools is active an staked amount less than max pool token
- **getStakeInfo**() - get stake info in pool by user
- **getStakeHistories**() - get stake info history by user
- **getStakeAvailableList**() - get stake available list
- **getRewardClaimable**(uint poolId, address user) - get reward claimable of user in pool
- **getStakedAmount**() - get all token in all pools holders staked
- **getRewardAmount**() - get all rewards in all pools to paid holders
- **checkWhiteList**() - if pool include white list and user stake amount qualified

## Functions for owner only

- **createPool**() - create pool
- **closePool**() - close pool
- **withdrawERC20**() - admin withdraws excess token

#### Creating Stake

**stake**
When creating the `Stake`, amount of `Stake` will be calculated using a special formula, but the function describing stake
balance will be almost the same as the function of locked tokens (it will be only multiplied by specific value)

#### Stake value calculation

##### Contract events

Staking contract emits these events:

- Staked - when stake is created
- Withdrawn - when user withdraws tokens
- NewPool - when admin created pool
- ClosePool - when admin close pool
