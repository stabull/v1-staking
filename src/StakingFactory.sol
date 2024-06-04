// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Authorizable.sol";
import "./interfaces/IStakingPool.sol";

import {Test, console2} from "forge-std/Test.sol";

contract StakingFactory is Authorizable, ReentrancyGuard {
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

    // Info of each user.
    struct UserInfo {
        uint256 shares; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.

        // We do some fancy math here. Basically, any point in time, the amount of rewardToken
        // entitled to a user but is pending to be distributed is:
        //
        //   amount = user.shares / sharesTotal * tokenLockedTotal
        //   pending reward = (amount * pool.accRewardTokenPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws token tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardTokenPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct PoolInfo {
        IERC20 token; // Address of the pool token.
        uint256 allocPoint; // How many allocation points assigned to this pool. rewardToken to distribute per block.
        uint256 lastRewardBlock; // Last block number that rewardToken distribution occurs.
        uint256 accRewardTokenPerShare; // Accumulated rewardToken per share, times 1e12. See below.
        address pool; // Staking Pool address that will auto compound pool tokens
    }

    address public rewardToken;
    address public fundSource; //source of rewardToken tokens to pull from

    // address public burnAddress = 0x000000000000000000000000000000000000dEaD;

    //initialize at zero and update later
    uint256 public rewardTokenPerBlock = 0; // rewardToken tokens distributed per block

    PoolInfo[] public poolInfo; // Info of each pool.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // Info of each user that stakes LP tokens.
    mapping(address => bool) public poolsAdded;
    uint256 public totalAllocPoint = 0; // Total allocation points. Must be the sum of all allocation points in all pools.

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

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

    constructor(address _rewardToken, address _fundSource) Ownable() {
        rewardToken = _rewardToken;
        fundSource = _fundSource;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do. (Only if pool tokens are stored here.)

    function add(
        uint256 _allocPoint,
        IERC20 poolToken,
        bool _withUpdate,
        address _pool
    )
        public
        onlyOwner
        zeroAllocCheck(_allocPoint)
        zeroAddressCheck(address(poolToken))
        zeroAddressCheck(_pool)
        onlyAuthorized
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
        poolsAdded[address(poolToken)] == true;
    }

    // Update the given pool's rewardToken allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    )
        public
        onlyOwner
        zeroAllocCheck(_allocPoint)
        validPID(_pid)
        onlyAuthorized
    {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint =
            totalAllocPoint -
            (poolInfo[_pid].allocPoint) +
            (_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public pure returns (uint256) {
        return _to - (_from);
    }

    // View function to see pending rewardToken on frontend.
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

    // View function to see staked pool tokens on frontend.
    function stakedtokenTokens(
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

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
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

    // pool tokens moved from user -> rewardTokenFarm (rewardToken allocation) -> pool (compounding)
    function deposit(
        uint256 _pid,
        uint256 poolTokenAmt
    ) public nonReentrant validPID(_pid) zeroAmountCheck(poolTokenAmt) {
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

    // Withdraw LP tokens from MasterChef.
    function withdraw(
        uint256 _pid,
        uint256 poolTokenAmt
    ) public nonReentrant validPID(_pid) zeroAmountCheck(poolTokenAmt) {
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

    function withdrawAll(uint256 _pid) public {
        withdraw(_pid, type(uint256).max);
    }

    function claimReward(uint256 _pid) public nonReentrant validPID(_pid) {
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

    function claimRewardMulitple(uint256[] memory _pids) public nonReentrant {
        for (uint i = 0; i < _pids.length; i++) {
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

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(
        uint256 _pid
    ) public nonReentrant validPID(_pid) {
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

    // Safe rewardToken transfer function, just in case if rounding error causes pool to not have enough
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

    //gets rewardToken for distribution from external address
    function getRewardToken(
        uint256 _rewardTokenAmt
    ) internal zeroAmountCheck(_rewardTokenAmt) {
        IERC20(rewardToken).transferFrom(
            fundSource,
            address(this),
            _rewardTokenAmt
        );
    }

    function setFundSource(
        address _fundSource
    ) external onlyOwner zeroAddressCheck(_fundSource) {
        fundSource = _fundSource;
    }

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount
    ) external zeroAddressCheck(_token) zeroAmountCheck(_amount) onlyOwner {
        if (_token == rewardToken) revert RewardTokenTransfer();
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function setRewardTokenPerBlock(
        uint256 _rewardTokenPerBlock
    ) external onlyOwner zeroAmountCheck(_rewardTokenPerBlock) {
        rewardTokenPerBlock = _rewardTokenPerBlock;
    }
}
