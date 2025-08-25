// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console, Script} from "forge-std/Script.sol";

// Interface matching your exact PlatformToken contract
interface IPlatformToken {
    // Basic ERC20 functions
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);

    // Staking functions
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function emergencyUnstake() external;
    function stakedBalance(address user) external view returns (uint256);
    function stakingTimestamp(address user) external view returns (uint256);

    // Platform constants
    function MIN_STAKE_AMOUNT() external pure returns (uint256);
    function MAX_STAKE_PER_USER() external pure returns (uint256);
    function MIN_STAKE_DURATION() external pure returns (uint256);

    // Utility functions
    function isEligibleForBenefits(address user) external view returns (bool);
    function getStakingWeight(address user) external view returns (uint256);
    function getStakingInfo(address user) external view returns (uint256 staked, uint256 timestamp, bool canUnstake);
    function getSupplyStats() external view returns (uint256 circulating, uint256 staked, uint256 burned);

    // Staking state
    function totalStaked() external view returns (uint256);
    function totalBurned() external view returns (uint256);
    function emergencyWithdrawalEnabled() external view returns (bool);

    // Burning functions
    function burn(uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
}

contract StakeTokens is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);

        // Get platform token address
        address tokenAddress = 0xECEfF35FE011694DfCEa93E97bba60D2FEEc2253;
        uint256 stakeAmount = uint256(100 * 10 ** 18);

        console.log("=== Staking Platform Tokens ===");
        console.log("Token Address:", tokenAddress);
        console.log("User Address:", user);
        console.log("Stake Amount:", stakeAmount);

        vm.startBroadcast(privateKey);

        IPlatformToken token = IPlatformToken(tokenAddress);

        // Check current balances and staking info
        uint256 balance = token.balanceOf(user);
        uint256 stakedBalance = token.stakedBalance(user);
        uint256 minStakeAmount = token.MIN_STAKE_AMOUNT();
        uint256 maxStakePerUser = token.MAX_STAKE_PER_USER();
        uint256 minStakeDuration = token.MIN_STAKE_DURATION();

        console.log("\n=== Current Status ===");
        console.log("Token Balance:", balance);
        console.log("Current Staked:", stakedBalance);
        console.log("Minimum Stake Amount:", minStakeAmount);
        console.log("Maximum Stake Per User:", maxStakePerUser);
        console.log("Minimum Stake Duration:", minStakeDuration, "seconds");
        console.log("Eligible for Benefits:", token.isEligibleForBenefits(user));
        console.log("Staking Weight:", token.getStakingWeight(user));

        // Get detailed staking info
        (uint256 staked, uint256 timestamp, bool canUnstake) = token.getStakingInfo(user);
        console.log("Staking Timestamp:", timestamp);
        console.log("staked: ", staked);
        console.log("Can Unstake Now:", canUnstake);
        if (timestamp > 0 && !canUnstake) {
            uint256 timeLeft = (timestamp + minStakeDuration) - block.timestamp;
            console.log("Time until can unstake:", timeLeft, "seconds");
        }

        // Validate stake amount
        if (stakeAmount < minStakeAmount) {
            console.log("\nError: Stake amount is below minimum required");
            console.log("Minimum required:", minStakeAmount);
            console.log("Requested amount:", stakeAmount);
            vm.stopBroadcast();
            return;
        }

        if (stakedBalance + stakeAmount > maxStakePerUser) {
            console.log("\nError: Stake amount would exceed maximum per user");
            console.log("Current staked:", stakedBalance);
            console.log("Trying to add:", stakeAmount);
            console.log("Maximum allowed:", maxStakePerUser);
            vm.stopBroadcast();
            return;
        }

        if (balance < stakeAmount) {
            console.log("\nError: Insufficient token balance");
            console.log("Available:", balance);
            console.log("Required:", stakeAmount);
            vm.stopBroadcast();
            return;
        }

        // Stake tokens
        console.log("\n=== Staking Tokens ===");
        console.log("Staking", stakeAmount, "tokens...");

        try token.stake(stakeAmount) {
            console.log("Tokens staked successfully!");
        } catch Error(string memory reason) {
            console.log("Staking failed:", reason);
            vm.stopBroadcast();
            return;
        } catch {
            console.log("Staking failed: Unknown error");
            vm.stopBroadcast();
            return;
        }

        // Check new balances
        uint256 newBalance = token.balanceOf(user);
        uint256 newStakedBalance = token.stakedBalance(user);

        console.log("\n=== Updated Status ===");
        console.log("New Token Balance:", newBalance);
        console.log("New Staked Balance:", newStakedBalance);

        vm.stopBroadcast();
    }
}

