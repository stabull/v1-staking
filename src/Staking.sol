// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;


import "@openzeppelin/contracts/access/Ownable.sol";


contract JPOW is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 shares; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.

        // We do some fancy math here. Basically, any point in time, the amount of WSB
        // entitled to a user but is pending to be distributed is:
        //
        //   amount = user.shares / sharesTotal * wantLockedTotal
        //   pending reward = (amount * pool.accWSBPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws want tokens to a pool. Here's what happens:
        //   1. The pool's `accWSBPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct PoolInfo {
        IERC20 want; // Address of the want token.
        uint256 allocPoint; // How many allocation points assigned to this pool. WSB to distribute per block.
        uint256 lastRewardBlock; // Last block number that WSB distribution occurs.
        uint256 accWSBPerShare; // Accumulated WSB per share, times 1e12. See below.
        address strat; // Strategy address that will auto compound want tokens
    }

    address public WSB = 0x22168882276e5D5e1da694343b41DD7726eeb288;
    address public fundSource; //source of WSB tokens to pull from

    address public burnAddress = 0x000000000000000000000000000000000000dEaD;

    //initialize at zero and update later
    uint256 public WSBPerBlock = 0; // WSB tokens distributed per block

    PoolInfo[] public poolInfo; // Info of each pool.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // Info of each user that stakes LP tokens.
    uint256 public totalAllocPoint = 0; // Total allocation points. Must be the sum of all allocation points in all pools.

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do. (Only if want tokens are stored here.)

    function add(
        uint256 _allocPoint,
        IERC20 _want,
        bool _withUpdate,
        address _strat
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                want: _want,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accWSBPerShare: 0,
                strat: _strat
            })
        );
    }

    // Update the given pool's WSB allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // View function to see pending WSB on frontend.
    function pendingWSB(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accWSBPerShare = pool.accWSBPerShare;
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        if (block.number > pool.lastRewardBlock && sharesTotal != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 WSBReward =
                multiplier.mul(WSBPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accWSBPerShare = accWSBPerShare.add(
                WSBReward.mul(1e12).div(sharesTotal)
            );
        }
        return user.shares.mul(accWSBPerShare).div(1e12).sub(user.rewardDebt);
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        if (sharesTotal == 0) {
            return 0;
        }
        return user.shares.mul(wantLockedTotal).div(sharesTotal);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        if (sharesTotal == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        if (multiplier <= 0) {
            return;
        }
        uint256 WSBReward =
            multiplier.mul(WSBPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );

        getWSB(WSBReward);

        pool.accWSBPerShare = pool.accWSBPerShare.add(
            WSBReward.mul(1e12).div(sharesTotal)
        );
        pool.lastRewardBlock = block.number;
    }

    // Want tokens moved from user -> WSBFarm (WSB allocation) -> Strat (compounding)
    function deposit(uint256 _pid, uint256 _wantAmt) public nonReentrant {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.shares > 0) {
            uint256 pending =
                user.shares.mul(pool.accWSBPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            if (pending > 0) {
                safeWSBTransfer(msg.sender, pending);
            }
        }
        if (_wantAmt > 0) {
            pool.want.safeTransferFrom(
                address(msg.sender),
                address(this),
                _wantAmt
            );

            pool.want.safeIncreaseAllowance(pool.strat, _wantAmt);
            uint256 sharesAdded =
                IStrategy(poolInfo[_pid].strat).deposit(msg.sender, _wantAmt);
            user.shares = user.shares.add(sharesAdded);
        }
        user.rewardDebt = user.shares.mul(pool.accWSBPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _wantAmt);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _wantAmt) public nonReentrant {
        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        // Withdraw pending WSB
        uint256 pending =
            user.shares.mul(pool.accWSBPerShare).div(1e12).sub(
                user.rewardDebt
            );
        if (pending > 0) {
            safeWSBTransfer(msg.sender, pending);
        }

        // Withdraw want tokens
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            uint256 sharesRemoved =
                IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, _wantAmt);

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares.sub(sharesRemoved);
            }

            uint256 wantBal = IERC20(pool.want).balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            if (address(pool.want) == address(WSB)) {
                pool.want.safeTransfer(address(msg.sender), sharesRemoved);
            } else {
                pool.want.safeTransfer(address(msg.sender), _wantAmt);    
            }
            
        }
        user.rewardDebt = user.shares.mul(pool.accWSBPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    function withdrawAll(uint256 _pid) public nonReentrant {
        withdraw(_pid, uint256(-1));
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);

        IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, amount);

        pool.want.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
        user.shares = 0;
        user.rewardDebt = 0;
    }

    // Safe WSB transfer function, just in case if rounding error causes pool to not have enough
    function safeWSBTransfer(address _to, uint256 _WSBAmt) internal {
        uint256 WSBBal = IERC20(WSB).balanceOf(address(this));
        if (_WSBAmt > WSBBal) {
            IERC20(WSB).transfer(_to, WSBBal);
        } else {
            IERC20(WSB).transfer(_to, _WSBAmt);
        }
    }

    //gets WSB for distribution from external address
    function getWSB(uint256 _WSBAmt) internal {
        IERC20(WSB).transferFrom(fundSource, address(this), _WSBAmt);
    }

    function setFundSource(address _fundSource) external onlyOwner {
        fundSource = _fundSource;
    }

    function inCaseTokensGetStuck(address _token, uint256 _amount)
        external
        onlyOwner
    {
        require(_token != WSB, "!safe");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function setWSBPerBlock(uint256 _WSBPerBlock) external onlyOwner {
        WSBPerBlock = _WSBPerBlock;
    }

}

contract DarkPool is Ownable {

    address public WSB = 0x22168882276e5D5e1da694343b41DD7726eeb288;

    constructor(address _JPOW) public {
        IERC20(WSB).approve(_JPOW, uint256(-1));
    }

    function transferERC20(address _token, address _receiver, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(_receiver, _amount);
    }

}