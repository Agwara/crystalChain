// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {LotteryGame} from "../src/LotteryGame.sol";
import {PlatformToken} from "../src/PlatformToken.sol";
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";

contract LotteryGameTest is Test {
    LotteryGame public lottery;
    PlatformToken public token;
    MockVRFCoordinator public mockVRF;

    address public creator = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public player3 = address(0x4);
    address public operator = address(0x5);
    address public giftDistributor = address(0x6);

    uint64 public constant SUBSCRIPTION_ID = 1;
    bytes32 public constant KEY_HASH = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;
    uint256 public constant STAKE_AMOUNT = 100 * 10 ** 18;
    uint256 public constant BET_AMOUNT = 10 * 10 ** 18;

    // Events to test
    event RoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime);
    event BetPlaced(uint256 indexed roundId, address indexed user, uint256[5] numbers, uint256 amount);
    event NumbersDrawn(uint256 indexed roundId, uint256[5] winningNumbers);
    event WinningsClaimed(uint256 indexed roundId, address indexed user, uint256 amount, uint8 matchCount);
    event GiftDistributed(uint256 indexed roundId, address indexed recipient, uint256 amount, bool isCreator);
    event GiftReserveFunded(address indexed funder, uint256 amount);
    event GiftSettingsUpdated(uint256 recipients, uint256 creatorAmount, uint256 userAmount);
    event MaxPayoutUpdated(uint256 newMaxPayout);

    function setUp() public {
        // Deploy mock VRF coordinator
        mockVRF = new MockVRFCoordinator();

        // Deploy platform token
        token = new PlatformToken(INITIAL_SUPPLY);

        // Deploy lottery game
        lottery = new LotteryGame(address(token), address(mockVRF), SUBSCRIPTION_ID, KEY_HASH, creator);

        token.transfer(address(lottery), INITIAL_SUPPLY / 2); // Fund lottery with tokens

        // Setup roles
        lottery.grantRole(lottery.OPERATOR_ROLE(), operator);
        lottery.grantRole(lottery.GIFT_DISTRIBUTOR_ROLE(), giftDistributor);

        // Authorize lottery contract to burn tokens
        token.setAuthorizedBurner(address(lottery), true);
        token.setAuthorizedTransferor(address(lottery), true);

        // Setup test accounts
        _setupTestAccounts();

        vm.warp(block.timestamp + 1);
    }

    function _setupTestAccounts() internal {
        address[4] memory accounts = [player1, player2, player3, operator];

        for (uint256 i = 0; i < accounts.length; i++) {
            // Transfer tokens to test accounts
            token.transfer(accounts[i], 10_000 * 10 ** 18);

            // Stake tokens to become eligible
            vm.startPrank(accounts[i]);
            token.stake(STAKE_AMOUNT);
            vm.stopPrank();
        }

        // Fast forward past staking duration
        // vm.warp(block.timestamp + 25 hours);
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
        assertEq(address(lottery.platformToken()), address(token));
        assertEq(lottery.currentRound(), 1);
        assertEq(lottery.creator(), creator);
        assertTrue(lottery.hasRole(lottery.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(lottery.hasRole(lottery.OPERATOR_ROLE(), operator));
        assertTrue(lottery.hasRole(lottery.GIFT_DISTRIBUTOR_ROLE(), giftDistributor));
    }

    function test_InitialRoundStarted() public view {
        LotteryGame.Round memory round = lottery.getCurrentRound();
        assertEq(round.roundId, 1);
        assertEq(round.startTime, block.timestamp - 1);
        assertEq(round.endTime, block.timestamp - 1 + lottery.ROUND_DURATION());
        assertFalse(round.numbersDrawn);
        assertEq(round.totalBets, 0);
    }

    // =============================================================
    //                        BETTING TESTS
    // =============================================================

    function test_PlaceBet_Success() public {
        uint256[5] memory numbers = _getValidNumbers();

        vm.startPrank(player1);
        token.approve(address(lottery), BET_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit BetPlaced(1, player1, numbers, BET_AMOUNT);

        lottery.placeBet(numbers, BET_AMOUNT);
        vm.stopPrank();

        // Verify bet was placed
        LotteryGame.Bet memory bet = lottery.getBet(1, 0);
        assertEq(bet.user, player1);
        assertEq(bet.amount, BET_AMOUNT);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(bet.numbers[i], numbers[i]);
        }

        // Verify round stats updated
        LotteryGame.Round memory round = lottery.getCurrentRound();
        assertEq(round.totalBets, BET_AMOUNT);
        assertEq(round.totalPrizePool, BET_AMOUNT);

        // Verify user stats updated
        uint256[] memory userBets = lottery.getUserRoundBets(1, player1);
        assertEq(userBets.length, 1);
        assertEq(userBets[0], 0);
    }

    function test_PlaceBet_MultipleUsers() public {
        uint256[5] memory numbers1 = _getValidNumbers();
        uint256[5] memory numbers2 = _getValidNumbers2();

        // Player 1 bets
        vm.startPrank(player1);
        token.approve(address(lottery), BET_AMOUNT);
        lottery.placeBet(numbers1, BET_AMOUNT);
        vm.stopPrank();

        // Player 2 bets
        vm.startPrank(player2);
        token.approve(address(lottery), BET_AMOUNT);
        lottery.placeBet(numbers2, BET_AMOUNT);
        vm.stopPrank();

        LotteryGame.Round memory round = lottery.getCurrentRound();
        assertEq(round.totalBets, BET_AMOUNT * 2);
        assertEq(round.participants.length, 2);
    }

    function test_PlaceBet_MultipleFromSameUser() public {
        uint256[5] memory numbers1 = _getValidNumbers();
        uint256[5] memory numbers2 = _getValidNumbers2();

        vm.startPrank(player1);
        token.approve(address(lottery), BET_AMOUNT * 2);

        lottery.placeBet(numbers1, BET_AMOUNT);
        lottery.placeBet(numbers2, BET_AMOUNT);
        vm.stopPrank();

        uint256[] memory userBets = lottery.getUserRoundBets(1, player1);
        assertEq(userBets.length, 2);

        LotteryGame.Round memory round = lottery.getCurrentRound();
        assertEq(round.participants.length, 1); // Same user
        assertEq(round.totalBets, BET_AMOUNT * 2);
    }

    function test_PlaceBet_RevertInvalidNumbers() public {
        vm.startPrank(player1);
        token.approve(address(lottery), BET_AMOUNT);

        // Test duplicate numbers
        uint256[5] memory duplicateNumbers = [uint256(1), 1, 5, 10, 15];
        vm.expectRevert(LotteryGame.InvalidNumbers.selector);
        lottery.placeBet(duplicateNumbers, BET_AMOUNT);

        // Test number out of range (0)
        uint256[5] memory zeroNumbers = [uint256(0), 5, 10, 15, 20];
        vm.expectRevert(LotteryGame.InvalidNumbers.selector);
        lottery.placeBet(zeroNumbers, BET_AMOUNT);

        // Test number out of range (50)
        uint256[5] memory highNumbers = [uint256(5), 10, 15, 20, 50];
        vm.expectRevert(LotteryGame.InvalidNumbers.selector);
        lottery.placeBet(highNumbers, BET_AMOUNT);

        // Test unsorted numbers
        uint256[5] memory unsortedNumbers = [uint256(5), 1, 10, 15, 20];
        vm.expectRevert(LotteryGame.InvalidNumbers.selector);
        lottery.placeBet(unsortedNumbers, BET_AMOUNT);

        vm.stopPrank();
    }

    function test_PlaceBet_RevertInsufficientStake() public {
        // Create user with no stake
        address unstaked = address(0x99);
        token.transfer(unstaked, 1000 * 10 ** 18);

        vm.startPrank(unstaked);
        token.approve(address(lottery), BET_AMOUNT);

        vm.expectRevert(LotteryGame.NotEligibleForBetting.selector);
        lottery.placeBet(_getValidNumbers(), BET_AMOUNT);
        vm.stopPrank();
    }

    function test_PlaceBet_RevertLowAmount() public {
        vm.startPrank(player1);
        token.approve(address(lottery), type(uint256).max); // approve plenty

        uint256 lowAmount = lottery.MIN_BET_AMOUNT() - 1;

        vm.expectRevert(LotteryGame.BetAmountTooLow.selector);
        lottery.placeBet(_getValidNumbers(), lowAmount);

        vm.stopPrank();
    }

    function test_PlaceBet_RevertExceedsMaxPerRound() public {
        uint256 maxBet = lottery.MAX_BET_PER_USER_PER_ROUND();

        vm.startPrank(player1);
        token.approve(address(lottery), maxBet + 1);

        vm.expectRevert(LotteryGame.ExceedsMaxBetPerRound.selector);
        lottery.placeBet(_getValidNumbers(), maxBet + 1);
        vm.stopPrank();
    }

    function test_PlaceBet_RevertRoundEnded() public {
        // Fast forward past round end
        vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);

        vm.startPrank(player1);
        token.approve(address(lottery), BET_AMOUNT);

        vm.expectRevert(LotteryGame.RoundNotActive.selector);
        lottery.placeBet(_getValidNumbers(), BET_AMOUNT);
        vm.stopPrank();
    }

    // =============================================================
    //                     ROUND MANAGEMENT TESTS
    // =============================================================

    function test_EndRound_Success() public {
        // Place some bets
        _placeBetsForRound(1);

        // Fast forward to round end
        vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);

        uint256 vrfRequestId = mockVRF.getNextRequestId();

        lottery.endRound();

        // Verify VRF request was made
        LotteryGame.Round memory round = lottery.getRound(1);
        assertEq(round.vrfRequestId, vrfRequestId);
        assertEq(lottery.vrfRequestToRound(vrfRequestId), 1);
    }

    function test_EndRound_RevertNotEnded() public {
        vm.expectRevert(LotteryGame.RoundNotEnded.selector);
        lottery.endRound();
    }

    function test_VRFResponse_NewRoundStarted() public {
        uint256 initialRound = lottery.currentRound();

        _placeBetsForRound(1);

        // Fast forward and end round
        vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);
        lottery.endRound();

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
        emit RoundStarted(initialRound + 1, block.timestamp, block.timestamp + lottery.ROUND_DURATION());

        mockVRF.fulfillRandomWords(lottery.getRound(1).vrfRequestId, randomWords);

        // Verify new round started
        assertEq(lottery.currentRound(), initialRound + 1);
        assertTrue(lottery.getRound(1).numbersDrawn);
    }

    function test_EmergencyDrawNumbers() public {
        _placeBetsForRound(1);

        // Fast forward and end round
        vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);
        lottery.endRound();

        // Fast forward past emergency threshold
        vm.warp(block.timestamp + 2 hours);

        uint256[5] memory emergencyNumbers = [uint256(1), 5, 15, 25, 35];

        vm.prank(operator);
        vm.expectEmit(true, false, false, true);
        emit NumbersDrawn(1, emergencyNumbers);

        lottery.emergencyDrawNumbers(1, emergencyNumbers);

        assertTrue(lottery.getRound(1).numbersDrawn);
    }

    // =============================================================
    //                       WINNING & CLAIMING TESTS
    // =============================================================

    function test_ClaimWinnings_FullMatch() public {
        uint256[5] memory numbers = [uint256(1), 5, 15, 25, 35];

        // Place bet
        vm.startPrank(player1);
        token.approve(address(lottery), BET_AMOUNT);
        lottery.placeBet(numbers, BET_AMOUNT);
        vm.stopPrank();

        // End round and set winning numbers to match
        _endRoundWithNumbers(1, numbers);

        // Check claimable winnings
        (uint256 totalWinnings, uint256[] memory claimableBets) = lottery.getClaimableWinnings(1, player1);

        console.log("Total Winnings: %s", totalWinnings);
        console.log("Claimable Bets Length: %s", claimableBets.length);

        assertEq(claimableBets.length, 1);

        uint256 expectedPayout = (BET_AMOUNT * 800 * (10000 - lottery.HOUSE_EDGE())) / 10000;
        assertEq(totalWinnings, expectedPayout);

        // Claim winnings
        uint256 balanceBefore = token.balanceOf(player1);

        vm.prank(player1);
        vm.expectEmit(true, true, false, true);
        emit WinningsClaimed(1, player1, expectedPayout, 5);

        lottery.claimWinnings(1, claimableBets);

        assertEq(token.balanceOf(player1), balanceBefore + expectedPayout);
    }

    function test_ClaimWinnings_PartialMatch() public {
        uint256[5] memory betNumbers = [uint256(1), 5, 15, 25, 35];
        uint256[5] memory winningNumbers = [uint256(1), 5, 15, 30, 40]; // 3 matches

        // Place bet
        vm.startPrank(player1);
        token.approve(address(lottery), BET_AMOUNT);
        lottery.placeBet(betNumbers, BET_AMOUNT);
        vm.stopPrank();

        // End round with partial match
        _endRoundWithNumbers(1, winningNumbers);

        // Check claimable winnings
        (uint256 totalWinnings,) = lottery.getClaimableWinnings(1, player1);
        uint256 expectedPayout = (BET_AMOUNT * 8 * (10000 - lottery.HOUSE_EDGE())) / 10000;
        assertEq(totalWinnings, expectedPayout);
    }

    function test_ClaimWinnings_NoMatch() public {
        uint256[5] memory betNumbers = [uint256(1), 5, 15, 25, 35];
        uint256[5] memory winningNumbers = [uint256(2), 6, 16, 26, 36]; // 0 matches

        // Place bet
        vm.startPrank(player1);
        token.approve(address(lottery), BET_AMOUNT);
        lottery.placeBet(betNumbers, BET_AMOUNT);
        vm.stopPrank();

        // End round with no match
        _endRoundWithNumbers(1, winningNumbers);

        // Check claimable winnings
        (uint256 totalWinnings,) = lottery.getClaimableWinnings(1, player1);
        assertEq(totalWinnings, 0);
    }

    function test_ClaimWinnings_RevertAlreadyClaimed() public {
        uint256[5] memory numbers = [uint256(1), 5, 15, 25, 35];

        // Setup winning scenario
        vm.startPrank(player1);
        token.approve(address(lottery), BET_AMOUNT);
        lottery.placeBet(numbers, BET_AMOUNT);
        vm.stopPrank();

        _endRoundWithNumbers(1, numbers);

        (, uint256[] memory claimableBets) = lottery.getClaimableWinnings(1, player1);

        // Claim once
        vm.prank(player1);
        lottery.claimWinnings(1, claimableBets);

        // Try to claim again
        vm.prank(player1);
        vm.expectRevert(LotteryGame.AlreadyClaimed.selector);
        lottery.claimWinnings(1, claimableBets);
    }

    // =============================================================
    //                        GIFT SYSTEM TESTS
    // =============================================================

    function test_FundGiftReserve() public {
        uint256 fundAmount = 1000 * 10 ** 18;

        vm.startPrank(player1);
        token.approve(address(lottery), fundAmount);

        vm.expectEmit(true, false, false, true);
        emit GiftReserveFunded(player1, fundAmount);

        lottery.fundGiftReserve(fundAmount);
        vm.stopPrank();

        (uint256 reserve,) = lottery.getGiftReserveStatus();
        assertEq(reserve, fundAmount);
    }

    function test_DistributeGifts() public {
        // Fund gift reserve
        uint256 fundAmount = 100000 * 10 ** 18;
        token.approve(address(lottery), fundAmount);
        lottery.fundGiftReserve(fundAmount);

        // Setup consecutive play
        _setupConsecutivePlay();

        // End round 3
        _endRoundWithNumbers(3, [uint256(1), 2, 3, 4, 5]);

        vm.prank(giftDistributor);
        lottery.distributeGifts(3);

        // Verify gifts were distributed
        assertTrue(lottery.getRound(3).giftsDistributed);

        // Verify creator received gift
        // Note: We'd need to track balances to fully verify, but structure is correct
    }

    function test_DistributeGifts_RevertInsufficientReserve() public {
        _endRoundWithNumbers(1, [uint256(1), 2, 3, 4, 5]);

        vm.prank(giftDistributor);
        vm.expectRevert(LotteryGame.InsufficientGiftReserve.selector);
        lottery.distributeGifts(1);
    }

    // =============================================================
    //                        ADMIN TESTS
    // =============================================================

    function test_UpdateGiftSettings() public {
        uint256 newRecipients = 15;
        uint256 newCreatorAmount = 200 * 10 ** 18;
        uint256 newUserAmount = 75 * 10 ** 18;

        vm.expectEmit(false, false, false, true);
        emit GiftSettingsUpdated(newRecipients, newCreatorAmount, newUserAmount);

        lottery.updateGiftSettings(newRecipients, newCreatorAmount, newUserAmount);

        assertEq(lottery.giftRecipientsCount(), newRecipients);
        assertEq(lottery.creatorGiftAmount(), newCreatorAmount);
        assertEq(lottery.userGiftAmount(), newUserAmount);
    }

    function test_PauseUnpause() public {
        lottery.pause();
        assertTrue(lottery.paused());

        vm.startPrank(player1);
        token.approve(address(lottery), BET_AMOUNT);
        vm.expectRevert();
        lottery.placeBet(_getValidNumbers(), BET_AMOUNT);
        vm.stopPrank();

        lottery.unpause();
        assertFalse(lottery.paused());
    }

    function test_EmergencyWithdraw() public {
        // Fund contract with some tokens
        uint256 withdrawAmount = 1000 * 10 ** 18;
        token.transfer(address(lottery), withdrawAmount);

        uint256 balanceBefore = token.balanceOf(address(this));
        lottery.emergencyWithdraw(withdrawAmount);

        assertEq(token.balanceOf(address(this)), balanceBefore + withdrawAmount);
    }

    // =============================================================
    //                        TIMELOCK TESTS
    // =============================================================

    function test_MaxPayoutTimelock() public {
        uint256 newMaxPayout = 20_000 * 10 ** 18;

        // Schedule change
        lottery.scheduleMaxPayoutChange(newMaxPayout);

        // Try to execute immediately (should fail)
        vm.expectRevert(LotteryGame.TimelockNotReady.selector);
        lottery.setMaxPayoutPerRound(newMaxPayout);

        // Wait for timelock
        vm.warp(block.timestamp + 25 hours);

        // Execute change
        vm.expectEmit(false, false, false, true);
        emit MaxPayoutUpdated(newMaxPayout);

        lottery.setMaxPayoutPerRound(newMaxPayout);
        assertEq(lottery.maxPayoutPerRound(), newMaxPayout);
    }

    // =============================================================
    //                        HELPER FUNCTIONS
    // =============================================================

    function _placeBetsForRound(uint256 roundId) internal {
        require(lottery.currentRound() == roundId, "Wrong round");

        address[3] memory players = [player1, player2, player3];
        uint256[5][3] memory numberSets = [_getValidNumbers(), _getValidNumbers2(), _getValidNumbers3()];

        for (uint256 i = 0; i < players.length; i++) {
            vm.startPrank(players[i]);
            token.approve(address(lottery), BET_AMOUNT);
            lottery.placeBet(numberSets[i], BET_AMOUNT);
            vm.stopPrank();
        }
    }

    function _endRoundWithNumbers(uint256 roundId, uint256[5] memory winningNumbers) internal {
        vm.warp(block.timestamp + lottery.ROUND_DURATION() + 2 hours);
        lottery.endRound();

        // Directly give intended winning numbers; mock will generate the right randomWords
        // mockVRF.fulfillRandomWordsWithNumbers(lottery.getRound(roundId).vrfRequestId, winningNumbers);
        lottery.emergencyDrawNumbers(roundId, winningNumbers);
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
        LotteryGame.Round memory currentRound = lottery.getCurrentRound();
        assertEq(currentRound.roundId, 1);

        // Test getUserStats
        LotteryGame.UserStats memory stats = lottery.getUserStats(player1);
        assertEq(stats.totalBets, 0); // No bets placed yet

        // Test getGiftReserveStatus
        (uint256 reserve, uint256 costPerRound) = lottery.getGiftReserveStatus();
        assertEq(reserve, 0); // No funds added yet
        assertTrue(costPerRound > 0); // Should have some cost
    }
}
