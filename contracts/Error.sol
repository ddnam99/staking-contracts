// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2;

library Error {
    string public constant ADMIN_ROLE_REQUIRED = "Error: ADMIN role required";

    string public constant POOL_NOT_FOUND = "Error: Pool not found";

    string public constant START_TIME_MUST_IN_FUTURE_DATE = "Error: Start time must be in future date";
    string public constant DURATION_MUST_NOT_EQUAL_ZERO = "Error: Duration must be not equal 0";
    string public constant MIN_TOKEN_STAKE_MUST_GREATER_ZERO = "Error: Min token stake must be greater than 0";
    string public constant MAX_TOKEN_STAKE_MUST_GREATER_MIN_TOKEN_STAKE =
        "Error: Max token stake must be greater than min token stake";
    string public constant MAX_POOL_STAKE_MUST_GREATER_ZERO = "Error: Max pool stake must be greater than 0";
    string public constant DENOMINATOR_APR_MUST_GREATER_ZERO = "Error: Denominator apr must be greater than 0";
    string public constant REWARD_PERCENT_MUST_IN_RANGE_BETWEEN_ONE_TO_HUNDRED =
        "Error: Reward percent must be in range [1, 100]";

    string public constant TRANSFER_REWARD_FAILED = "Error: Transfer reward token failed";
    string public constant TRANSFER_TOKEN_FAILED = "Error: Transfer token failed";

    string public constant DUPLICATE_STAKE = "Error: Duplicate stake";
    string public constant AMOUNT_MUST_GREATER_ZERO = "Error: Amount must be greater than 0";
    string public constant IT_NOT_TIME_STAKE_YET = "Error: It's not time to stake yet";
    string public constant POOL_CLOSED = "Error: Pool closed";
    string public constant POOL_IS_ACTIVE = "Error: Pool is active";
    string public constant AMOUNT_MUST_GREATER_OR_EQUAL_MIN_TOKEN_STAKE =
        "Error: Amount must be greater or equal min token stake";
    string public constant AMOUNT_MUST_LESS_OR_EQUAL_MAX_TOKEN_STAKE =
        "Error: Amount must be less or equal max token stake";
    string public constant OVER_MAX_POOL_STAKE = "Error: Over max pool stake";

    string public constant NOTHING_TO_WITHDRAW = "Error: Nothing to withdraw";
    string public constant NOT_ENOUGH_TOKEN = "Error: Not enough token";
    string public constant CANNOT_UN_STAKE_WHEN_OVER_DURATION = "Error: Cannot un stake when over duration";
    string public constant CANNOT_WITHDRAW_BEFORE_REDEMPTION_PERIOD = "Error: Cannot withdraw before redemption period";

    string public constant UPDATE_WITHDRAW_TIME_LAST_STAKE_FAILED = "Error: Update withdraw time last stake failed";

    string public constant TOKEN_USED_IN_ACTIVE_POOL = "Error: Token being used in an active pool";
}
