# StakingFactory Contract

## Overview
The `StakingFactory` contract is responsible for managing multiple staking pools. It allows users to deposit and withdraw tokens from different pools, earn rewards, and provides functions for managing and updating pools.

## Features
- **Multi-pool Management**: Supports multiple staking pools with different configurations.
- **Reward Distribution**: Distributes rewards based on the staked amount and allocation points of each pool.
- **Flexible Pool Updates**: Allows for the addition and configuration of pools dynamically.
- **Security Measures**: Implements security measures such as reentrancy guards and various checks.

## Contract Logic
### State Variables
- `rewardToken`: Address of the reward token.
- `fundSource`: Address of the fund source.
- `rewardTokenPerBlock`: Reward tokens distributed per block.
- `poolInfo`: Array containing information about each pool.
- `userInfo`: Mapping storing user information for each pool.
- `poolsAdded`: Mapping to check if a pool has already been added.
- `totalAllocPoint`: Total allocation points for all pools.

### Structs
- **UserInfo**: Stores the number of shares and reward debt for a user.
- **PoolInfo**: Stores the token, allocation point, last reward block, accumulated reward per share, and pool address.

### Modifiers
- `zeroAmountCheck`: Checks if the amount is zero.
- `zeroAllocCheck`: Checks if the allocation point is zero.
- `zeroAddressCheck`: Checks if the address is zero.
- `validPID`: Checks if the pool ID is valid.

### Events
- `Deposit`: Emitted when a user deposits tokens.
- `Withdraw`: Emitted when a user withdraws tokens.
- `EmergencyWithdraw`: Emitted when a user performs an emergency withdrawal.

### Functions
- `constructor`: Initializes the contract with the reward token and fund source addresses.
- `poolLength`: Returns the number of pools.
- `add`: Adds a new pool.
- `set`: Updates the allocation points for a pool.
- `getMultiplier`: Calculates the reward multiplier.
- `pendingRewardToken`: Returns the pending reward tokens for a user.
- `stakedtokenTokens`: Returns the amount of staked tokens for a user.
- `massUpdatePools`: Updates all pools.
- `updatePool`: Updates a specific pool.
- `deposit`: Allows a user to deposit tokens into a pool.
- `withdraw`: Allows a user to withdraw tokens from a pool.
- `withdrawAll`: Allows a user to withdraw all tokens from a pool.
- `claimReward`: Allows a user to claim rewards from a pool.

# StakingPool Contract

## Overview
The `StakingPool` contract allows users to stake tokens to earn rewards. It provides functions for depositing, withdrawing, and claiming rewards, and is designed to work with the `StakingFactory` contract.

## Features
- **Token Staking**: Allows users to stake tokens to earn rewards.
- **Reward Calculation**: Calculates rewards based on the staked amount and time.
- **Security Measures**: Implements security measures such as reentrancy guards and various checks.

## Contract Logic
### State Variables
- `token`: The token being staked.
- `rewardToken`: The reward token.
- `rewardTokenPerBlock`: Reward tokens distributed per block.
- `totalStaked`: Total amount of tokens staked.
- `totalRewards`: Total rewards distributed.
- `rewardDebt`: Mapping to store user reward debt.
- `staked`: Mapping to store user staked amount.

### Structs
- **UserInfo**: Stores the amount of tokens staked and the reward debt for a user.

### Events
- `Deposit`: Emitted when a user deposits tokens.
- `Withdraw`: Emitted when a user withdraws tokens.
- `ClaimReward`: Emitted when a user claims rewards.

### Functions
- `constructor`: Initializes the contract with the staking token and reward token addresses.
- `deposit`: Allows a user to deposit tokens.
- `withdraw`: Allows a user to withdraw tokens.
- `claimReward`: Allows a user to claim rewards.
- `updatePool`: Updates the pool with the latest reward calculations.
- `calculateReward`: Calculates the reward for a user.
