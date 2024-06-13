// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./Authorizable.sol";
import "./interfaces/IStakingPool.sol";

/// @title StakingFactory
/// @notice This contract manages multiple StakingPool contracts and distributes rewards to users who stake their LP tokens.
contract StakingFactory is Authorizable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    error ZeroAmountInserted();
    error ZeroAllocPointInserted();
    error InvalidPoolId();
    error ZeroAddressInserted();
    error InvalidPID();
    error UserSharesZero();
    error TotalSharesZero();
    error RewardTokenTransfer();
    error TokenPoolAlreadyAdded();

    /// @dev Struct to store information about each user's stake in a pool.
    struct UserInfo {
        uint256 shares; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    /// @dev Struct to store information about each staking pool.
    struct PoolInfo {
        IERC20 token; // Address of the pool token.
        uint256 allocPoint; // Allocation points assigned to the pool.
        uint256 lastRewardBlock; // Last block number where reward distribution occurred.
        uint256 accRewardTokenPerShare; // Accumulated reward tokens per share, times 1e12.
        address pool; // Staking Pool address.
    }

    /// @notice Emitted when a user deposits LP tokens into a pool.
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    /// @notice Emitted when a user withdraws LP tokens from a pool.
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    /// @notice Emitted when a user performs an emergency withdrawal from a pool.
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    address public rewardToken;
    address public fundSource; // Source of reward tokens.

    uint256 public rewardTokenPerBlock; // Reward tokens distributed per block.

    PoolInfo[] public poolInfo; // Array of all pools.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // User stake information for each pool.
    mapping(address => bool) public poolsAdded; // Tracks if a pool token has already been added.
    uint256 public totalAllocPoint; // Total allocation points across all pools.

    modifier zeroAmountCheck(uint256 amount) {
        if (amount == 0) {
            revert ZeroAmountInserted();
        }
        _;
    }

    modifier zeroAllocCheck(uint256 amount) {
        if (amount == 0) {
            revert ZeroAllocPointInserted();
        }
        _;
    }

    modifier zeroAddressCheck(address _address) {
        if (_address == address(0)) {
            revert ZeroAddressInserted();
        }
        _;
    }

    modifier validPID(uint256 _pid) {
        if (_pid >= poolInfo.length) {
            revert InvalidPID();
        }
        _;
    }

    /// @notice Initializes the StakingFactory contract with the reward token and fund source addresses.
    /// @param _rewardToken The address of the reward token.
    /// @param _fundSource The address from which reward tokens will be pulled for distribution.
    constructor(address _rewardToken, address _fundSource) Ownable() {
        rewardToken = _rewardToken;
        fundSource = _fundSource;
    }

    /// @notice Adds a new staking pool to the factory.
    /// @dev Only callable by the contract owner.
    /// @param _allocPoint Allocation points assigned to the new pool. This determines the share of rewards the pool receives.
    /// @param poolToken The address of the LP token that will be staked in the pool.
    /// @param _withUpdate Boolean indicating whether to update reward variables before adding the pool.
    /// @param _pool The address of the `StakingPool` contract associated with the new pool.
    function add(
        uint256 _allocPoint,
        IERC20 poolToken,
        bool _withUpdate,
        address _pool
    )
        external
        zeroAllocCheck(_allocPoint)
        zeroAddressCheck(address(poolToken))
        zeroAddressCheck(_pool)
        onlyAuthorised
    {
        if (poolsAdded[address(poolToken)]) revert TokenPoolAlreadyAdded();
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number;
        totalAllocPoint = totalAllocPoint + (_allocPoint);
        poolInfo.push(
            PoolInfo({
                token: poolToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardTokenPerShare: 0,
                pool: _pool
            })
        );
        poolsAdded[address(poolToken)] = true;
    }

    /// @notice Updates the allocation points of an existing pool.
    /// @dev Only callable by the contract owner.
    /// @param _pid The pool ID (index in the `poolInfo` array).
    /// @param _allocPoint The new allocation point for the pool.
    /// @param _withUpdate Boolean indicating whether to update reward variables before updating the allocation points.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external zeroAllocCheck(_allocPoint) validPID(_pid) onlyAuthorised {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint =
            totalAllocPoint -
            (poolInfo[_pid].allocPoint) +
            (_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /// @notice Sets the number of reward tokens to be distributed per block.
    /// @dev Only callable by the contract owner.
    /// @param _rewardTokenPerBlock The new reward token amount per block.
    function setRewardTokenPerBlock(
        uint256 _rewardTokenPerBlock
    ) external onlyOwner zeroAmountCheck(_rewardTokenPerBlock) {
        rewardTokenPerBlock = _rewardTokenPerBlock;
    }

    /// @notice Sets the address from which reward tokens will be pulled for distribution.
    /// @dev Only callable by the contract owner.
    /// @param _fundSource The new fund source address.
    function setFundSource(
        address _fundSource
    ) external onlyOwner zeroAddressCheck(_fundSource) {
        fundSource = _fundSource;
    }

    /// @notice Allows the contract owner to recover tokens (other than the reward token) accidentally sent to the contract.
    /// @param _token The address of the stuck token.
    /// @param _amount The amount of tokens to recover.
    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount
    ) external zeroAddressCheck(_token) zeroAmountCheck(_amount) onlyOwner {
        if (_token == rewardToken) revert RewardTokenTransfer();
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /// @notice Allows a user to deposit LP tokens into a specific pool for staking.
    /// @param _pid The pool ID.
    /// @param poolTokenAmt The amount of LP tokens to deposit.
    function deposit(
        uint256 _pid,
        uint256 poolTokenAmt
    ) external nonReentrant whenNotPaused validPID(_pid) zeroAmountCheck(poolTokenAmt) {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.shares > 0) {
            uint256 pending = (user.shares * (pool.accRewardTokenPerShare)) /
                (1e12) -
                (user.rewardDebt);
            if (pending > 0) {
                safeRewardTokenTransfer(msg.sender, pending);
            }
        }
        if (poolTokenAmt > 0) {
            pool.token.safeTransferFrom(
                address(msg.sender),
                address(this),
                poolTokenAmt
            );

            pool.token.safeIncreaseAllowance(pool.pool, poolTokenAmt);
            uint256 sharesAdded = IStakingPool(poolInfo[_pid].pool).deposit(
                msg.sender,
                poolTokenAmt
            );
            user.shares = user.shares + (sharesAdded);
        }
        user.rewardDebt =
            (user.shares * (pool.accRewardTokenPerShare)) /
            (1e12);
        emit Deposit(msg.sender, _pid, poolTokenAmt);
    }

    /// @notice Allows a user to withdraw all their staked LP tokens and accrued rewards from a specific pool.
    /// @param _pid The pool ID.
    function withdrawAll(uint256 _pid) external {
        withdraw(_pid, type(uint256).max);
    }

    /// @notice Allows a user to claim their accrued rewards from a specific pool without withdrawing LP tokens.
    /// @param _pid The pool ID.
    function claimReward(uint256 _pid) external nonReentrant validPID(_pid) {
        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 sharesTotal = IStakingPool(poolInfo[_pid].pool).sharesTotal();
        if (user.shares == 0) revert UserSharesZero();
        if (sharesTotal == 0) revert TotalSharesZero();

        // Withdraw pending rewardToken
        uint256 pending = (user.shares * (pool.accRewardTokenPerShare)) /
            (1e12) -
            (user.rewardDebt);
        if (pending > 0) {
            safeRewardTokenTransfer(msg.sender, pending);
        }
        user.rewardDebt =
            (user.shares * (pool.accRewardTokenPerShare)) /
            (1e12);
    }

    /// @notice Allows a user to claim their accrued rewards from multiple pools.
    /// @param _pids An array of pool IDs.
    function claimRewardMultiple(uint256[] memory _pids) external nonReentrant {
        for (uint256 i = 0; i < _pids.length; i++) {
            uint256 _pid = _pids[i];
            if (_pid >= poolInfo.length) revert InvalidPID();
            updatePool(_pid);

            PoolInfo storage pool = poolInfo[_pid];
            UserInfo storage user = userInfo[_pid][msg.sender];

            uint256 sharesTotal = IStakingPool(poolInfo[_pid].pool)
                .sharesTotal();
            if (user.shares == 0) revert UserSharesZero();
            if (sharesTotal == 0) revert TotalSharesZero();

            // Withdraw pending rewardToken
            uint256 pending = (user.shares * (pool.accRewardTokenPerShare)) /
                (1e12) -
                (user.rewardDebt);
            if (pending > 0) {
                safeRewardTokenTransfer(msg.sender, pending);
            }
            user.rewardDebt =
                (user.shares * (pool.accRewardTokenPerShare)) /
                (1e12);
        }
    }

    /// @notice Allows a user to withdraw their staked LP tokens from a specific pool without claiming rewards.
    /// @dev This function is for emergency situations and should be used with caution.
    /// @param _pid The pool ID.
    function emergencyWithdraw(
        uint256 _pid
    ) external nonReentrant validPID(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 tokenLockedTotal = IStakingPool(poolInfo[_pid].pool)
            .tokenLockedTotal();
        uint256 sharesTotal = IStakingPool(poolInfo[_pid].pool).sharesTotal();
        uint256 amount = (user.shares * (tokenLockedTotal)) / (sharesTotal);

        IStakingPool(poolInfo[_pid].pool).withdraw(msg.sender, amount);

        uint256 poolBalance = IERC20(pool.token).balanceOf(address(this));
        if (amount > poolBalance) {
            amount = poolBalance;
        }

        pool.token.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
        user.shares = 0;
        user.rewardDebt = 0;
    }

    /// @notice Returns the number of pools managed by the factory.
    /// @return The length of the `poolInfo` array.
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// @notice Returns the pending reward tokens for a user in a specific pool.
    /// @param _pid The pool ID.
    /// @param _user The address of the user.
    /// @return The amount of pending reward tokens.
    function pendingRewardToken(
        uint256 _pid,
        address _user
    ) external view validPID(_pid) returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardTokenPerShare = pool.accRewardTokenPerShare;
        uint256 sharesTotal = IStakingPool(pool.pool).sharesTotal();
        if (block.number > pool.lastRewardBlock && sharesTotal != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 rewardTokenReward = (multiplier *
                (rewardTokenPerBlock) *
                (pool.allocPoint)) / (totalAllocPoint);
            accRewardTokenPerShare =
                accRewardTokenPerShare +
                ((rewardTokenReward * (1e12)) / (sharesTotal));
        }
        return
            (user.shares * (accRewardTokenPerShare)) /
            (1e12) -
            (user.rewardDebt);
    }

    /// @notice Returns the amount of staked LP tokens for a user in a specific pool.
    /// @param _pid The pool ID.
    /// @param _user The address of the user.
    /// @return The amount of staked LP tokens.
    function stakedTokensAmount(
        uint256 _pid,
        address _user
    ) external view validPID(_pid) returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 sharesTotal = IStakingPool(pool.pool).sharesTotal();
        uint256 tokenLockedTotal = IStakingPool(poolInfo[_pid].pool)
            .tokenLockedTotal();
        if (sharesTotal == 0) {
            return 0;
        }
        return (user.shares * (tokenLockedTotal)) / (sharesTotal);
    }

    /// @notice Allows a user to withdraw their staked LP tokens from a specific pool.
    /// @param _pid The pool ID.
    /// @param poolTokenAmt The amount of LP tokens to withdraw.
    function withdraw(
        uint256 _pid,
        uint256 poolTokenAmt
    ) public nonReentrant whenNotPaused validPID(_pid) zeroAmountCheck(poolTokenAmt) {
        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 tokenLockedTotal = IStakingPool(poolInfo[_pid].pool)
            .tokenLockedTotal();
        uint256 sharesTotal = IStakingPool(poolInfo[_pid].pool).sharesTotal();

        if (user.shares == 0) revert UserSharesZero();
        if (sharesTotal == 0) revert TotalSharesZero();

        // Withdraw pending rewardToken
        uint256 pending = (user.shares * (pool.accRewardTokenPerShare)) /
            (1e12) -
            (user.rewardDebt);
        if (pending > 0) {
            safeRewardTokenTransfer(msg.sender, pending);
        }

        // Withdraw pool tokens
        uint256 amount = (user.shares * (tokenLockedTotal)) / (sharesTotal);
        if (poolTokenAmt > amount) {
            poolTokenAmt = amount;
        }
        if (poolTokenAmt > 0) {
            uint256 sharesRemoved = IStakingPool(poolInfo[_pid].pool).withdraw(
                msg.sender,
                poolTokenAmt
            );

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares - (sharesRemoved);
            }

            uint256 tokenBal = IERC20(pool.token).balanceOf(address(this));
            if (tokenBal < poolTokenAmt) {
                poolTokenAmt = tokenBal;
            }
            if (address(pool.token) == address(rewardToken)) {
                pool.token.safeTransfer(address(msg.sender), sharesRemoved);
            } else {
                pool.token.safeTransfer(address(msg.sender), poolTokenAmt);
            }
        }
        user.rewardDebt =
            (user.shares * (pool.accRewardTokenPerShare)) /
            (1e12);
        emit Withdraw(msg.sender, _pid, poolTokenAmt);
    }

    /// @notice Updates the reward variables of a specific pool.
    /// @param _pid The pool ID.
    function updatePool(uint256 _pid) public validPID(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 sharesTotal = IStakingPool(pool.pool).sharesTotal();
        if (sharesTotal == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        if (multiplier <= 0) {
            return;
        }
        uint256 rewardTokenReward = (multiplier *
            (rewardTokenPerBlock) *
            (pool.allocPoint)) / (totalAllocPoint);

        getRewardToken(rewardTokenReward);

        pool.accRewardTokenPerShare =
            pool.accRewardTokenPerShare +
            ((rewardTokenReward * (1e12)) / (sharesTotal));
        pool.lastRewardBlock = block.number;
    }

    /// @notice Updates reward variables for all pools.
    /// @dev This function can be expensive in terms of gas, so use it carefully.
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /// @notice Calculates the reward multiplier over a given block range.
    /// @param _from The starting block number.
    /// @param _to The ending block number.
    /// @return The calculated reward multiplier.
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public pure returns (uint256) {
        return _to - (_from);
    }

    /// @dev Internal function to safely transfer reward tokens to a user.
    /// @param _to The address of the recipient.
    /// @param _rewardTokenAmt The amount of reward tokens to transfer.
    function safeRewardTokenTransfer(
        address _to,
        uint256 _rewardTokenAmt
    ) internal zeroAddressCheck(_to) zeroAmountCheck(_rewardTokenAmt) {
        uint256 rewardTokenBal = IERC20(rewardToken).balanceOf(address(this));
        if (_rewardTokenAmt > rewardTokenBal) {
            IERC20(rewardToken).transfer(_to, rewardTokenBal);
        } else {
            IERC20(rewardToken).transfer(_to, _rewardTokenAmt);
        }
    }

    /// @dev Internal function to transfer reward tokens from the `fundSource` to the factory contract.
    /// @param _rewardTokenAmt The amount of reward tokens to transfer.
    function getRewardToken(
        uint256 _rewardTokenAmt
    ) internal zeroAmountCheck(_rewardTokenAmt) {
        IERC20(rewardToken).transferFrom(
            fundSource,
            address(this),
            _rewardTokenAmt
        );
    }
}
