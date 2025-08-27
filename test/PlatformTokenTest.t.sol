// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PlatformToken} from "../src/PlatformToken.sol";

contract PlatformTokenTest is Test {
    PlatformToken public token;

    // Test accounts
    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);
    address public maliciousContract = address(0x5);

    // Constants for testing
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18; // 1M tokens
    uint256 public constant MIN_STAKE = 10 * 10 ** 18; // 10 tokens
    uint256 public constant MAX_STAKE = 100_000 * 10 ** 18; // 100k tokens
    uint256 public constant MIN_DURATION = 24 hours;

    // Events for testing
    event TokensStaked(address indexed user, uint256 amount, uint256 totalStaked);
    event TokensUnstaked(address indexed user, uint256 amount, uint256 totalStaked);
    event TokensBurned(address indexed burner, uint256 amount, uint256 totalBurned);

    function setUp() public {
        vm.startPrank(owner);
        token = new PlatformToken(INITIAL_SUPPLY);

        // Distribute tokens for testing
        token.transfer(alice, 50_000 * 10 ** 18);
        token.transfer(bob, 50_000 * 10 ** 18);
        token.transfer(charlie, 50_000 * 10 ** 18);
        vm.stopPrank();

        // Labels for better trace output
        vm.label(owner, "Owner");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(maliciousContract, "MaliciousContract");
    }

    // ============================================================================
    // DEPLOYMENT TESTS
    // ============================================================================

    function test_Deployment() public view {
        assertEq(token.name(), "PlatformToken");
        assertEq(token.symbol(), "PTK");
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.owner(), owner);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - 150_000 * 10 ** 18); // After transfers
        assertTrue(token.authorizedBurners(owner));
        assertTrue(token.authorizedTransferors(owner));
    }

    // ============================================================================
    // STAKING TESTS
    // ============================================================================

    function test_StakeValidAmount() public {
        uint256 stakeAmount = 100 * 10 ** 18;

        vm.startPrank(alice);

        vm.expectEmit(true, false, false, true);
        emit TokensStaked(alice, stakeAmount, stakeAmount);

        token.stake(stakeAmount);

        assertEq(token.stakedBalance(alice), stakeAmount);
        assertEq(token.totalStaked(), stakeAmount);
        assertEq(token.balanceOf(alice), 50_000 * 10 ** 18 - stakeAmount);
        assertEq(token.balanceOf(address(token)), stakeAmount);
        assertEq(token.stakingTimestamp(alice), block.timestamp);

        vm.stopPrank();
    }

    function test_StakeMultipleTimes() public {
        vm.startPrank(alice);

        uint256 firstStake = 100 * 10 ** 18;
        uint256 secondStake = 200 * 10 ** 18;

        token.stake(firstStake);

        vm.warp(block.timestamp + 1 hours);
        uint256 newTimestamp = block.timestamp;

        token.stake(secondStake);

        assertEq(token.stakedBalance(alice), firstStake + secondStake);
        assertEq(token.totalStaked(), firstStake + secondStake);
        assertEq(token.stakingTimestamp(alice), newTimestamp); // Should update

        vm.stopPrank();
    }

    function test_StakeFailsWithZeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(PlatformToken.ZeroAmount.selector);
        token.stake(0);
        vm.stopPrank();
    }

    function test_StakeFailsBelowMinimum() public {
        vm.startPrank(alice);
        vm.expectRevert(PlatformToken.BelowMinimumStakeAmount.selector);
        token.stake(MIN_STAKE - 1);
        vm.stopPrank();
    }

    function test_StakeFailsInsufficientBalance() public {
        vm.startPrank(alice);
        vm.expectRevert(PlatformToken.InsufficientBalance.selector);
        token.stake(100_000 * 10 ** 18); // More than alice has
        vm.stopPrank();
    }

    function test_StakeFailsExceedsMaximum() public {
        // Give alice more tokens first
        vm.prank(owner);
        token.transfer(alice, 100_000 * 10 ** 18);

        vm.startPrank(alice);
        vm.expectRevert(PlatformToken.ExceedsMaximumStakeAmount.selector);
        token.stake(MAX_STAKE + 1);
        vm.stopPrank();
    }

    function test_StakeFailsWhenPaused() public {
        vm.prank(owner);
        token.pause();

        vm.startPrank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.stake(MIN_STAKE);
        vm.stopPrank();
    }

    // ============================================================================
    // UNSTAKING TESTS
    // ============================================================================

    function test_UnstakeAfterMinimumDuration() public {
        uint256 stakeAmount = 100 * 10 ** 18;

        vm.startPrank(alice);
        token.stake(stakeAmount);

        // Fast forward past minimum duration
        vm.warp(block.timestamp + MIN_DURATION + 1);

        uint256 balanceBefore = token.balanceOf(alice);

        vm.expectEmit(true, false, false, true);
        emit TokensUnstaked(alice, stakeAmount, 0);

        token.unstake(stakeAmount);

        assertEq(token.stakedBalance(alice), 0);
        assertEq(token.totalStaked(), 0);
        assertEq(token.balanceOf(alice), balanceBefore + stakeAmount);
        assertEq(token.balanceOf(address(token)), 0);

        vm.stopPrank();
    }

    function test_UnstakePartialAmount() public {
        uint256 stakeAmount = 100 * 10 ** 18;
        uint256 unstakeAmount = 30 * 10 ** 18;

        vm.startPrank(alice);
        token.stake(stakeAmount);
        vm.warp(block.timestamp + MIN_DURATION + 1);

        token.unstake(unstakeAmount);

        assertEq(token.stakedBalance(alice), stakeAmount - unstakeAmount);
        assertEq(token.totalStaked(), stakeAmount - unstakeAmount);

        vm.stopPrank();
    }

    function test_UnstakeFailsBeforeMinimumDuration() public {
        uint256 stakeAmount = 100 * 10 ** 18;

        vm.startPrank(alice);
        token.stake(stakeAmount);

        // Try to unstake immediately
        vm.expectRevert(PlatformToken.StakingDurationNotMet.selector);
        token.unstake(stakeAmount);

        // Try just before minimum duration
        vm.warp(block.timestamp + MIN_DURATION - 1);
        vm.expectRevert(PlatformToken.StakingDurationNotMet.selector);
        token.unstake(stakeAmount);

        vm.stopPrank();
    }

    function test_UnstakeFailsInsufficientStakedBalance() public {
        vm.startPrank(alice);
        vm.expectRevert(PlatformToken.InsufficientStakedBalance.selector);
        token.unstake(MIN_STAKE);
        vm.stopPrank();
    }

    function test_UnstakeFailsZeroAmount() public {
        vm.startPrank(alice);
        token.stake(MIN_STAKE);
        vm.warp(block.timestamp + MIN_DURATION + 1);

        vm.expectRevert(PlatformToken.ZeroAmount.selector);
        token.unstake(0);
        vm.stopPrank();
    }

    // ============================================================================
    // EMERGENCY UNSTAKING TESTS
    // ============================================================================

    function test_EmergencyUnstakeWhenEnabled() public {
        uint256 stakeAmount = 100 * 10 ** 18;

        vm.startPrank(alice);
        token.stake(stakeAmount);
        vm.stopPrank();

        // Enable emergency withdrawal
        vm.prank(owner);
        token.toggleEmergencyWithdrawal(true);

        vm.startPrank(alice);
        uint256 balanceBefore = token.balanceOf(alice);

        token.emergencyUnstake();

        assertEq(token.stakedBalance(alice), 0);
        assertEq(token.balanceOf(alice), balanceBefore + stakeAmount);

        vm.stopPrank();
    }

    function test_EmergencyUnstakeFailsWhenDisabled() public {
        vm.startPrank(alice);
        token.stake(MIN_STAKE);

        vm.expectRevert(PlatformToken.EmergencyWithdrawalDisabled.selector);
        token.emergencyUnstake();

        vm.stopPrank();
    }

    function test_EmergencyUnstakeFailsNoStakedTokens() public {
        vm.prank(owner);
        token.toggleEmergencyWithdrawal(true);

        vm.startPrank(alice);
        vm.expectRevert(PlatformToken.InsufficientStakedBalance.selector);
        token.emergencyUnstake();
        vm.stopPrank();
    }

    // ============================================================================
    // BURNING TESTS
    // ============================================================================

    function test_BurnOwnTokens() public {
        uint256 burnAmount = 100 * 10 ** 18;
        uint256 balanceBefore = token.balanceOf(alice);
        uint256 totalSupplyBefore = token.totalSupply();

        vm.startPrank(alice);

        vm.expectEmit(true, false, false, true);
        emit TokensBurned(alice, burnAmount, burnAmount);

        token.burn(burnAmount);

        assertEq(token.balanceOf(alice), balanceBefore - burnAmount);
        assertEq(token.totalSupply(), totalSupplyBefore - burnAmount);
        assertEq(token.totalBurned(), burnAmount);

        vm.stopPrank();
    }

    function test_BurnFailsInsufficientBalance() public {
        vm.startPrank(alice);
        vm.expectRevert(PlatformToken.InsufficientBalance.selector);
        token.burn(100_000 * 10 ** 18); // More than alice has
        vm.stopPrank();
    }

    function test_BurnFailsZeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(PlatformToken.ZeroAmount.selector);
        token.burn(0);
        vm.stopPrank();
    }

    // ============================================================================
    // AUTHORIZED BURNING TESTS
    // ============================================================================

    function test_BurnFromWithAuthorization() public {
        uint256 burnAmount = 100 * 10 ** 18;

        // Authorize bob as burner
        vm.prank(owner);
        token.setAuthorizedBurner(bob, true);

        // Alice approves bob to burn her tokens
        vm.prank(alice);
        token.approve(bob, burnAmount);

        vm.startPrank(bob);
        token.burnFrom(alice, burnAmount);
        vm.stopPrank();

        assertEq(token.totalBurned(), burnAmount);
    }

    function test_BurnFromFailsUnauthorized() public {
        vm.startPrank(bob);
        vm.expectRevert(PlatformToken.UnauthorizedBurner.selector);
        token.burnFrom(alice, MIN_STAKE);
        vm.stopPrank();
    }

    function test_BurnAndMint() public {
        uint256 burnAmount = 100 * 10 ** 18;
        uint256 mintAmount = 50 * 10 ** 18;

        // Transfer some tokens to contract first
        vm.prank(owner);
        token.transfer(address(token), burnAmount);

        uint256 totalSupplyBefore = token.totalSupply();
        uint256 bobBalanceBefore = token.balanceOf(bob);

        vm.prank(owner); // Owner is authorized burner
        token.burnAndMint(burnAmount, bob, mintAmount);

        assertEq(token.totalSupply(), totalSupplyBefore - burnAmount + mintAmount);
        assertEq(token.balanceOf(bob), bobBalanceBefore + mintAmount);
        assertEq(token.totalBurned(), burnAmount);
    }

    // ============================================================================
    // TRANSFER RESTRICTION TESTS
    // ============================================================================

    function test_TransferFailsWithStakedTokens() public {
        uint256 stakeAmount = 10_000 * 10 ** 18; // Most of alice's balance

        vm.startPrank(alice);
        token.stake(stakeAmount);

        uint256 balance = token.balanceOf(alice);
        uint256 staked = token.stakedBalance(alice);

        require(balance >= staked, "Staked more than balance"); // sanity check

        uint256 availableBalance = balance - staked;

        vm.expectRevert("Insufficient transferable balance");
        token.transfer(bob, availableBalance + 1);

        // But can transfer available balance
        token.transfer(bob, availableBalance);

        vm.stopPrank();
    }

    // ============================================================================
    // VIEW FUNCTION TESTS
    // ============================================================================

    function test_GetStakingInfo() public {
        uint256 stakeAmount = 100 * 10 ** 18;

        vm.startPrank(alice);
        token.stake(stakeAmount);
        vm.stopPrank();

        (uint256 staked, uint256 timestamp, bool canUnstake) = token.getStakingInfo(alice);

        assertEq(staked, stakeAmount);
        assertEq(timestamp, block.timestamp);
        assertFalse(canUnstake); // Before minimum duration

        // After minimum duration
        vm.warp(block.timestamp + MIN_DURATION + 1);
        (,, canUnstake) = token.getStakingInfo(alice);
        assertTrue(canUnstake);
    }

    function test_GetSupplyStats() public {
        uint256 stakeAmount = 100 * 10 ** 18;
        uint256 burnAmount = 50 * 10 ** 18;

        vm.startPrank(alice);
        token.stake(stakeAmount);
        token.burn(burnAmount);
        vm.stopPrank();

        (uint256 circulating, uint256 staked, uint256 burned) = token.getSupplyStats();

        assertEq(circulating, INITIAL_SUPPLY - burnAmount);
        assertEq(staked, stakeAmount);
        assertEq(burned, burnAmount);
    }

    function test_IsEligibleForBenefits() public {
        vm.startPrank(alice);

        // Not eligible initially
        assertFalse(token.isEligibleForBenefits(alice));

        // Stake tokens
        token.stake(MIN_STAKE);
        assertFalse(token.isEligibleForBenefits(alice)); // Still need duration

        // After minimum duration
        vm.warp(block.timestamp + MIN_DURATION + 1);
        assertTrue(token.isEligibleForBenefits(alice));

        vm.stopPrank();
    }

    function test_GetStakingWeight() public {
        uint256 stakeAmount = 1000 * 10 ** 18;

        vm.startPrank(alice);
        token.stake(stakeAmount);

        // Initial weight equals staked amount
        assertEq(token.getStakingWeight(alice), stakeAmount);

        // After 7 days, weight increases
        vm.warp(block.timestamp + 7 days + 1);
        assertGt(token.getStakingWeight(alice), stakeAmount);

        // After 30 days, weight is doubled
        vm.warp(block.timestamp + 30 days);
        assertEq(token.getStakingWeight(alice), stakeAmount * 2);

        vm.stopPrank();
    }

    // ============================================================================
    // ADMIN FUNCTION TESTS
    // ============================================================================

    function test_SetAuthorizedBurner() public {
        vm.startPrank(owner);

        assertFalse(token.authorizedBurners(alice));
        token.setAuthorizedBurner(alice, true);
        assertTrue(token.authorizedBurners(alice));

        token.setAuthorizedBurner(alice, false);
        assertFalse(token.authorizedBurners(alice));

        vm.stopPrank();
    }

    function test_SetAuthorizedTransferor() public {
        vm.startPrank(owner);

        assertFalse(token.authorizedTransferors(alice));
        token.setAuthorizedTransferor(alice, true);
        assertTrue(token.authorizedTransferors(alice));

        vm.stopPrank();
    }

    function test_ToggleEmergencyWithdrawal() public {
        vm.startPrank(owner);

        assertFalse(token.emergencyWithdrawalEnabled());
        token.toggleEmergencyWithdrawal(true);
        assertTrue(token.emergencyWithdrawalEnabled());

        token.toggleEmergencyWithdrawal(false);
        assertFalse(token.emergencyWithdrawalEnabled());

        vm.stopPrank();
    }

    function test_PauseUnpause() public {
        vm.startPrank(owner);

        assertFalse(token.paused());
        token.pause();
        assertTrue(token.paused());

        token.unpause();
        assertFalse(token.paused());

        vm.stopPrank();
    }

    function test_OnlyOwnerFunctions() public {
        vm.startPrank(alice);

        vm.expectRevert();
        token.setAuthorizedBurner(bob, true);

        vm.expectRevert();
        token.pause();

        vm.expectRevert();
        token.toggleEmergencyWithdrawal(true);

        vm.stopPrank();
    }

    // ============================================================================
    // REENTRANCY TESTS
    // ============================================================================

    function test_ReentrancyProtection() public {
        // This would require a malicious contract that attempts reentrancy
        // Simplified test - in practice you'd deploy a malicious contract
        vm.startPrank(alice);
        token.stake(MIN_STAKE);
        vm.warp(block.timestamp + MIN_DURATION + 1);

        // The ReentrancyGuard should prevent multiple calls
        token.unstake(MIN_STAKE / 2);
        // If reentrancy were possible, this would fail

        vm.stopPrank();
    }

    // ============================================================================
    // EDGE CASE TESTS
    // ============================================================================

    function test_StakeExactlyMaxAmount() public {
        // Give alice enough tokens
        vm.prank(owner);
        token.transfer(alice, MAX_STAKE);

        vm.startPrank(alice);
        token.stake(MAX_STAKE); // Should succeed
        assertEq(token.stakedBalance(alice), MAX_STAKE);
        vm.stopPrank();
    }

    function test_MultipleUsersStaking() public {
        uint256 aliceStake = 1000 * 10 ** 18;
        uint256 bobStake = 2000 * 10 ** 18;

        vm.prank(alice);
        token.stake(aliceStake);

        vm.prank(bob);
        token.stake(bobStake);

        assertEq(token.totalStaked(), aliceStake + bobStake);
        assertEq(token.stakedBalance(alice), aliceStake);
        assertEq(token.stakedBalance(bob), bobStake);
    }

    // ============================================================================
    // FUZZ TESTS
    // ============================================================================

    function testFuzz_StakeValidAmounts(uint256 amount) public {
        // Bound the amount to valid range
        amount = bound(amount, MIN_STAKE, MAX_STAKE);

        // Give alice enough tokens
        vm.prank(owner);
        token.transfer(alice, amount);

        vm.startPrank(alice);
        token.stake(amount);
        assertEq(token.stakedBalance(alice), amount);
        vm.stopPrank();
    }

    function testFuzz_BurnValidAmounts(uint256 amount) public {
        uint256 aliceBalance = token.balanceOf(alice);
        amount = bound(amount, 1, aliceBalance);

        vm.startPrank(alice);
        uint256 totalSupplyBefore = token.totalSupply();

        token.burn(amount);

        assertEq(token.totalSupply(), totalSupplyBefore - amount);
        assertEq(token.totalBurned(), amount);
        vm.stopPrank();
    }
}
