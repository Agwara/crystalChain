// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/LotteryGame.sol";

contract TestLottery is Script {
    function run() external {
        // Load deployment info
        string memory deploymentFile = "./deployments/Sepolia_deployment.json";
        string memory json = vm.readFile(deploymentFile);

        address lotteryAddress = vm.parseJsonAddress(json, ".lotteryGame");
        address tokenAddress = vm.parseJsonAddress(json, ".platformToken");

        console.log("Testing LotteryGame at:", lotteryAddress);
        console.log("Using Platform Token at:", tokenAddress);

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        LotteryGame lottery = LotteryGame(lotteryAddress);
        IERC20 token = IERC20(tokenAddress);

        // Get contract info
        console.log("\n=== Contract Info ===");
        console.log("Current Round:", lottery.currentRound());
        console.log("User Token Balance:", token.balanceOf(user));
        console.log("Contract Token Balance:", token.balanceOf(lotteryAddress));

        // Get current round info
        LotteryGame.Round memory round = lottery.getCurrentRound();
        console.log("Round Start Time:", round.startTime);
        console.log("Round End Time:", round.endTime);
        console.log("Round Active:", block.timestamp < round.endTime);

        // Get user stats
        LotteryGame.UserStats memory userStats = lottery.getUserStats(user);
        console.log("User Consecutive Rounds:", userStats.consecutiveRounds);
        console.log("User Total Bets:", userStats.totalBets);
        console.log("User Eligible for Gift:", userStats.isEligibleForGift);

        // Check gift reserve
        (uint256 reserve, uint256 costPerRound) = lottery.getGiftReserveStatus();
        console.log("Gift Reserve:", reserve);
        console.log("Cost Per Round:", costPerRound);

        vm.stopBroadcast();
    }
}

contract PlaceBet is Script {
    function run() external {
        // Load deployment info
        string memory deploymentFile = "./deployments/Sepolia_deployment.json";
        string memory json = vm.readFile(deploymentFile);

        address lotteryAddress = vm.parseJsonAddress(json, ".lotteryGame");
        address tokenAddress = vm.parseJsonAddress(json, ".platformToken");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);

        // Example bet: numbers [5, 15, 25, 35, 45] with 1 token
        uint256[5] memory numbers = [5, 15, 25, 35, 45];
        uint256 betAmount = 1 * 10 ** 18; // 1 token

        console.log("Placing bet with numbers:", numbers[0], numbers[1], numbers[2], numbers[3], numbers[4]);
        console.log("Bet amount:", betAmount);

        vm.startBroadcast(privateKey);

        LotteryGame lottery = LotteryGame(lotteryAddress);
        IERC20 token = IERC20(tokenAddress);

        // Check if round is active
        LotteryGame.Round memory round = lottery.getCurrentRound();
        if (block.timestamp >= round.endTime) {
            console.log("Round has ended, cannot place bet");
            vm.stopBroadcast();
            return;
        }

        // Check token balance
        uint256 balance = token.balanceOf(user);
        console.log("User token balance:", balance);

        if (balance < betAmount) {
            console.log("Insufficient token balance");
            vm.stopBroadcast();
            return;
        }

        // Approve tokens
        console.log("Approving tokens...");
        token.approve(lotteryAddress, betAmount);

        // Place bet
        console.log("Placing bet...");
        lottery.placeBet(numbers, betAmount);

        console.log("Bet placed successfully!");

        vm.stopBroadcast();
    }
}

contract EndRound is Script {
    function run() external {
        // Load deployment info
        string memory deploymentFile = "./deployments/Sepolia_deployment.json";
        string memory json = vm.readFile(deploymentFile);

        address lotteryAddress = vm.parseJsonAddress(json, ".lotteryGame");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        LotteryGame lottery = LotteryGame(lotteryAddress);

        // Get current round info
        LotteryGame.Round memory round = lottery.getCurrentRound();
        console.log("Current Round:", lottery.currentRound());
        console.log("Round End Time:", round.endTime);
        console.log("Current Time:", block.timestamp);

        if (block.timestamp < round.endTime) {
            console.log("Round has not ended yet");
            vm.stopBroadcast();
            return;
        }

        if (round.numbersDrawn) {
            console.log("Numbers already drawn for this round");
            vm.stopBroadcast();
            return;
        }

        // End round (will trigger VRF request)
        console.log("Ending round...");
        lottery.endRound();

        console.log("Round ended, VRF request sent");
        console.log("Wait for VRF callback to complete number drawing");

        vm.stopBroadcast();
    }
}

contract CheckWinnings is Script {
    function run() external {
        // Load deployment info
        string memory deploymentFile = "./deployments/Sepolia_deployment.json";
        string memory json = vm.readFile(deploymentFile);

        address lotteryAddress = vm.parseJsonAddress(json, ".lotteryGame");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);

        uint256 roundId = vm.envOr("ROUND_ID", uint256(1));

        vm.startBroadcast(privateKey);

        LotteryGame lottery = LotteryGame(lotteryAddress);

        console.log("Checking winnings for round:", roundId);
        console.log("User address:", user);

        // Get round info
        LotteryGame.Round memory round = lottery.getRound(roundId);
        console.log("Numbers drawn:", round.numbersDrawn);

        if (!round.numbersDrawn) {
            console.log("Numbers not yet drawn for this round");
            vm.stopBroadcast();
            return;
        }

        console.log(
            "Winning numbers:",
            round.winningNumbers[0],
            round.winningNumbers[1],
            round.winningNumbers[2],
            round.winningNumbers[3],
            round.winningNumbers[4]
        );

        // Check claimable winnings
        (uint256 totalWinnings, uint256[] memory claimableBets) = lottery.getClaimableWinnings(roundId, user);

        console.log("Total claimable winnings:", totalWinnings);
        console.log("Number of winning bets:", claimableBets.length);

        if (totalWinnings > 0) {
            console.log("Claiming winnings...");
            lottery.claimWinnings(roundId, claimableBets);
            console.log("Winnings claimed successfully!");
        } else {
            console.log("No winnings to claim");
        }

        vm.stopBroadcast();
    }
}

contract FundGifts is Script {
    function run() external {
        // Load deployment info
        string memory deploymentFile = "./deployments/Sepolia_deployment.json";
        string memory json = vm.readFile(deploymentFile);

        address lotteryAddress = vm.parseJsonAddress(json, ".lotteryGame");
        address tokenAddress = vm.parseJsonAddress(json, ".platformToken");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(privateKey);

        uint256 fundAmount = vm.envOr("FUND_AMOUNT", uint256(5000 * 10 ** 18)); // 5000 tokens default

        vm.startBroadcast(privateKey);

        LotteryGame lottery = LotteryGame(lotteryAddress);
        IERC20 token = IERC20(tokenAddress);

        console.log("Funding gift reserve with:", fundAmount);
        console.log("User token balance:", token.balanceOf(user));

        // Approve and fund
        token.approve(lotteryAddress, fundAmount);
        lottery.fundGiftReserve(fundAmount);

        console.log("Gift reserve funded successfully!");

        // Check new reserve status
        (uint256 reserve, uint256 costPerRound) = lottery.getGiftReserveStatus();
        console.log("New gift reserve:", reserve);
        console.log("Rounds fundable:", reserve / costPerRound);

        vm.stopBroadcast();
    }
}