contract UnstakeTokens is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);

        address tokenAddress = 0xECEfF35FE011694DfCEa93E97bba60D2FEEc2253;
        uint256 unstakeAmount = vm.envOr("UNSTAKE_AMOUNT", uint256(50 * 10 ** 18)); // 50 tokens default

        console.log("=== Unstaking Platform Tokens ===");
        console.log("Token Address:", tokenAddress);
        console.log("User Address:", user);
        console.log("Unstake Amount:", unstakeAmount);

        vm.startBroadcast(privateKey);

        IPlatformToken token = IPlatformToken(tokenAddress);

        // Check current status
        uint256 balance = token.balanceOf(user);
        uint256 stakedBalance = token.stakedBalance(user);
        uint256 minStakeAmount = token.MIN_STAKE_AMOUNT();
        bool emergencyEnabled = token.emergencyWithdrawalEnabled();

        console.log("\n=== Current Status ===");
        console.log("Token Balance:", balance);
        console.log("Staked Balance:", stakedBalance);
        console.log("Minimum Stake Amount:", minStakeAmount);
        console.log("Emergency Withdrawal Enabled:", emergencyEnabled);

        // Get staking info to check if can unstake
        (uint256 staked, uint256 timestamp, bool canUnstake) = token.getStakingInfo(user);
        console.log("Can Unstake:", canUnstake, "staked: ", staked);
        if (!canUnstake && !emergencyEnabled) {
            uint256 minDuration = token.MIN_STAKE_DURATION();
            uint256 timeLeft = (timestamp + minDuration) - block.timestamp;
            console.log("Time until can unstake:", timeLeft, "seconds");
        }

        // Validate unstake amount
        if (unstakeAmount > stakedBalance) {
            console.log("\nError: Unstake amount exceeds staked balance");
            console.log("Staked balance:", stakedBalance);
            console.log("Requested unstake:", unstakeAmount);
            vm.stopBroadcast();
            return;
        }

        // Check if can unstake now
        if (!canUnstake && !emergencyEnabled) {
            console.log("\nError: Cannot unstake yet - minimum duration not met");
            console.log("Use emergencyUnstake if emergency withdrawal is enabled");
            vm.stopBroadcast();
            return;
        }

        // Check if remaining stake will be above minimum (if not unstaking all)
        uint256 remainingStake = stakedBalance - unstakeAmount;
        if (remainingStake > 0 && remainingStake < minStakeAmount) {
            console.log("\nWarning: Remaining stake would be below minimum");
            console.log("Consider unstaking all or leaving at least", minStakeAmount);
            console.log("Remaining would be:", remainingStake);
            // Continue anyway - let the contract decide
        }

        // Unstake tokens
        console.log("\n=== Unstaking Tokens ===");
        console.log("Unstaking", unstakeAmount, "tokens...");

        try token.unstake(unstakeAmount) {
            console.log("Tokens unstaked successfully!");
        } catch Error(string memory reason) {
            console.log("Unstaking failed:", reason);
            vm.stopBroadcast();
            return;
        } catch {
            console.log("Unstaking failed: Unknown error");
            vm.stopBroadcast();
            return;
        }

        // Check new balances
        uint256 newBalance = token.balanceOf(user);
        uint256 newStakedBalance = token.stakedBalance(user);

        console.log("\n=== Updated Status ===");
        console.log("New Token Balance:", newBalance);
        console.log("New Staked Balance:", newStakedBalance);

        vm.stopBroadcast();
    }
}

