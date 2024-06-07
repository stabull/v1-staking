// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../src/StakingFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/mocks/MockERC20.sol";
import "../src/StakingPool.sol";
import {Test, console2} from "forge-std/Test.sol";

contract StakingFactoryTest is Test {
    StakingFactory stakingFactory;
    MockERC20 rewardToken;
    MockERC20 lpToken;
    MockERC20 lpToken2;
    MockERC20 lpToken3;
    StakingPool stakingPool;
    StakingPool stakingPool2;
    StakingPool stakingPool3;
    address owner = address(0x1);
    address user = address(0x2);
    address user2 = address(0x3);
    address user3 = address(0x4);
    address fundSource = address(0x35);

    uint256 DECIMAL = 10 ** 18;
    uint256 ONE_IN_BPS = 10000;

    function setUp() public {
        vm.startPrank(owner);
        rewardToken = new MockERC20();

        lpToken = new MockERC20();

        stakingFactory = new StakingFactory(address(rewardToken), fundSource);
        stakingPool = new StakingPool(
            address(stakingFactory),
            address(rewardToken),
            owner,
            address(lpToken)
        );

        // Mint some tokens for testing
        rewardToken.mint(fundSource, 10000 * DECIMAL);
        lpToken.mint(user, 10000 * DECIMAL);
        lpToken.mint(user2, 10000 * DECIMAL);
        lpToken.mint(user3, 10000 * DECIMAL);
        vm.stopPrank();

        // Approve the StakingFactory to spend tokens
        vm.startPrank(fundSource);
        rewardToken.approve(address(stakingFactory), type(uint256).max);
        vm.stopPrank();
    }

    function test_AddPool() public {
        // Only owner can add pool
        vm.prank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        (IERC20 token, uint256 allocPoint, , , ) = stakingFactory.poolInfo(0);
        assertEq(address(token), address(lpToken));
        assertEq(allocPoint, 100);
    }

    function testDeposit() public {
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        vm.stopPrank();
        uint256 amount = 1000 * DECIMAL;

        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount);
        stakingFactory.deposit(0, amount);

        (uint256 shares, ) = stakingFactory.userInfo(0, user);
        vm.stopPrank();
        uint256 entranceFees = stakingPool.entranceFeeFactor();
        amount = amount - (amount * entranceFees) / 10000;
        assertEq(shares, amount);
    }

    function testUserCannotAddPool() public {
        vm.startPrank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        stakingFactory.add(100, lpToken, true, address(stakingPool));

        vm.stopPrank();
    }

    function testNonOwnerCannotSetRewardTokenPerBlock() public {
        uint256 rewardAmount = 100 * DECIMAL;
        vm.startPrank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        stakingFactory.setRewardTokenPerBlock(rewardAmount);

        vm.stopPrank();
    }

    function testAddMultiplePools() public {
        vm.startPrank(owner);

        lpToken2 = new MockERC20();
        lpToken3 = new MockERC20();

        stakingPool2 = new StakingPool(
            address(stakingFactory),
            address(rewardToken),
            owner,
            address(lpToken2)
        );
        stakingPool3 = new StakingPool(
            address(stakingFactory),
            address(rewardToken),
            owner,
            address(lpToken3)
        );

        stakingFactory.add(100, lpToken, true, address(stakingPool));
        stakingFactory.add(200, lpToken2, true, address(stakingPool2));
        stakingFactory.add(300, lpToken3, true, address(stakingPool3));

        vm.stopPrank();

        (IERC20 token1, uint256 allocPoint1, , , ) = stakingFactory.poolInfo(0);
        (IERC20 token2, uint256 allocPoint2, , , ) = stakingFactory.poolInfo(1);
        (IERC20 token3, uint256 allocPoint3, , , ) = stakingFactory.poolInfo(2);

        assertEq(address(token1), address(lpToken));
        assertEq(allocPoint1, 100);
        assertEq(address(token2), address(lpToken2));
        assertEq(allocPoint2, 200);
        assertEq(address(token3), address(lpToken3));
        assertEq(allocPoint3, 300);
    }

    function testWithdraw() public {
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        vm.stopPrank();
        uint256 amount = 1000 * DECIMAL;

        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount);

        stakingFactory.deposit(0, amount);

        stakingFactory.withdraw(0, amount);
        vm.stopPrank();
        (uint256 shares, ) = stakingFactory.userInfo(0, user);
        assertEq(shares, 0);
    }

    function testClaimReward() public {
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));

        uint256 amount = 1000 * DECIMAL;
        uint256 rewardAmount = 100 * DECIMAL;

        stakingFactory.setRewardTokenPerBlock(rewardAmount);
        vm.stopPrank();

        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount);
        stakingFactory.deposit(0, amount);
        uint256 allowance = rewardToken.allowance(
            fundSource,
            address(stakingFactory)
        );
        assert(allowance >= rewardAmount * 10); // ensure enough allowance
        uint256 fundSourceBalance = rewardToken.balanceOf(fundSource);
        assert(fundSourceBalance >= rewardAmount * 10); // ensure enough balance

        // Advance blocks to accumulate rewards
        vm.roll(block.number + 10);
        uint256 userBalance = rewardToken.balanceOf(user);
        assertEq(userBalance, 0);

        stakingFactory.claimReward(0);
        vm.stopPrank();

        (uint256 userShares, ) = stakingFactory.userInfo(0, user);
        (, , , uint256 accRewardTokenPerShare, ) = stakingFactory.poolInfo(0);
        uint256 userReward = (userShares * accRewardTokenPerShare) / 1e12;
        userBalance = rewardToken.balanceOf(user);
        assertEq(userBalance, userReward);
    }

    // ... (Your existing test cases)

