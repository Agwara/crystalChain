// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {LotteryGameCore, Round, Bet, UserStats} from "../src/LotteryGameCore.sol";
import {LotteryGift} from "../src/LotteryGift.sol";
import {LotteryAdmin} from "../src/LotteryAdmin.sol";
import {PlatformToken} from "../src/PlatformToken.sol";
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";

contract ModularLotteryGameTest is Test {
    LotteryGameCore public coreContract;
    LotteryGift public giftContract;
    LotteryAdmin public adminContract;
    PlatformToken public token;
    MockVRFCoordinator public mockVRF;

    address public creator = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public player3 = address(0x4);
    address public operator = address(0x5);
    address public giftDistributor = address(0x6);
    address public admin = address(0x7);

    uint64 public constant SUBSCRIPTION_ID = 1;
    bytes32 public constant KEY_HASH = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    uint256 public constant INITIAL_SUPPLY = 1_000_000_000_000 * 10 ** 18;
    uint256 public constant STAKE_AMOUNT = 100 * 10 ** 18;
    uint256 public constant BET_AMOUNT = 1 * 10 ** 18;

    // Events to test
    event RoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime);
    event BetPlaced(uint256 indexed roundId, address indexed user, uint256[5] numbers, uint256 amount);
    event NumbersDrawn(uint256 indexed roundId, uint256[5] winningNumbers);
    event WinningsClaimed(uint256 indexed roundId, address indexed user, uint256 amount, uint8 matchCount);
    event GiftDistributed(uint256 indexed roundId, address indexed recipient, uint256 amount, bool isCreator);
    event GiftReserveFunded(address indexed funder, uint256 amount);
    event GiftSettingsUpdated(uint256 recipients, uint256 creatorAmount, uint256 userAmount);
    event MaxPayoutUpdated(uint256 newMaxPayout);
    event GiftContractSet(address indexed newGiftContract);
    event AdminContractSet(address indexed newAdminContract);

    function setUp() public {
        // Deploy mock VRF coordinator
        mockVRF = new MockVRFCoordinator();

        // Deploy platform token
        token = new PlatformToken(INITIAL_SUPPLY);

        // Deploy core lottery contract
        coreContract = new LotteryGameCore(address(token), address(mockVRF), SUBSCRIPTION_ID, KEY_HASH);

        // Deploy gift contract
        giftContract = new LotteryGift(address(coreContract), address(token), creator);

        // Deploy admin contract
        adminContract = new LotteryAdmin(address(coreContract), address(giftContract), address(token));

        // Set up contract relationships
        _setupContractRelationships();

        // Fund contracts with tokens
        token.transfer(address(coreContract), INITIAL_SUPPLY / 3);
        token.transfer(address(giftContract), INITIAL_SUPPLY / 3);

        // Setup roles
        coreContract.grantRole(coreContract.OPERATOR_ROLE(), operator);
        giftContract.grantRole(giftContract.GIFT_DISTRIBUTOR_ROLE(), giftDistributor);
        adminContract.grantRole(adminContract.DEFAULT_ADMIN_ROLE(), admin);
        giftContract.grantRole(giftContract.DEFAULT_ADMIN_ROLE(), address(adminContract));

        // Authorize lottery contract to burn tokens
        token.setAuthorizedBurner(address(coreContract), true);
        token.setAuthorizedTransferor(address(coreContract), true);

        // Setup test accounts

        _setupTestAccounts();

        vm.warp(block.timestamp + 1);
    }

    function _setupContractRelationships() internal {
        console.log("inner");
        // Set gift contract in core contract
        // vm.startPrank(admin);
        coreContract.updateGiftContract(address(giftContract));

        // Set admin contract in core contract
        coreContract.updateAdminContract(address(adminContract));
        // vm.stopPrank();
    }

    function _setupTestAccounts() internal {
        address[4] memory accounts = [player1, player2, player3, operator];

        for (uint256 i = 0; i < accounts.length; i++) {
            // Transfer tokens to test accounts
            token.transfer(accounts[i], 100000 * 10 ** 18);

            // Stake tokens to become eligible
            vm.startPrank(accounts[i]);
            token.stake(STAKE_AMOUNT);
            vm.stopPrank();
        }
    }

    function _getValidNumbers() internal pure returns (uint256[5] memory) {
        return [uint256(1), 5, 15, 25, 35];
    }

    function _getValidNumbers2() internal pure returns (uint256[5] memory) {
        return [uint256(2), 10, 20, 30, 40];
    }

    function _getValidNumbers3() internal pure returns (uint256[5] memory) {
        return [uint256(3), 8, 18, 28, 38];
    }

    // =============================================================
    //                        DEPLOYMENT TESTS
    // =============================================================

    function test_Deployment() public view {
        assertEq(address(coreContract.platformToken()), address(token));
        assertEq(coreContract.currentRound(), 1);
        assertEq(giftContract.creator(), creator);
        assertTrue(coreContract.hasRole(coreContract.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(coreContract.hasRole(coreContract.OPERATOR_ROLE(), operator));
        assertTrue(giftContract.hasRole(giftContract.GIFT_DISTRIBUTOR_ROLE(), giftDistributor));

        // Test contract relationships
        assertEq(coreContract.giftContract(), address(giftContract));
        assertEq(coreContract.adminContract(), address(adminContract));
    }

    function test_InitialRoundStarted() public view {
        Round memory round = coreContract.getCurrentRound();
        assertEq(round.roundId, 1);
        assertEq(round.startTime, block.timestamp - 1);
        assertEq(round.endTime, block.timestamp - 1 + coreContract.ROUND_DURATION());
        assertFalse(round.numbersDrawn);
        assertEq(round.totalBets, 0);
    }

    // =============================================================
    //                        BETTING TESTS
    // =============================================================

    function test_PlaceBet_Success() public {
        uint256[5] memory numbers = _getValidNumbers();

        vm.startPrank(player1);
        token.approve(address(coreContract), BET_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit BetPlaced(1, player1, numbers, BET_AMOUNT);

        coreContract.placeBet(numbers, BET_AMOUNT);
        vm.stopPrank();

        // Verify bet was placed
        Bet memory bet = coreContract.getBet(1, 0);
        assertEq(bet.user, player1);
        assertEq(bet.amount, BET_AMOUNT);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(bet.numbers[i], numbers[i]);
        }

        // Verify round stats updated
        Round memory round = coreContract.getCurrentRound();
        assertEq(round.totalBets, BET_AMOUNT);
        assertEq(round.totalPrizePool, BET_AMOUNT);

        // Verify user stats updated
        uint256[] memory userBets = coreContract.getUserRoundBets(1, player1);
        assertEq(userBets.length, 1);
        assertEq(userBets[0], 0);
    }

    function test_PlaceBet_MultipleUsers() public {
        uint256[5] memory numbers1 = _getValidNumbers();
        uint256[5] memory numbers2 = _getValidNumbers2();

        // Player 1 bets
        vm.startPrank(player1);
        token.approve(address(coreContract), BET_AMOUNT);
        coreContract.placeBet(numbers1, BET_AMOUNT);
        vm.stopPrank();

        // Player 2 bets
        vm.startPrank(player2);
        token.approve(address(coreContract), BET_AMOUNT);
        coreContract.placeBet(numbers2, BET_AMOUNT);
        vm.stopPrank();

        Round memory round = coreContract.getCurrentRound();
        assertEq(round.totalBets, BET_AMOUNT * 2);
        assertEq(round.participants.length, 2);
    }

    function test_PlaceBet_MultipleFromSameUser() public {
        uint256[5] memory numbers1 = _getValidNumbers();
        uint256[5] memory numbers2 = _getValidNumbers2();

        vm.startPrank(player1);
        token.approve(address(coreContract), BET_AMOUNT * 2);

        coreContract.placeBet(numbers1, BET_AMOUNT);
        coreContract.placeBet(numbers2, BET_AMOUNT);
        vm.stopPrank();

        uint256[] memory userBets = coreContract.getUserRoundBets(1, player1);
        assertEq(userBets.length, 2);

        Round memory round = coreContract.getCurrentRound();
        assertEq(round.participants.length, 1); // Same user
        assertEq(round.totalBets, BET_AMOUNT * 2);
    }

    function test_PlaceBet_RevertInvalidNumbers() public {
        vm.startPrank(player1);
        token.approve(address(coreContract), BET_AMOUNT);

        // Test duplicate numbers
        uint256[5] memory duplicateNumbers = [uint256(1), 1, 5, 10, 15];
        vm.expectRevert(LotteryGameCore.InvalidNumbers.selector);
        coreContract.placeBet(duplicateNumbers, BET_AMOUNT);

        // Test number out of range (0)
        uint256[5] memory zeroNumbers = [uint256(0), 5, 10, 15, 20];
        vm.expectRevert(LotteryGameCore.InvalidNumbers.selector);
        coreContract.placeBet(zeroNumbers, BET_AMOUNT);

        // Test number out of range (50)
        uint256[5] memory highNumbers = [uint256(5), 10, 15, 20, 50];
        vm.expectRevert(LotteryGameCore.InvalidNumbers.selector);
        coreContract.placeBet(highNumbers, BET_AMOUNT);

        // Test unsorted numbers
        uint256[5] memory unsortedNumbers = [uint256(5), 1, 10, 15, 20];
        vm.expectRevert(LotteryGameCore.InvalidNumbers.selector);
        coreContract.placeBet(unsortedNumbers, BET_AMOUNT);

        vm.stopPrank();
    }

    function test_PlaceBet_RevertInsufficientStake() public {
        // Create user with no stake
        address unstaked = address(0x99);
        token.transfer(unstaked, 1000 * 10 ** 18);

        vm.startPrank(unstaked);
        token.approve(address(coreContract), BET_AMOUNT);

        vm.expectRevert(LotteryGameCore.NotEligibleForBetting.selector);
        coreContract.placeBet(_getValidNumbers(), BET_AMOUNT);
        vm.stopPrank();
    }

    function test_PlaceBet_RevertLowAmount() public {
        vm.startPrank(player1);
        token.approve(address(coreContract), type(uint256).max);

        uint256 lowAmount = coreContract.MIN_BET_AMOUNT() - 1;

        vm.expectRevert(LotteryGameCore.BetAmountTooLow.selector);
        coreContract.placeBet(_getValidNumbers(), lowAmount);

        vm.stopPrank();
    }

    function test_PlaceBet_RevertExceedsMaxPerRound() public {
        uint256 maxBet = coreContract.MAX_BET_PER_USER_PER_ROUND();

        vm.startPrank(player1);
        token.approve(address(coreContract), maxBet + 1);

        vm.expectRevert(LotteryGameCore.ExceedsMaxBetPerRound.selector);
        coreContract.placeBet(_getValidNumbers(), maxBet + 1);
        vm.stopPrank();
    }

    function test_PlaceBet_RevertRoundEnded() public {
        // Fast forward past round end
        vm.warp(block.timestamp + coreContract.ROUND_DURATION() + 1);

        vm.startPrank(player1);
        token.approve(address(coreContract), BET_AMOUNT);

        vm.expectRevert(LotteryGameCore.RoundNotActive.selector);
        coreContract.placeBet(_getValidNumbers(), BET_AMOUNT);
        vm.stopPrank();
    }

    // =============================================================
    //                     ROUND MANAGEMENT TESTS
    // =============================================================

    function test_EndRound_Success() public {
        // Place some bets
        _placeBetsForRound(1);

        // Fast forward to round end
        vm.warp(block.timestamp + coreContract.ROUND_DURATION() + 1);

        uint256 vrfRequestId = mockVRF.getNextRequestId();

        coreContract.endRound();

        // Verify VRF request was made
        Round memory round = coreContract.getRound(1);
        assertEq(round.vrfRequestId, vrfRequestId);
        assertEq(coreContract.vrfRequestToRound(vrfRequestId), 1);
    }

    function test_EndRound_RevertNotEnded() public {
        vm.expectRevert(LotteryGameCore.RoundNotEnded.selector);
        coreContract.endRound();
    }

    function test_VRFResponse_NewRoundStarted() public {
        uint256 initialRound = coreContract.currentRound();

        _placeBetsForRound(1);

        // Fast forward and end round
        vm.warp(block.timestamp + coreContract.ROUND_DURATION() + 1);
        coreContract.endRound();

        // Simulate VRF response
        uint256[] memory randomWords = new uint256[](5);
        randomWords[0] = 12345;
        randomWords[1] = 67890;
        randomWords[2] = 11111;
        randomWords[3] = 22222;
        randomWords[4] = 33333;

        vm.expectEmit(true, false, false, false);
        emit NumbersDrawn(1, [uint256(0), 0, 0, 0, 0]); // We don't know exact numbers

        vm.expectEmit(true, false, false, true);
        emit RoundStarted(initialRound + 1, block.timestamp, block.timestamp + coreContract.ROUND_DURATION());

        mockVRF.fulfillRandomWords(coreContract.getRound(1).vrfRequestId, randomWords);

        // Verify new round started
        assertEq(coreContract.currentRound(), initialRound + 1);
        assertTrue(coreContract.getRound(1).numbersDrawn);
    }

    function test_EmergencyDrawNumbers() public {
        _placeBetsForRound(1);

        // Fast forward and end round
        vm.warp(block.timestamp + coreContract.ROUND_DURATION() + 1);
        coreContract.endRound();

        // Fast forward past emergency threshold
        vm.warp(block.timestamp + 2 hours);

        uint256[5] memory emergencyNumbers = [uint256(1), 5, 15, 25, 35];

        vm.prank(operator);
        vm.expectEmit(true, false, false, true);
        emit NumbersDrawn(1, emergencyNumbers);

        coreContract.emergencyDrawNumbers(1, emergencyNumbers);

        assertTrue(coreContract.getRound(1).numbersDrawn);
    }

    // =============================================================
    //                       WINNING & CLAIMING TESTS
    // =============================================================

    function test_ClaimWinnings_FullMatch() public {
        uint256[5] memory numbers = [uint256(1), 5, 15, 25, 35];

        // Place bet
        vm.startPrank(player1);
        token.approve(address(coreContract), BET_AMOUNT);
        coreContract.placeBet(numbers, BET_AMOUNT);
        vm.stopPrank();

        // End round and set winning numbers to match
        _endRoundWithNumbers(1, numbers);

        // Check claimable winnings
        (uint256 totalWinnings, uint256[] memory claimableBets) = coreContract.getClaimableWinnings(1, player1);

        console.log("Total Winnings: %s", totalWinnings);
        console.log("Claimable Bets Length: %s", claimableBets.length);

        assertEq(claimableBets.length, 1);

        uint256 expectedPayout = (BET_AMOUNT * 800 * (10000 - coreContract.HOUSE_EDGE())) / 10000;
        assertEq(totalWinnings, expectedPayout);

        // Claim winnings
        uint256 balanceBefore = token.balanceOf(player1);

        vm.prank(player1);
        vm.expectEmit(true, true, false, true);
        emit WinningsClaimed(1, player1, expectedPayout, 5);

        coreContract.claimWinnings(1, claimableBets);

        assertEq(token.balanceOf(player1), balanceBefore + expectedPayout);
    }

    function test_ClaimWinnings_PartialMatch() public {
        uint256[5] memory betNumbers = [uint256(1), 5, 15, 25, 35];
        uint256[5] memory winningNumbers = [uint256(1), 5, 15, 30, 40]; // 3 matches

        // Place bet
        vm.startPrank(player1);
        token.approve(address(coreContract), BET_AMOUNT);
        coreContract.placeBet(betNumbers, BET_AMOUNT);
        vm.stopPrank();

        // End round with partial match
        _endRoundWithNumbers(1, winningNumbers);

        // Check claimable winnings
        (uint256 totalWinnings,) = coreContract.getClaimableWinnings(1, player1);
        uint256 expectedPayout = (BET_AMOUNT * 8 * (10000 - coreContract.HOUSE_EDGE())) / 10000;
        assertEq(totalWinnings, expectedPayout);
    }

    function test_ClaimWinnings_NoMatch() public {
        uint256[5] memory betNumbers = [uint256(1), 5, 15, 25, 35];
        uint256[5] memory winningNumbers = [uint256(2), 6, 16, 26, 36]; // 0 matches

        // Place bet
        vm.startPrank(player1);
        token.approve(address(coreContract), BET_AMOUNT);
        coreContract.placeBet(betNumbers, BET_AMOUNT);
        vm.stopPrank();

        // End round with no match
        _endRoundWithNumbers(1, winningNumbers);

        // Check claimable winnings
        (uint256 totalWinnings,) = coreContract.getClaimableWinnings(1, player1);
        assertEq(totalWinnings, 0);
    }

    function test_ClaimWinnings_RevertAlreadyClaimed() public {
        uint256[5] memory numbers = [uint256(1), 5, 15, 25, 35];

        // Setup winning scenario
        vm.startPrank(player1);
        token.approve(address(coreContract), BET_AMOUNT);
        coreContract.placeBet(numbers, BET_AMOUNT);
        vm.stopPrank();

        _endRoundWithNumbers(1, numbers);

        (, uint256[] memory claimableBets) = coreContract.getClaimableWinnings(1, player1);

        // Claim once
        vm.prank(player1);
        coreContract.claimWinnings(1, claimableBets);

        // Try to claim again
        vm.prank(player1);
        vm.expectRevert(LotteryGameCore.AlreadyClaimed.selector);
        coreContract.claimWinnings(1, claimableBets);
    }

    // =============================================================
    //                        GIFT SYSTEM TESTS
    // =============================================================

    function test_FundGiftReserve() public {
        uint256 fundAmount = 1000 * 10 ** 18;

        vm.startPrank(player1);
        token.approve(address(giftContract), fundAmount);

        vm.expectEmit(true, false, false, true);
        emit GiftReserveFunded(player1, fundAmount);

        giftContract.fundGiftReserve(fundAmount);
        vm.stopPrank();

        (uint256 reserve,) = giftContract.getGiftReserveStatus();
        assertEq(reserve, fundAmount);
    }

    function test_DistributeGifts() public {
        // Fund gift reserve
        uint256 fundAmount = 1000 * 10 ** 18;
        vm.startPrank(player1);
        token.approve(address(giftContract), fundAmount);
        giftContract.fundGiftReserve(fundAmount);
        vm.stopPrank();

        // Setup consecutive play
        _setupConsecutivePlay();

        // End round 3
        _endRoundWithNumbers(3, [uint256(1), 2, 3, 4, 5]);

        vm.prank(giftDistributor);
        giftContract.distributeGifts(3);

        // Verify gifts were distributed
        assertTrue(coreContract.getRound(3).giftsDistributed);
    }

    // function test_DistributeGifts_RevertInsufficientReserve() public {
    //     _endRoundWithNumbers(1, [uint256(1), 2, 3, 4, 5]);

    //     vm.prank(giftDistributor);
    //     vm.expectRevert(LotteryGift.InsufficientGiftReserve.selector);
    //     giftContract.distributeGifts(1);
    // }

    // =============================================================
    //                        ADMIN TESTS
    // =============================================================

    function test_UpdateGiftSettings() public {
        uint256 newRecipients = 15;
        uint256 newCreatorAmount = 200 * 10 ** 18;
        uint256 newUserAmount = 75 * 10 ** 18;

        vm.expectEmit(false, false, false, true);
        emit GiftSettingsUpdated(newRecipients, newCreatorAmount, newUserAmount);

        adminContract.updateGiftSettings(newRecipients, newCreatorAmount, newUserAmount);

        assertEq(giftContract.giftRecipientsCount(), newRecipients);
        assertEq(giftContract.creatorGiftAmount(), newCreatorAmount);
        assertEq(giftContract.userGiftAmount(), newUserAmount);
    }

    function test_PauseUnpause() public {
        vm.prank(admin);
        adminContract.pause();
        assertTrue(coreContract.paused());

        vm.startPrank(player1);
        token.approve(address(coreContract), BET_AMOUNT);
        vm.expectRevert();
        coreContract.placeBet(_getValidNumbers(), BET_AMOUNT);
        vm.stopPrank();

        vm.prank(admin);
        adminContract.unpause();
        assertFalse(coreContract.paused());
    }

    function test_EmergencyWithdraw() public {
        // Fund core contract with some tokens
        uint256 withdrawAmount = 1000 * 10 ** 18;

        uint256 balanceBefore = token.balanceOf(admin);

        vm.prank(admin);
        adminContract.emergencyWithdraw(withdrawAmount);

        assertEq(token.balanceOf(admin), balanceBefore + withdrawAmount);
    }

    // =============================================================
    //                        TIMELOCK TESTS
    // =============================================================

    function test_MaxPayoutTimelock() public {
        uint256 newMaxPayout = 20_000 * 10 ** 18;

        vm.prank(admin);
        // Schedule change
        adminContract.scheduleMaxPayoutChange(newMaxPayout);

        // Try to execute immediately (should fail)
        vm.prank(admin);
        vm.expectRevert(LotteryAdmin.TimelockNotReady.selector);
        adminContract.setMaxPayoutPerRound(newMaxPayout);

        // Wait for timelock
        vm.warp(block.timestamp + 25 hours);

        // Execute change
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit MaxPayoutUpdated(newMaxPayout);

        adminContract.setMaxPayoutPerRound(newMaxPayout);
        assertEq(coreContract.maxPayoutPerRound(), newMaxPayout);
    }

    // =============================================================
    //                    CONTRACT RELATIONSHIP TESTS
    // =============================================================

    function test_ContractRelationships() public view {
        // Test that contracts are properly connected
        assertEq(coreContract.giftContract(), address(giftContract));
        assertEq(coreContract.adminContract(), address(adminContract));

        // Test that gift contract knows about core contract
        assertEq(address(giftContract.coreContract()), address(coreContract));

        // Test that admin contract knows about both
        assertEq(address(adminContract.coreContract()), address(coreContract));
        assertEq(address(adminContract.giftContract()), address(giftContract));
    }

    function test_UpdateGiftContract_Success() public {
        // Test updating gift contract with DEFAULT_ADMIN_ROLE
        address newGiftContract = address(0x999);

        vm.expectEmit(true, false, false, false);
        emit GiftContractSet(newGiftContract);

        coreContract.updateGiftContract(newGiftContract);
        assertEq(coreContract.giftContract(), newGiftContract);
    }

    function test_UpdateAdminContract_Success() public {
        // Test updating admin contract with DEFAULT_ADMIN_ROLE
        address newAdminContract = address(0x998);

        vm.expectEmit(true, false, false, false);
        emit AdminContractSet(newAdminContract);

        coreContract.updateAdminContract(newAdminContract);
        assertEq(coreContract.adminContract(), newAdminContract);
    }

    // =============================================================
    //                        HELPER FUNCTIONS
    // =============================================================

    function _placeBetsForRound(uint256 roundId) internal {
        require(coreContract.currentRound() == roundId, "Wrong round");

        address[3] memory players = [player1, player2, player3];
        uint256[5][3] memory numberSets = [_getValidNumbers(), _getValidNumbers2(), _getValidNumbers3()];

        for (uint256 i = 0; i < players.length; i++) {
            vm.startPrank(players[i]);
            token.approve(address(coreContract), BET_AMOUNT);
            coreContract.placeBet(numberSets[i], BET_AMOUNT);
            vm.stopPrank();
        }
    }

    function _endRoundWithNumbers(uint256 roundId, uint256[5] memory winningNumbers) internal {
        vm.warp(block.timestamp + coreContract.ROUND_DURATION() + 2 hours);
        coreContract.endRound();

        // Use emergency draw to set specific numbers
        vm.prank(operator);
        coreContract.emergencyDrawNumbers(roundId, winningNumbers);
    }

    function _setupConsecutivePlay() internal {
        // Place bets for 3 consecutive rounds to make players eligible for gifts
        for (uint256 round = 1; round <= 3; round++) {
            _placeBetsForRound(round);

            if (round < 3) {
                _endRoundWithNumbers(round, [uint256(1), 2, 3, 4, 5]);
            }
        }
    }

    // =============================================================
    //                        VIEW FUNCTION TESTS
    // =============================================================

    function test_ViewFunctions() public view {
        // Test getCurrentRound
        Round memory currentRound = coreContract.getCurrentRound();
        assertEq(currentRound.roundId, 1);

        // Test getUserStats
        UserStats memory stats = coreContract.getUserStats(player1);
        assertEq(stats.totalBets, 0); // No bets placed yet

        // Test getGiftReserveStatus
        (uint256 reserve, uint256 costPerRound) = giftContract.getGiftReserveStatus();
        assertEq(reserve, 0); // No funds added yet
        assertTrue(costPerRound > 0); // Should have some cost
    }
}
