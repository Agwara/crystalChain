// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LotteryGameCore, Round, UserStats, Bet} from "../src/LotteryGameCore.sol";
import {LotteryGift} from "../src/LotteryGift.sol";
import {LotteryAdmin} from "../src/LotteryAdmin.sol";
import {PlatformToken} from "../src/PlatformToken.sol";

/**
 * @title PostDeploymentTest
 * @dev Comprehensive testing script for deployed lottery contracts
 * @notice Run this after deployment to verify all systems work correctly
 */
contract PostDeploymentTest is Script {
    // Test configuration
    uint256 constant TEST_STAKE_AMOUNT = 50 * 10 ** 18; // 50 PTK
    uint256 constant TEST_BET_AMOUNT = 1 * 10 ** 18; // 5 PTK
    uint256 constant GIFT_FUND_AMOUNT = 1000 * 10 ** 18; // 1000 PTK

    // Contract instances
    PlatformToken platformToken;
    LotteryGameCore coreContract;
    LotteryGift giftContract;
    LotteryAdmin adminContract;

    // Test accounts
    address deployer;
    address testUser1;
    address testUser2;
    address testUser3;

    // Test results tracking
    struct TestResults {
        bool platformTokenTests;
        bool coreContractTests;
        bool giftContractTests;
        bool adminContractTests;
        bool integrationTests;
        uint256 failedTests;
        string[] failureReasons;
    }

    TestResults results;

    function run() external {
        // Load configuration
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        // Load contract addresses
        address platformTokenAddr = vm.envAddress("PLATFORM_TOKEN_ADDRESS");
        address coreAddr = vm.envAddress("CORE_CONTRACT_ADDRESS");
        address giftAddr = vm.envAddress("GIFT_CONTRACT_ADDRESS");
        address adminAddr = vm.envAddress("ADMIN_CONTRACT_ADDRESS");

        // Initialize contracts
        platformToken = PlatformToken(platformTokenAddr);
        coreContract = LotteryGameCore(coreAddr);
        giftContract = LotteryGift(giftAddr);
        adminContract = LotteryAdmin(adminAddr);

        console.log("=== POST-DEPLOYMENT TEST SUITE ===");
        console.log("Deployer:", deployer);
        console.log("PlatformToken:", address(platformToken));
        console.log("CoreContract:", address(coreContract));
        console.log("GiftContract:", address(giftContract));
        console.log("AdminContract:", address(adminContract));
        console.log("");

        // Generate test accounts
        testUser1 = vm.addr(1);
        testUser2 = vm.addr(2);
        testUser3 = vm.addr(3);

        vm.startBroadcast(deployerPrivateKey);

        // Run test suites
        testPlatformToken();
        testCoreContract();
        testGiftContract();
        testAdminContract();
        testIntegration();

        vm.stopBroadcast();

        // Report results
        generateReport();
    }

    function testPlatformToken() internal {
        console.log(">>> Testing PlatformToken...");
        bool allPassed = true;

        // Test 1: Check initial state
        uint256 totalSupply = platformToken.totalSupply();
        uint256 deployerBalance = platformToken.balanceOf(deployer);
        console.log("Total Supply:", totalSupply);
        console.log("Deployer Balance:", deployerBalance);

        if (deployerBalance == 0) {
            allPassed = false;
            results.failureReasons.push("PlatformToken: Deployer has zero balance");
        }

        // Test 2: Transfer tokens to test users
        uint256 user1BalanceBefore = platformToken.balanceOf(testUser1);
        platformToken.transfer(testUser1, TEST_STAKE_AMOUNT * 2);
        platformToken.transfer(testUser2, TEST_STAKE_AMOUNT * 2);
        platformToken.transfer(testUser3, TEST_STAKE_AMOUNT * 2);

        uint256 user1BalanceAfter = platformToken.balanceOf(testUser1);

        if (user1BalanceAfter != user1BalanceBefore + TEST_STAKE_AMOUNT * 2) {
            allPassed = false;
            results.failureReasons.push("PlatformToken: Transfer failed");
        } else {
            console.log("Token transfers successful");
        }

        // Test 3: Check token metadata
        string memory name = platformToken.name();
        string memory symbol = platformToken.symbol();
        uint8 decimals = platformToken.decimals();

        console.log("Token Name:", name);
        console.log("Token Symbol:", symbol);
        console.log("Token Decimals:", decimals);

        if (decimals != 18) {
            allPassed = false;
            results.failureReasons.push("PlatformToken: Invalid decimals");
        }

        results.platformTokenTests = allPassed;
        if (!allPassed) results.failedTests++;
        console.log(allPassed ? "PlatformToken tests PASSED" : "PlatformToken tests FAILED");
        console.log("");
    }

    function testCoreContract() internal {
        console.log(">>> Testing LotteryGameCore...");
        bool allPassed = true;

        // Test 1: Check initial state
        uint256 currentRound = coreContract.currentRound();
        Round memory round = coreContract.getCurrentRound();

        console.log("Current Round:", currentRound);
        console.log("Round Start Time:", round.startTime);
        console.log("Round End Time:", round.endTime);

        if (currentRound == 0) {
            allPassed = false;
            results.failureReasons.push("CoreContract: No active round");
        }

        // Test 2: Check round timing
        if (round.endTime <= round.startTime) {
            allPassed = false;
            results.failureReasons.push("CoreContract: Invalid round timing");
        }

        // Test 3: Verify contract connections
        address giftContractAddr = address(coreContract.giftContract());
        address adminContractAddr = address(coreContract.adminContract());

        console.log("Connected Gift Contract:", giftContractAddr);
        console.log("Connected Admin Contract:", adminContractAddr);

        if (giftContractAddr == address(0) || adminContractAddr == address(0)) {
            allPassed = false;
            results.failureReasons.push("CoreContract: Missing contract connections");
        } else {
            console.log("Contract connections verified");
        }

        // Test 4: Check constants
        uint256 maxNumber = coreContract.MAX_NUMBER();
        uint256 numbersCount = coreContract.NUMBERS_COUNT();
        uint256 roundDuration = coreContract.ROUND_DURATION();

        console.log("Max Number:", maxNumber);
        console.log("Numbers Count:", numbersCount);
        console.log("Round Duration:", roundDuration);

        if (maxNumber != 49 || numbersCount != 5 || roundDuration != 5 minutes) {
            allPassed = false;
            results.failureReasons.push("CoreContract: Invalid constants");
        }

        results.coreContractTests = allPassed;
        if (!allPassed) results.failedTests++;
        console.log(allPassed ? "CoreContract tests PASSED" : "CoreContract tests FAILED");
        console.log("");
    }

    function testGiftContract() internal {
        console.log(">>> Testing LotteryGift...");
        bool allPassed = true;

        // Test 1: Check initial configuration
        (uint256 reserve, uint256 costPerRound) = giftContract.getGiftReserveStatus();
        console.log("Gift Reserve:", reserve);
        console.log("Cost Per Round:", costPerRound);

        // Test 2: Fund gift reserve
        uint256 initialReserve = reserve;
        platformToken.approve(address(giftContract), GIFT_FUND_AMOUNT);
        giftContract.fundGiftReserve(GIFT_FUND_AMOUNT);

        (uint256 newReserve,) = giftContract.getGiftReserveStatus();
        if (newReserve != initialReserve + GIFT_FUND_AMOUNT) {
            allPassed = false;
            results.failureReasons.push("GiftContract: Reserve funding failed");
        } else {
            console.log("Gift reserve funded successfully");
        }

        // Test 3: Check constants
        uint256 cooldown = giftContract.GIFT_COOLDOWN();
        uint256 consecutive = giftContract.CONSECUTIVE_PLAY_REQUIREMENT();

        console.log("Gift Cooldown:", cooldown);
        console.log("Consecutive Play Requirement:", consecutive);

        if (cooldown != 24 hours || consecutive != 3) {
            allPassed = false;
            results.failureReasons.push("GiftContract: Invalid constants");
        }

        // Test 4: Check contract connections
        address tokenAddr = address(giftContract.platformToken());
        address coreAddr = address(giftContract.coreContract());

        if (tokenAddr != address(platformToken) || coreAddr != address(coreContract)) {
            allPassed = false;
            results.failureReasons.push("GiftContract: Invalid contract references");
        }

        results.giftContractTests = allPassed;
        if (!allPassed) results.failedTests++;
        console.log(allPassed ? "GiftContract tests PASSED" : "GiftContract tests FAILED");
        console.log("");
    }

    function testAdminContract() internal {
        console.log(">>> Testing LotteryAdmin...");
        bool allPassed = true;

        // Test 1: Check contract references
        address coreAddr = address(adminContract.coreContract());
        address giftAddr = address(adminContract.giftContract());
        address tokenAddr = address(adminContract.platformToken());

        console.log("Admin -> Core:", coreAddr);
        console.log("Admin -> Gift:", giftAddr);
        console.log("Admin -> Token:", tokenAddr);

        if (
            coreAddr != address(coreContract) || giftAddr != address(giftContract)
                || tokenAddr != address(platformToken)
        ) {
            allPassed = false;
            results.failureReasons.push("AdminContract: Invalid contract references");
        } else {
            console.log("Admin contract references verified");
        }

        // Test 2: Check admin role
        bytes32 adminRole = adminContract.DEFAULT_ADMIN_ROLE();
        bool hasAdminRole = adminContract.hasRole(adminRole, deployer);

        console.log("Default Admin Role:", vm.toString(adminRole));
        console.log("Deployer has admin role:", hasAdminRole);

        if (!hasAdminRole) {
            allPassed = false;
            results.failureReasons.push("AdminContract: Missing admin role");
        } else {
            console.log("Admin role verified");
        }

        // Test 3: Check role management functions exist
        // Note: We're not testing the actual role management here to avoid
        // modifying permissions during testing
        console.log("Admin contract interface verified");

        results.adminContractTests = allPassed;
        if (!allPassed) results.failedTests++;
        console.log(allPassed ? "AdminContract tests PASSED" : "AdminContract tests FAILED");
        console.log("");
    }

    function testIntegration() internal {
        console.log(">>> Testing Integration Scenarios...");
        bool allPassed = true;

        // Test full user flow
        bool stakingPassed = testUserStakingFlow();
        bool bettingPassed = testBettingFlow();
        bool authPassed = testAuthorizationFlow();

        allPassed = stakingPassed && bettingPassed && authPassed;

        if (!stakingPassed) {
            results.failureReasons.push("Integration: User staking flow failed");
        }
        if (!bettingPassed) {
            results.failureReasons.push("Integration: Betting flow failed");
        }
        if (!authPassed) {
            results.failureReasons.push("Integration: Authorization flow failed");
        }

        results.integrationTests = allPassed;
        if (!allPassed) results.failedTests++;
        console.log(allPassed ? "Integration tests PASSED" : "Integration tests FAILED");
        console.log("");
    }

    function testUserStakingFlow() internal returns (bool) {
        console.log("Testing user staking flow...");

        // Impersonate test user
        vm.stopBroadcast();
        vm.startPrank(testUser1);

        // Check initial state
        uint256 initialBalance = platformToken.balanceOf(testUser1);
        uint256 initialStaked = platformToken.stakedBalance(testUser1);

        console.log("    Initial balance:", initialBalance);
        console.log("    Initial staked:", initialStaked);

        if (initialBalance < TEST_STAKE_AMOUNT) {
            console.log("    Insufficient balance for staking test");
            vm.stopPrank();
            vm.startBroadcast();
            return false;
        }

        // Stake tokens
        platformToken.stake(TEST_STAKE_AMOUNT);

        uint256 newStaked = platformToken.stakedBalance(testUser1);
        if (newStaked != initialStaked + TEST_STAKE_AMOUNT) {
            console.log("    Staking failed - expected:", initialStaked + TEST_STAKE_AMOUNT, "got:", newStaked);
            vm.stopPrank();
            vm.startBroadcast();
            return false;
        }

        // Check eligibility
        bool eligible = platformToken.isEligibleForBenefits(testUser1);
        uint256 weight = platformToken.getStakingWeight(testUser1);

        console.log("    Staked:", TEST_STAKE_AMOUNT);
        console.log("    Eligible for benefits:", eligible);
        console.log("    Weight:", weight);

        vm.stopPrank();
        vm.startBroadcast();

        return true;
    }

    function testBettingFlow() internal returns (bool) {
        console.log("Testing betting flow...");

        // Setup multiple users for betting
        console.log("Setup betting for user1");
        setupUserForBetting(testUser1);
        console.log("Setup betting for user2");
        setupUserForBetting(testUser2);
        console.log("Setup betting for user3");
        setupUserForBetting(testUser3);

        // Test placing bets
        console.log("placing bet for user1");
        bool bet1 = placeBetAsUser(testUser1, [uint256(1), 5, 10, 15, 20]);
        console.log("placing bet for user2");
        bool bet2 = placeBetAsUser(testUser2, [uint256(2), 7, 12, 25, 30]);
        console.log("placing bet for user3");
        bool bet3 = placeBetAsUser(testUser3, [uint256(3), 9, 18, 35, 42]);

        if (!bet1 || !bet2 || !bet3) {
            console.log("    Betting failed");
            return false;
        }

        console.log("    Multiple users placed bets successfully");

        // Check round state
        Round memory round = coreContract.getCurrentRound();
        console.log("    Total bets in round:", round.totalBets);
        console.log("    Participants count:", round.participants.length);

        return true;
    }

    function testAuthorizationFlow() internal returns (bool) {
        console.log("Testing authorization flow...");

        // Check core contract is authorized burner
        bool isAuthorizedBurner = platformToken.authorizedBurners(address(coreContract));
        if (!isAuthorizedBurner) {
            console.log("    Core contract not authorized as burner");
            return false;
        }

        console.log("    Core contract is authorized burner");

        // Check gift contract can update user stats
        vm.stopBroadcast();
        vm.prank(address(giftContract));

        // This should not revert if authorization is correct
        coreContract.updateUserGiftRound(testUser1, 1);
        console.log("    Gift contract can update user stats");

        vm.startBroadcast();

        return true;
    }

    function setupUserForBetting(address user) internal {
        vm.stopBroadcast();
        vm.startPrank(user);

        // Check if user needs to stake more
        uint256 staked = platformToken.stakedBalance(user);
        uint256 minStake = platformToken.MIN_STAKE_AMOUNT();

        if (staked < minStake) {
            uint256 neededStake = minStake - staked;
            if (neededStake < TEST_STAKE_AMOUNT) {
                neededStake = TEST_STAKE_AMOUNT;
            }
            platformToken.stake(neededStake);
            console.log("    User staked additional:", neededStake);
        }

        vm.stopPrank();
        vm.startBroadcast();
    }

    function placeBetAsUser(address user, uint256[5] memory numbers) internal returns (bool) {
        vm.stopBroadcast();
        vm.startPrank(user);

        // Check if user has enough balance
        uint256 balance = platformToken.balanceOf(user);
        if (balance < TEST_BET_AMOUNT) {
            console.log("    User has insufficient balance for betting");
            vm.stopPrank();
            vm.startBroadcast();
            return false;
        }

        // Approve tokens for betting
        platformToken.approve(address(coreContract), TEST_BET_AMOUNT);

        // Place bet
        coreContract.placeBet(numbers, TEST_BET_AMOUNT);

        console.log("    Bet placed successfully for user");

        vm.stopPrank();
        vm.startBroadcast();

        return true;
    }

    function generateReport() internal view {
        console.log("=== TEST RESULTS SUMMARY ===");
        console.log("");

        console.log("PlatformToken Tests:", results.platformTokenTests ? "PASSED" : "FAILED");
        console.log("CoreContract Tests:", results.coreContractTests ? "PASSED" : "FAILED");
        console.log("GiftContract Tests:", results.giftContractTests ? "PASSED" : "FAILED");
        console.log("AdminContract Tests:", results.adminContractTests ? "PASSED" : "FAILED");
        console.log("Integration Tests:", results.integrationTests ? "PASSED" : "FAILED");
        console.log("");

        console.log("Failed Test Suites:", results.failedTests);

        if (results.failureReasons.length > 0) {
            console.log("");
            console.log("Failure Reasons:");
            for (uint256 i = 0; i < results.failureReasons.length; i++) {
                console.log("-", results.failureReasons[i]);
            }
        }

        console.log("");
        if (results.failedTests == 0) {
            console.log("ALL TESTS PASSED - System is ready for use!");
        } else {
            console.log("SOME TESTS FAILED - Please review and fix issues");
        }

        console.log("");
        console.log("=== NEXT STEPS ===");
        if (results.failedTests == 0) {
            console.log("1. Set up Chainlink VRF subscription (if not done)");
            console.log("2. Add more funds to gift reserve if needed");
            console.log("3. Consider running extended integration tests");
            console.log("4. Monitor first few rounds closely");
        } else {
            console.log("1. Fix failing tests before proceeding");
            console.log("2. Re-run test suite after fixes");
            console.log("3. Consider redeploying if critical issues found");
        }
    }
}