function testPauseUnpause() public {
    vm.startPrank(owner);
    stakingFactory.add(100, lpToken, true, address(stakingPool));
    vm.stopPrank();

    // Pause the pool
    vm.prank(owner);
    stakingPool.pause();

    // Try to deposit - should revert
    vm.startPrank(user);
    lpToken.approve(address(stakingFactory), 1000 * DECIMAL);
    vm.expectRevert("Pausable: paused");
    stakingFactory.deposit(0, 1000 * DECIMAL);
    vm.stopPrank();

    // Unpause the pool
    vm.prank(owner);
    stakingPool.unpause();

    // Deposit should now succeed
    vm.startPrank(user);
    stakingFactory.deposit(0, 1000 * DECIMAL);
    vm.stopPrank();
}

function testSetEntranceFeeFactor() public {
    uint256 newEntranceFeeFactor = 40; // 0.4%
    vm.prank(owner); 
    stakingPool.setEntranceFeeFactor(newEntranceFeeFactor);
    assertEq(stakingPool.entranceFeeFactor(), newEntranceFeeFactor);
}

function testSetExitFeeFactor() public {
    uint256 newExitFeeFactor = 45; // 0.45%
    vm.prank(owner);
    stakingPool.setExitFeeFactor(newExitFeeFactor);
    assertEq(stakingPool.exitFeeFactor(), newExitFeeFactor);
}

function testSetExitFeeFactorAboveMax() public {
    uint256 newExitFeeFactor = 55; // 0.45%
    vm.prank(owner);
    vm.expectRevert(bytes4(keccak256("FeeLimitExceeded()")));
    stakingPool.setExitFeeFactor(newExitFeeFactor);
}

function testSetGov() public {
    address newGov = address(0x123);
    vm.prank(owner);
    stakingPool.setGov(newGov);
    assertEq(stakingPool.govAddress(), newGov);
}

function testInCaseTokensGetStuck() public {
    MockERC20 stuckToken = new MockERC20();
    stuckToken.mint(address(stakingPool), 100 * DECIMAL);

    address recipient = address(0x456);

    vm.prank(owner);
    stakingPool.inCaseTokensGetStuck(address(stuckToken), 100 * DECIMAL, recipient);

    assertEq(stuckToken.balanceOf(address(stakingPool)), 0);
    assertEq(stuckToken.balanceOf(recipient), 100 * DECIMAL);
}



// 2. Edge Case: Zero Deposits and Withdrawals
function testZeroDepositWithdraw() public {
    vm.startPrank(owner);
    stakingFactory.add(100, lpToken, true, address(stakingPool));
    vm.stopPrank();

    vm.startPrank(user);
    lpToken.approve(address(stakingFactory), 1000 * DECIMAL);

    // Deposit 0 tokens
    vm.expectRevert(bytes4(keccak256("ZeroAmountInserted()")));
    stakingFactory.deposit(0, 0); 
    (uint256 shares, ) = stakingFactory.userInfo(0, user);
    assertEq(shares, 0, "Shares should remain 0 after 0 deposit");

    // Withdraw 0 tokens
    vm.expectRevert(bytes4(keccak256("ZeroAmountInserted()")));
    stakingFactory.withdraw(0, 0);
    (shares, ) = stakingFactory.userInfo(0, user);
    assertEq(shares, 0, "Shares should remain 0 after 0 withdrawal");
    vm.stopPrank();
}

// 4. inCaseTokensGetStuck() - Reward Token Revert 
function testInCaseTokensGetStuckRewardToken() public {
    MockERC20 stuckToken = rewardToken; // Set stuckToken to rewardToken
    stuckToken.mint(address(stakingFactory), 100 * DECIMAL);

    // Trying to recover the reward token should revert
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(StakingFactory.RewardTokenTransfer.selector)); 
    stakingFactory.inCaseTokensGetStuck(address(stuckToken), 100 * DECIMAL);
}