contract CheckStakingStatus is Script {
    function run() external view {
        address userAddress = vm.addr(vm.envUint("PRIVATE_KEY"));
        address tokenAddress = 0xECEfF35FE011694DfCEa93E97bba60D2FEEc2253;

        console.log("=== Staking Status Check ===");
        console.log("Token Address:", tokenAddress);
        console.log("User Address:", userAddress);

        IPlatformToken token = IPlatformToken(tokenAddress);

        // Get all staking information
        uint256 balance = token.balanceOf(userAddress);
        uint256 stakedBalance = token.stakedBalance(userAddress);
        uint256 minStakeAmount = token.MIN_STAKE_AMOUNT();
        uint256 maxStakePerUser = token.MAX_STAKE_PER_USER();
        uint256 minStakeDuration = token.MIN_STAKE_DURATION();
        bool eligibleForBenefits = token.isEligibleForBenefits(userAddress);
        uint256 stakingWeight = token.getStakingWeight(userAddress);
        bool emergencyEnabled = token.emergencyWithdrawalEnabled();

        // Get detailed staking info
        (uint256 staked, uint256 timestamp, bool canUnstake) = token.getStakingInfo(userAddress);
        console.log("staked: ", staked);
        // Get supply statistics

        console.log("\n=== Token Balances ===");
        console.log("Available Balance:", balance);
        console.log("Staked Balance:", stakedBalance);

        console.log("\n=== Staking Requirements ===");
        console.log("Minimum Stake Amount:", minStakeAmount);
        console.log("Maximum Stake Per User:", maxStakePerUser);
        // console.log("Minimum Stake Duration:", minStakeDuration, "seconds (", minStakeDuration / 3600, "hours )");
        console.log("Meets Minimum:", stakedBalance >= minStakeAmount);

        console.log("\n=== Staking Status ===");
        console.log("Staking Timestamp:", timestamp);
        if (timestamp > 0) {
            console.log("Staking Duration:", block.timestamp - timestamp, "seconds");
            console.log("Can Unstake:", canUnstake);
            if (!canUnstake && !emergencyEnabled) {
                uint256 timeLeft = (timestamp + minStakeDuration) - block.timestamp;
                console.log("Time until unstake:", timeLeft, "seconds");
            }
        }
        console.log("Emergency Withdrawal Enabled:", emergencyEnabled);

        console.log("\n=== Benefits & Weight ===");
        console.log("Eligible for Benefits:", eligibleForBenefits);
        console.log("Staking Weight:", stakingWeight);
    }
}

contract ClaimStakingRewards is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);

        address tokenAddress = 0xECEfF35FE011694DfCEa93E97bba60D2FEEc2253;
        uint256 burnAmount = vm.envOr("BURN_AMOUNT", uint256(10 * 10 ** 18)); // 10 tokens default

        console.log("=== Burning Platform Tokens ===");
        console.log("Token Address:", tokenAddress);
        console.log("User Address:", user);
        console.log("Burn Amount:", burnAmount);

        vm.startBroadcast(privateKey);

        IPlatformToken token = IPlatformToken(tokenAddress);

        // Check balance
        uint256 balance = token.balanceOf(user);
        uint256 stakedBalance = token.stakedBalance(user);
        console.log("Available Balance:", balance);
        console.log("Staked Balance:", stakedBalance);

        if (balance < burnAmount) {
            console.log("Insufficient balance to burn");
            console.log("Available:", balance);
            console.log("Required:", burnAmount);
            vm.stopBroadcast();
            return;
        }

        // Get current burn stats
        (,, uint256 totalBurnedBefore) = token.getSupplyStats();
        console.log("Total burned before:", totalBurnedBefore);

        // Burn tokens
        console.log("Burning tokens...");
        try token.burn(burnAmount) {
            console.log("Tokens burned successfully!");

            // Check new stats
            uint256 newBalance = token.balanceOf(user);
            (,, uint256 totalBurnedAfter) = token.getSupplyStats();

            console.log("New balance:", newBalance);
            console.log("Total burned after:", totalBurnedAfter);
            console.log("Burn amount confirmed:", totalBurnedAfter - totalBurnedBefore);
        } catch Error(string memory reason) {
            console.log("Burn failed:", reason);
        }

        vm.stopBroadcast();
    }
}

contract EmergencyUnstake is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);

        address tokenAddress = 0xECEfF35FE011694DfCEa93E97bba60D2FEEc2253;

        console.log("=== Emergency Unstake ===");
        console.log("Token Address:", tokenAddress);
        console.log("User Address:", user);

        vm.startBroadcast(privateKey);

        IPlatformToken token = IPlatformToken(tokenAddress);

        // Check current status
        uint256 stakedBalance = token.stakedBalance(user);
        bool emergencyEnabled = token.emergencyWithdrawalEnabled();
        (uint256 staked, uint256 timestamp, bool canUnstake) = token.getStakingInfo(user);
        console.log("Can timestamp:", timestamp, "staked: ", staked);
        console.log("Current Staked Balance:", stakedBalance);
        console.log("Emergency Withdrawal Enabled:", emergencyEnabled);
        console.log("Can Unstake Normally:", canUnstake);

        if (stakedBalance == 0) {
            console.log("No tokens staked");
            vm.stopBroadcast();
            return;
        }

        if (!emergencyEnabled) {
            console.log("Emergency withdrawal is not enabled");
            console.log("Wait for normal unstaking period or contact admin");
            vm.stopBroadcast();
            return;
        }

        // Emergency unstake all tokens
        console.log("Performing emergency unstake...");
        try token.emergencyUnstake() {
            console.log("Emergency unstake successful!");

            uint256 newBalance = token.balanceOf(user);
            uint256 newStakedBalance = token.stakedBalance(user);

            console.log("New token balance:", newBalance);
            console.log("New staked balance:", newStakedBalance);
        } catch Error(string memory reason) {
            console.log("Emergency unstake failed:", reason);
        }

        vm.stopBroadcast();
    }
}