// ... Add more complex multiple user, multiple pool scenarios

    function testEmergencyWithdrawWithin72Hours() public {
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        vm.stopPrank();
        uint256 amount = 10000 * DECIMAL;
        uint256 userBalance = lpToken.balanceOf(user);
        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount);
        stakingFactory.deposit(0, amount);

        (uint256 userShares, ) = stakingFactory.userInfo(0, user);
        uint256 finalAmount = (userShares * stakingPool.tokenLockedTotal()) /
            stakingPool.sharesTotal();

        // Here exit fees will be charged as amount is withdrawn before 72 hours
        uint256 exitFees = stakingPool.exitFeeFactor();
        finalAmount = finalAmount - (finalAmount * exitFees) / 10000;

        stakingFactory.emergencyWithdraw(0);

        vm.stopPrank();

        (uint256 shares, ) = stakingFactory.userInfo(0, user);
        assertEq(shares, 0);

        uint256 userRewardBalance = rewardToken.balanceOf(user);
        assertEq(userRewardBalance, 0);

        userBalance = lpToken.balanceOf(user);
        assertEq(userBalance, finalAmount);
    }

    function testEmergencyWithdrawAfter72Hours() public {
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        vm.stopPrank();
        uint256 amount = 10000 * DECIMAL;
        uint256 userBalance = lpToken.balanceOf(user);
        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount);
        stakingFactory.deposit(0, amount);

        (uint256 userShares, ) = stakingFactory.userInfo(0, user);
        uint256 finalAmount = (userShares * stakingPool.tokenLockedTotal()) /
            stakingPool.sharesTotal();

        vm.warp(block.timestamp + 73 hours);
        stakingFactory.emergencyWithdraw(0);

        vm.stopPrank();

        (uint256 shares, ) = stakingFactory.userInfo(0, user);
        assertEq(shares, 0);

        uint256 userRewardBalance = rewardToken.balanceOf(user);
        assertEq(userRewardBalance, 0);

        userBalance = lpToken.balanceOf(user);
        assertEq(userBalance, finalAmount);
    }

    function testMultipleDepositInAPool() public {
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));

        uint256 amount = 1000 * DECIMAL;
        uint256 amount2 = 2000 * DECIMAL;
        uint256 rewardAmount = 100 * DECIMAL;

        stakingFactory.setRewardTokenPerBlock(rewardAmount);
        vm.stopPrank();

        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount + amount2);

        stakingFactory.deposit(0, amount);
        uint256 allowance = rewardToken.allowance(
            fundSource,
            address(stakingFactory)
        );
        assert(allowance >= rewardAmount * 10); // ensure enough allowance
        uint256 fundSourceBalance = rewardToken.balanceOf(fundSource);
        assert(fundSourceBalance >= rewardAmount * 10); // ensure enough balance

        // Advance blocks to accumulate rewards
        vm.roll(block.number + 10);
        uint256 userBalance = rewardToken.balanceOf(user);
        assertEq(userBalance, 0);

        userBalance = rewardToken.balanceOf(user);
        assertEq(userBalance, 0);

        (uint256 userShares, ) = stakingFactory.userInfo(0, user);

        stakingFactory.deposit(0, amount);
        vm.stopPrank();
        (, , , uint256 accRewardTokenPerShare, ) = stakingFactory.poolInfo(0);
        uint256 userReward = (userShares * accRewardTokenPerShare) / 1e12;

        userBalance = rewardToken.balanceOf(user);
        assertEq(userBalance, userReward);
    }

    function testBalanceAfterMultipleDepositAndWithdrawInAPool() public {
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));

        uint256 amount = 1000 * DECIMAL;
        uint256 amount2 = 2000 * DECIMAL;
        uint256 amount3 = 500 * DECIMAL;
        uint256 rewardAmount = 100 * DECIMAL;

        stakingFactory.setRewardTokenPerBlock(rewardAmount);
        vm.stopPrank();

        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount + amount2 + amount3);

        stakingFactory.deposit(0, amount);
        uint256 allowance = rewardToken.allowance(
            fundSource,
            address(stakingFactory)
        );
        assert(allowance >= rewardAmount * 10); // ensure enough allowance
        uint256 fundSourceBalance = rewardToken.balanceOf(fundSource);
        assert(fundSourceBalance >= rewardAmount * 10); // ensure enough balance

        // Advance blocks to accumulate rewards
        vm.roll(block.number + 10);
        uint256 userBalance = rewardToken.balanceOf(user);
        assertEq(userBalance, 0);

        userBalance = rewardToken.balanceOf(user);
        assertEq(userBalance, 0);

        stakingFactory.deposit(0, amount2);

        stakingFactory.deposit(0, amount3);

        vm.roll(block.number + 50);
        vm.warp(block.timestamp + 73 hours);

        uint256 userBalanceBefore = lpToken.balanceOf(user);
        stakingFactory.withdrawAll(0);
        vm.stopPrank();

        uint256 userBalanceAfter = lpToken.balanceOf(user);

        uint256 entranceFee = stakingPool.entranceFeeFactor();
        amount = amount - (amount * entranceFee) / 10000;

        amount2 = amount2 - (amount2 * entranceFee) / 10000;
        amount3 = amount3 - (amount3 * entranceFee) / 10000;
        uint256 finalAmount = amount + amount2 + amount3;
        assertEq(userBalanceAfter, userBalanceBefore + finalAmount);
    }

    function testRewardAfterMultipleDepositAndWithdrawInAPool() public {
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));

        uint256 amount = 1000 * DECIMAL;
        uint256 amount2 = 2000 * DECIMAL;
        uint256 amount3 = 500 * DECIMAL;
        uint256 rewardAmount = 100 * DECIMAL;

        stakingFactory.setRewardTokenPerBlock(rewardAmount);
        vm.stopPrank();

        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount + amount2 + amount3);

        stakingFactory.deposit(0, amount);
        uint256 allowance = rewardToken.allowance(
            fundSource,
            address(stakingFactory)
        );
        assert(allowance >= rewardAmount * 10); // ensure enough allowance
        uint256 fundSourceBalance = rewardToken.balanceOf(fundSource);
        assert(fundSourceBalance >= rewardAmount * 10); // ensure enough balance

        // Advance blocks to accumulate rewards
        vm.roll(block.number + 10);
        uint256 userBalance = rewardToken.balanceOf(user);

        userBalance = rewardToken.balanceOf(user);

        (uint256 userShares, uint256 rewardDebt) = stakingFactory.userInfo(
            0,
            user
        );

        uint256 userRewardBalance = rewardToken.balanceOf(user);

        assertEq(userRewardBalance, 0);

        stakingFactory.deposit(0, amount2);

        userRewardBalance = rewardToken.balanceOf(user);

        (, , , uint256 accRewardTokenPerShare, ) = stakingFactory.poolInfo(0);
        uint256 userReward = (userShares * accRewardTokenPerShare) /
            1e12 -
            rewardDebt;

        assertEq(userRewardBalance, userReward);

        stakingFactory.deposit(0, amount3);

        vm.roll(block.number + 50);
        vm.warp(block.timestamp + 73 hours);

        (userShares, rewardDebt) = stakingFactory.userInfo(0, user);

        stakingFactory.withdrawAll(0);
        vm.stopPrank();

        userRewardBalance = rewardToken.balanceOf(user);

        (, , , accRewardTokenPerShare, ) = stakingFactory.poolInfo(0);
        userReward += (userShares * accRewardTokenPerShare) / 1e12 - rewardDebt;

        assertEq(userRewardBalance, userReward);
    }

    function testTwoUsersDepositAndWithdrawCheckBalances() public {
        uint256 rewardAmount = 100 * DECIMAL;
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        stakingPool.setExitFeeFactor(0);
        stakingFactory.setRewardTokenPerBlock(rewardAmount);
        vm.stopPrank();

        uint256 amountUser1 = 1000 * DECIMAL;
        uint256 amountUser2 = 2000 * DECIMAL;

        // User 1 deposits
        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amountUser1);
        stakingFactory.deposit(0, amountUser1);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 5);

        // User 2 deposits
        vm.startPrank(user2);
        lpToken.approve(address(stakingFactory), amountUser2);
        stakingFactory.deposit(0, amountUser2);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 10);

        // User 1 withdraws
        vm.startPrank(user);
        uint256 user1BalanceBefore = lpToken.balanceOf(user);
        stakingFactory.withdrawAll(0);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 10);

        // User 2 withdraws
        vm.startPrank(user2);
        uint256 user2BalanceBefore = lpToken.balanceOf(user2);
        stakingFactory.withdrawAll(0);
        vm.stopPrank();

        uint256 entranceFee = stakingPool.entranceFeeFactor();
        // Check balances after withdrawals
        uint256 user1ExpectedBalance = user1BalanceBefore +
            amountUser1 -
            ((amountUser1 * entranceFee) / 10000);
        uint256 user2ExpectedBalance = user2BalanceBefore +
            amountUser2 -
            ((amountUser2 * entranceFee) / 10000);

        assertEq(lpToken.balanceOf(user), user1ExpectedBalance);
        assertEq(lpToken.balanceOf(user2), user2ExpectedBalance);
    }

    function testTwoUsersDepositAndWithdrawCheckRewards() public {
        uint256 rewardAmount = 100 * DECIMAL;
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        stakingFactory.setRewardTokenPerBlock(rewardAmount);
        vm.stopPrank();

        uint256 amountUser1 = 1000 * DECIMAL;
        uint256 amountUser2 = 2000 * DECIMAL;

        // User 1 deposits
        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amountUser1);
        stakingFactory.deposit(0, amountUser1);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 5);

        // User 2 deposits
        vm.startPrank(user2);
        lpToken.approve(address(stakingFactory), amountUser2);
        stakingFactory.deposit(0, amountUser2);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 10);

        // User 1 claims rewards and withdraws
        vm.startPrank(user);
        stakingFactory.claimReward(0);
        uint256 user1RewardBeforeWithdraw = rewardToken.balanceOf(user);
        (uint256 user1Shares, uint256 user1RewardDebt) = stakingFactory
            .userInfo(0, user);
        stakingFactory.withdrawAll(0);
        vm.stopPrank();

        // User 2 claims rewards and withdraws
        vm.startPrank(user2);
        stakingFactory.claimReward(0);
        uint256 user2RewardBeforeWithdraw = rewardToken.balanceOf(user2);
        (uint256 user2Shares, uint256 user2RewardDebt) = stakingFactory
            .userInfo(0, user2);
        stakingFactory.withdrawAll(0);
        vm.stopPrank();

        // Calculate expected rewards
        (, , , uint256 accRewardTokenPerShare, ) = stakingFactory.poolInfo(0);
        uint256 user1ExpectedReward = (user1Shares * accRewardTokenPerShare) /
            1e12 -
            user1RewardDebt;
        uint256 user2ExpectedReward = (user2Shares * accRewardTokenPerShare) /
            1e12 -
            user2RewardDebt;

        assertEq(
            rewardToken.balanceOf(user),
            user1RewardBeforeWithdraw + user1ExpectedReward
        );
        assertEq(
            rewardToken.balanceOf(user2),
            user2RewardBeforeWithdraw + user2ExpectedReward
        );
    }

    function testThreeUsersDepositAndWithdrawCheckBalances() public {
        uint256 rewardAmount = 100 * DECIMAL;
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        stakingPool.setExitFeeFactor(0);
        stakingFactory.setRewardTokenPerBlock(rewardAmount);
        vm.stopPrank();

        uint256 amountUser1 = 1000 * DECIMAL;
        uint256 amountUser2 = 2000 * DECIMAL;
        uint256 amountUser3 = 1500 * DECIMAL;

        // User 1 deposits
        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amountUser1);
        stakingFactory.deposit(0, amountUser1);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 5);

        // User 2 deposits
        vm.startPrank(user2);
        lpToken.approve(address(stakingFactory), amountUser2);
        stakingFactory.deposit(0, amountUser2);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 10);

        // User 3 deposits
        vm.startPrank(user3);
        lpToken.approve(address(stakingFactory), amountUser3);
        stakingFactory.deposit(0, amountUser3);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 5);

        // User 1 withdraws
        vm.startPrank(user);
        uint256 user1BalanceBefore = lpToken.balanceOf(user);
        stakingFactory.withdrawAll(0);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 10);

        // User 2 withdraws
        vm.startPrank(user2);
        uint256 user2BalanceBefore = lpToken.balanceOf(user2);
        stakingFactory.withdrawAll(0);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 5);

        // User 3 withdraws
        vm.startPrank(user3);
        uint256 user3BalanceBefore = lpToken.balanceOf(user3);
        stakingFactory.withdrawAll(0);
        vm.stopPrank();

        uint256 entranceFee = stakingPool.entranceFeeFactor();
        // Check balances after withdrawals
        uint256 user1ExpectedBalance = user1BalanceBefore +
            amountUser1 -
            ((amountUser1 * entranceFee) / 10000);
        uint256 user2ExpectedBalance = user2BalanceBefore +
            amountUser2 -
            ((amountUser2 * entranceFee) / 10000);
        uint256 user3ExpectedBalance = user3BalanceBefore +
            amountUser3 -
            ((amountUser3 * entranceFee) / 10000);

        assertEq(lpToken.balanceOf(user), user1ExpectedBalance);
        assertEq(lpToken.balanceOf(user2), user2ExpectedBalance);
        assertEq(lpToken.balanceOf(user3), user3ExpectedBalance);
    }

    function testThreeUsersDepositAndWithdrawCheckRewards() public {
        uint256 rewardAmount = 100 * DECIMAL;
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        stakingFactory.setRewardTokenPerBlock(rewardAmount);
        vm.stopPrank();

        uint256 amountUser1 = 1000 * DECIMAL;
        uint256 amountUser2 = 2000 * DECIMAL;
        uint256 amountUser3 = 1500 * DECIMAL;

        // User 1 deposits
        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amountUser1);
        stakingFactory.deposit(0, amountUser1);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 5);

        // User 2 deposits
        vm.startPrank(user2);
        lpToken.approve(address(stakingFactory), amountUser2);
        stakingFactory.deposit(0, amountUser2);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 10);

        // User 3 deposits
        vm.startPrank(user3);
        lpToken.approve(address(stakingFactory), amountUser3);
        stakingFactory.deposit(0, amountUser3);
        vm.stopPrank();

        // User 1 claims rewards and withdraws
        vm.startPrank(user);
        uint256 user1RewardBeforeWithdraw = rewardToken.balanceOf(user);
        (uint256 user1Shares, uint256 user1RewardDebt) = stakingFactory
            .userInfo(0, user);
        stakingFactory.updatePool(0);
        (, , , uint256 accRewardTokenPerShare, ) = stakingFactory.poolInfo(0);
        uint256 user1ExpectedReward = (user1Shares * accRewardTokenPerShare) /
            1e12 -
            user1RewardDebt;
        stakingFactory.claimReward(0);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 5);

        // User 2 claims rewards and withdraws
        vm.startPrank(user2);
        uint256 user2RewardBeforeWithdraw = rewardToken.balanceOf(user2);
        (uint256 user2Shares, uint256 user2RewardDebt) = stakingFactory
            .userInfo(0, user2);
        stakingFactory.updatePool(0);
        (, , , accRewardTokenPerShare, ) = stakingFactory.poolInfo(0);
        uint256 user2ExpectedReward = (user2Shares * accRewardTokenPerShare) /
            1e12 -
            user2RewardDebt;
        stakingFactory.claimReward(0);
        vm.stopPrank();

        // Advance blocks
        vm.roll(block.number + 5);

        // User 3 claims rewards and withdraws
        vm.startPrank(user3);
        uint256 user3RewardBeforeWithdraw = rewardToken.balanceOf(user3);
        (uint256 user3Shares, uint256 user3RewardDebt) = stakingFactory
            .userInfo(0, user3);
        stakingFactory.updatePool(0);
        (, , , accRewardTokenPerShare, ) = stakingFactory.poolInfo(0);
        uint256 user3ExpectedReward = (user3Shares * accRewardTokenPerShare) /
            1e12 -
            user3RewardDebt;
        stakingFactory.claimReward(0);
        vm.stopPrank();

        // Advance blocks
        // vm.roll(block.number + 5);

        assertEq(
            rewardToken.balanceOf(user),
            user1RewardBeforeWithdraw + user1ExpectedReward
        );
        assertEq(
            rewardToken.balanceOf(user2),
            user2RewardBeforeWithdraw + user2ExpectedReward
        );
        assertEq(
            rewardToken.balanceOf(user3),
            user3RewardBeforeWithdraw + user3ExpectedReward
        );
    }

    function testDepositWithdrawMultiplePools() public {
        vm.startPrank(owner);

        lpToken2 = new MockERC20();
        lpToken3 = new MockERC20();

        lpToken2.mint(user, 10000 * DECIMAL);
        lpToken3.mint(user, 10000 * DECIMAL);

        stakingPool2 = new StakingPool(
            address(stakingFactory),
            address(rewardToken),
            owner,
            address(lpToken2)
        );
        stakingPool3 = new StakingPool(
            address(stakingFactory),
            address(rewardToken),
            owner,
            address(lpToken3)
        );

        stakingFactory.add(100, lpToken, true, address(stakingPool));
        stakingFactory.add(200, lpToken2, true, address(stakingPool2));
        stakingFactory.add(300, lpToken3, true, address(stakingPool3));

        vm.stopPrank();

        uint256 amount = 1000 * DECIMAL;

        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount);
        lpToken2.approve(address(stakingFactory), amount);
        lpToken3.approve(address(stakingFactory), amount);

        stakingFactory.deposit(0, amount);
        stakingFactory.deposit(1, amount);
        stakingFactory.deposit(2, amount);

        stakingFactory.withdraw(0, amount);
        stakingFactory.withdraw(1, amount);
        stakingFactory.withdraw(2, amount);
        vm.stopPrank();

        (uint256 shares1, ) = stakingFactory.userInfo(0, user);
        (uint256 shares2, ) = stakingFactory.userInfo(1, user);
        (uint256 shares3, ) = stakingFactory.userInfo(2, user);

        assertEq(shares1, 0);
        assertEq(shares2, 0);
        assertEq(shares3, 0);
    }

    function testRewardDistributionMultiplePools() public {
        vm.startPrank(owner);

        lpToken2 = new MockERC20();
        lpToken3 = new MockERC20();

        lpToken2.mint(user, 10000 * DECIMAL);
        lpToken3.mint(user, 10000 * DECIMAL);

        stakingPool2 = new StakingPool(
            address(stakingFactory),
            address(rewardToken),
            owner,
            address(lpToken2)
        );
        stakingPool3 = new StakingPool(
            address(stakingFactory),
            address(rewardToken),
            owner,
            address(lpToken3)
        );

        stakingFactory.add(100, lpToken, true, address(stakingPool));
        stakingFactory.add(200, lpToken2, true, address(stakingPool2));
        stakingFactory.add(300, lpToken3, true, address(stakingPool3));

        uint256 rewardAmount = 100 * DECIMAL;
        stakingFactory.setRewardTokenPerBlock(rewardAmount);
        vm.stopPrank();

        uint256 amount = 1000 * DECIMAL;

        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount);
        lpToken2.approve(address(stakingFactory), amount);
        lpToken3.approve(address(stakingFactory), amount);

        stakingFactory.deposit(0, amount);
        stakingFactory.deposit(1, amount);
        stakingFactory.deposit(2, amount);

        // Advance blocks to accumulate rewards
        vm.roll(block.number + 10);

        uint256 initialUserBalance = rewardToken.balanceOf(user);

        stakingFactory.claimReward(0);
        stakingFactory.claimReward(1);
        stakingFactory.claimReward(2);
        vm.stopPrank();

        uint256 finalUserBalance = rewardToken.balanceOf(user);
        assert(finalUserBalance > initialUserBalance);
    }

    function testEmergencyWithdrawMultiplePools() public {
        vm.startPrank(owner);

        lpToken2 = new MockERC20();
        lpToken3 = new MockERC20();

        lpToken2.mint(user, 10000 * DECIMAL);
        lpToken3.mint(user, 10000 * DECIMAL);

        stakingPool2 = new StakingPool(
            address(stakingFactory),
            address(rewardToken),
            owner,
            address(lpToken2)
        );
        stakingPool3 = new StakingPool(
            address(stakingFactory),
            address(rewardToken),
            owner,
            address(lpToken3)
        );

        stakingFactory.add(100, lpToken, true, address(stakingPool));
        stakingFactory.add(200, lpToken2, true, address(stakingPool2));
        stakingFactory.add(300, lpToken3, true, address(stakingPool3));
        vm.stopPrank();

        uint256 amount = 1000 * DECIMAL;

        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount);
        lpToken2.approve(address(stakingFactory), amount);
        lpToken3.approve(address(stakingFactory), amount);

        stakingFactory.deposit(0, amount);
        stakingFactory.deposit(1, amount);
        stakingFactory.deposit(2, amount);

        stakingFactory.emergencyWithdraw(0);
        stakingFactory.emergencyWithdraw(1);
        stakingFactory.emergencyWithdraw(2);
        vm.stopPrank();

        (uint256 shares1, ) = stakingFactory.userInfo(0, user);
        (uint256 shares2, ) = stakingFactory.userInfo(1, user);
        (uint256 shares3, ) = stakingFactory.userInfo(2, user);

        assertEq(shares1, 0);
        assertEq(shares2, 0);
        assertEq(shares3, 0);

        uint256 userBalance1 = lpToken.balanceOf(user);
        uint256 userBalance2 = lpToken2.balanceOf(user);
        uint256 userBalance3 = lpToken3.balanceOf(user);

        assert(userBalance1 >= amount - 3000000000000000000); // Account for fees
        assert(userBalance2 >= amount - 3000000000000000000); // Account for fees
        assert(userBalance3 >= amount - 3000000000000000000); // Account for fees
    }

    function testMultipleUsersDepositToSamePool() public {
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        vm.stopPrank();

        uint256 amount1 = 1000 * DECIMAL;
        uint256 amount2 = 500 * DECIMAL;

        // User 1 deposits
        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount1);
        stakingFactory.deposit(0, amount1);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        lpToken.mint(user2, amount2);
        lpToken.approve(address(stakingFactory), amount2);
        stakingFactory.deposit(0, amount2);
        vm.stopPrank();

        (uint256 shares1, ) = stakingFactory.userInfo(0, user);
        (uint256 shares2, ) = stakingFactory.userInfo(0, user2);

        uint256 entranceFees = stakingPool.entranceFeeFactor();
        amount1 = amount1 - (amount1 * entranceFees) / 10000;
        amount2 = amount2 - (amount2 * entranceFees) / 10000;

        assertEq(shares1, amount1);
        assertEq(shares2, amount2);
    }

    function testUserDepositToMultiplePools() public {
        vm.startPrank(owner);

        lpToken2 = new MockERC20();
        stakingPool2 = new StakingPool(
            address(stakingFactory),
            address(rewardToken),
            owner,
            address(lpToken2)
        );
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        stakingFactory.add(200, lpToken2, true, address(stakingPool2));
        vm.stopPrank();

        uint256 amount1 = 1000 * DECIMAL;
        uint256 amount2 = 500 * DECIMAL;

        lpToken2.mint(user, 10000 * DECIMAL);

        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount1);
        lpToken2.approve(address(stakingFactory), amount2);
        stakingFactory.deposit(0, amount1);
        stakingFactory.deposit(1, amount2);
        vm.stopPrank();

        (uint256 shares1, ) = stakingFactory.userInfo(0, user);
        (uint256 shares2, ) = stakingFactory.userInfo(1, user);

        uint256 entranceFees1 = stakingPool.entranceFeeFactor();
        uint256 entranceFees2 = stakingPool2.entranceFeeFactor();
        amount1 = amount1 - (amount1 * entranceFees1) / 10000;
        amount2 = amount2 - (amount2 * entranceFees2) / 10000;

        assertEq(shares1, amount1);
        assertEq(shares2, amount2);
    }

    function testWithdrawWithCorrectSharesCalculation() public {
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        vm.stopPrank();

        uint256 amount = 1000 * DECIMAL;

        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount);
        stakingFactory.deposit(0, amount);

        (uint256 initialShares, ) = stakingFactory.userInfo(0, user);
        vm.stopPrank();

        vm.startPrank(user);
        stakingFactory.withdraw(0, amount);
        vm.stopPrank();

        (uint256 finalShares, ) = stakingFactory.userInfo(0, user);

        assertEq(
            initialShares,
            amount - (amount * stakingPool.entranceFeeFactor()) / 10000
        );
        assertEq(finalShares, 0);

        uint256 userBalance = lpToken.balanceOf(user);
        assert(userBalance >= amount - 3000000000000000000); // Account for fees
    }

    function testUserDepositAndWithdraw() public {
        vm.startPrank(owner);
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        vm.stopPrank();

        uint256 amount = 1000 * DECIMAL;

        // User deposits
        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount);
        stakingFactory.deposit(0, amount);
        vm.stopPrank();

        // Get the current state after deposit
        uint256 userShares;
        uint256 userRewardDebt;
        (userShares, userRewardDebt) = stakingFactory.userInfo(0, user);

        uint256 entranceFee = (amount * stakingPool.entranceFeeFactor()) /
            10000;
        uint256 expectedShares = amount - entranceFee;

        assertEq(userShares, expectedShares);

        // User withdraws
        vm.startPrank(user);
        stakingFactory.withdraw(0, amount);
        vm.stopPrank();

        (userShares, ) = stakingFactory.userInfo(0, user);
        assertEq(userShares, 0);

        uint256 userBalance = lpToken.balanceOf(user);
        uint256 exitFee = (amount * stakingPool.exitFeeFactor()) / 10000;
        uint256 expectedWithdrawAmount = amount - exitFee;

        assert(userBalance >= expectedWithdrawAmount - 3000000000000000000); // Account for small variations
    }

    function testDifferentEntryFeesForDifferentPools() public {
        vm.startPrank(owner);

        lpToken2 = new MockERC20();
        stakingPool2 = new StakingPool(
            address(stakingFactory),
            address(rewardToken),
            owner,
            address(lpToken2)
        );
        stakingFactory.add(100, lpToken, true, address(stakingPool));
        stakingFactory.add(200, lpToken2, true, address(stakingPool2));
        vm.stopPrank();

        uint256 amount1 = 1000 * DECIMAL;
        uint256 amount2 = 500 * DECIMAL;

        // User deposits to pool 0
        vm.startPrank(user);
        lpToken.approve(address(stakingFactory), amount1);
        stakingFactory.deposit(0, amount1);
        vm.stopPrank();

        // User deposits to pool 1
        vm.startPrank(user);
        lpToken2.mint(user, amount2);
        lpToken2.approve(address(stakingFactory), amount2);
        stakingFactory.deposit(1, amount2);
        vm.stopPrank();

        (uint256 shares1, ) = stakingFactory.userInfo(0, user);
        (uint256 shares2, ) = stakingFactory.userInfo(1, user);

        uint256 entranceFee1 = (amount1 * stakingPool.entranceFeeFactor()) /
            10000;
        uint256 entranceFee2 = (amount2 * stakingPool2.entranceFeeFactor()) /
            10000;

        uint256 expectedShares1 = amount1 - entranceFee1;
        uint256 expectedShares2 = amount2 - entranceFee2;

        assertEq(shares1, expectedShares1);
        assertEq(shares2, expectedShares2);
    }
}