contract BatchStakeForMultipleUsers is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address tokenAddress = 0xECEfF35FE011694DfCEa93E97bba60D2FEEc2253;

        // Example addresses - replace with actual addresses
        address[] memory users = new address[](3);
        users[0] = 0x1234567890123456789012345678901234567890;
        users[1] = 0x2345678901234567890123456789012345678901;
        users[2] = 0x3456789012345678901234567890123456789012;

        uint256 stakeAmountPerUser = vm.envOr("STAKE_PER_USER", uint256(100 * 10 ** 18));

        console.log("=== Batch Staking for Multiple Users ===");
        console.log("Token Address:", tokenAddress);
        console.log("Stake per user:", stakeAmountPerUser);
        console.log("Number of users:", users.length);

        vm.startBroadcast(privateKey);

        IPlatformToken token = IPlatformToken(tokenAddress);

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            console.log("\nProcessing user", i + 1, ":", user);

            uint256 balance = token.balanceOf(user);
            uint256 currentStaked = token.stakedBalance(user);
            uint256 maxStakePerUser = token.MAX_STAKE_PER_USER();

            console.log("Current balance:", balance);
            console.log("Current staked:", currentStaked);
            console.log("Max stake per user:", maxStakePerUser);

            if (balance >= stakeAmountPerUser && currentStaked + stakeAmountPerUser <= maxStakePerUser) {
                try token.stake(stakeAmountPerUser) {
                    console.log("Staked", stakeAmountPerUser, "for", user);
                } catch Error(string memory reason) {
                    console.log("Staking failed for", user, ":", reason);
                }
            } else if (balance < stakeAmountPerUser) {
                console.log("Insufficient balance for", user);
            } else {
                console.log("Would exceed max stake limit for", user);
            }
        }

        vm.stopBroadcast();
    }
}

contract StakeMinimumForLottery is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);

        address tokenAddress = 0xECEfF35FE011694DfCEa93E97bba60D2FEEc2253;

        console.log("=== Staking Minimum for Lottery Participation ===");
        console.log("Token Address:", tokenAddress);
        console.log("User Address:", user);

        vm.startBroadcast(privateKey);

        IPlatformToken token = IPlatformToken(tokenAddress);

        uint256 minStakeAmount = token.MIN_STAKE_AMOUNT();
        uint256 currentStaked = token.stakedBalance(user);
        uint256 balance = token.balanceOf(user);
        uint256 maxStakePerUser = token.MAX_STAKE_PER_USER();

        console.log("Minimum stake required:", minStakeAmount);
        console.log("Currently staked:", currentStaked);
        console.log("Available balance:", balance);
        console.log("Maximum stake per user:", maxStakePerUser);

        if (currentStaked >= minStakeAmount) {
            console.log("Already eligible for lottery participation!");
            console.log("Current staking weight:", token.getStakingWeight(user));
            console.log("Eligible for benefits:", token.isEligibleForBenefits(user));
            vm.stopBroadcast();
            return;
        }

        uint256 neededAmount = minStakeAmount - currentStaked;
        console.log("Additional amount needed:", neededAmount);

        if (balance < neededAmount) {
            console.log("Insufficient balance to meet minimum stake");
            console.log("Need:", neededAmount);
            console.log("Have:", balance);
            vm.stopBroadcast();
            return;
        }

        if (currentStaked + neededAmount > maxStakePerUser) {
            console.log("Would exceed maximum stake per user");
            console.log("Current + needed:", currentStaked + neededAmount);
            console.log("Maximum allowed:", maxStakePerUser);
            vm.stopBroadcast();
            return;
        }

        // Stake the minimum required amount
        console.log("Staking minimum required amount:", neededAmount);

        try token.stake(neededAmount) {
            console.log("Minimum stake completed!");
            console.log("New staked balance:", token.stakedBalance(user));
            console.log("Eligible for lottery:", token.isEligibleForBenefits(user));
        } catch Error(string memory reason) {
            console.log("Staking failed:", reason);
        }

        vm.stopBroadcast();
    }
}
