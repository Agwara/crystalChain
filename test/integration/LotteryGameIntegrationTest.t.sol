// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/LotteryGame.sol";
import "../../src/PlatformToken.sol";
import "../mocks/MockVRFCoordinator.sol";

/**
 * @title LotteryGameIntegrationTest
 * @dev Integration tests focusing on complex scenarios and edge cases
 */
contract LotteryGameIntegrationTest is Test {
    LotteryGame public lottery;
    PlatformToken public token;
    MockVRFCoordinator public mockVRF;

    address public creator = address(0x1);
    address[] public players;

    uint256 public constant INITIAL_SUPPLY = 10_000_000 * 10 ** 18;
    uint256 public constant STAKE_AMOUNT = 100 * 10 ** 18;

    event RoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime);
    event NumbersDrawn(uint256 indexed roundId, uint256[5] winningNumbers);
    event WinningsClaimed(uint256 indexed roundId, address indexed user, uint256 amount, uint8 matchCount);

    function setUp() public {
        mockVRF = new MockVRFCoordinator();
        token = new PlatformToken(INITIAL_SUPPLY);

        lottery = new LotteryGame(
            address(token),
            address(mockVRF),
            1, // subscription ID
            0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
            creator
        );

        token.setAuthorizedBurner(address(lottery), true);
        token.setAuthorizedTransferor(address(lottery), true);

        // Create 20 test players
        for (uint256 i = 0; i < 20; i++) {
            address player = address(uint160(0x100 + i));
            players.push(player);

            token.transfer(player, 50_000 * 10 ** 18);

            vm.startPrank(player);
            token.stake(STAKE_AMOUNT);
            vm.stopPrank();
        }

        // vm.warp(block.timestamp + 1 hours); // Past staking duration
    }

    // =============================================================
    //                    MULTIPLE ROUNDS SCENARIO
    // =============================================================

    function test_MultipleRounds_CompleteFlow() public {
        uint256 startingRound = lottery.currentRound();

        // Run 5 complete rounds
        for (uint256 round = 0; round < 5; round++) {
            uint256 currentRoundId = startingRound + round;

            // Multiple players place multiple bets
            _placeVariousBets();

            // Fast forward to round end
            vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);

            // End round and simulate VRF
            lottery.endRound();
            _simulateVRFResponse(currentRoundId);

            // Verify new round started (except for last iteration)
            if (round < 4) {
                assertEq(lottery.currentRound(), currentRoundId + 1);
            }
        }

        // Verify all rounds completed
        for (uint256 i = 0; i < 5; i++) {
            assertTrue(lottery.getRound(startingRound + i).numbersDrawn);
        }
    }

    function test_ConsecutivePlay_GiftEligibility() public {
        address player = players[0];

        // Play 3 consecutive rounds
        for (uint256 round = 1; round <= 3; round++) {
            _placeSingleBet(player, round, _generateNumbers(round));

            if (round < 3) {
                vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);
                lottery.endRound();
                _simulateVRFResponse(round);
            }
        }

        // Check eligibility
        LotteryGame.UserStats memory stats = lottery.getUserStats(player);
        assertTrue(stats.isEligibleForGift);
        assertEq(stats.consecutiveRounds, 3);
    }

    function test_LargeScaleBetting() public {
        uint256 roundId = lottery.currentRound();
        uint256 totalBets = 0;
        uint256 totalAmount = 0;

        // 100 bets from various players
        for (uint256 i = 0; i < 100; i++) {
            address player = players[i % players.length];
            uint256 betAmount = (i % 10 + 1) * 10 ** 18; // 1-10 tokens
            uint256[5] memory numbers = _generateNumbers(i);

            vm.startPrank(player);
            token.approve(address(lottery), betAmount);
            lottery.placeBet(numbers, betAmount);
            vm.stopPrank();

            totalBets++;
            totalAmount += betAmount;
        }

        LotteryGame.Round memory round = lottery.getRound(roundId);
        assertEq(round.totalBets, totalAmount);

        // End round and verify all bets processed
        vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);
        lottery.endRound();
        _simulateVRFResponse(roundId);

        // Check that match calculations worked for all bets
        for (uint256 i = 0; i < 10; i++) {
            // Check first 10 bets
            LotteryGame.Bet memory bet = lottery.getBet(roundId, i);
            assertTrue(bet.matchCount <= 5); // Valid match count
        }
    }

    // =============================================================
    //                      PAYOUT SCENARIOS
    // =============================================================

    function test_MaximumPayout_Scenario() public {
        uint256 roundId = lottery.currentRound();

        // Create scenario with maximum possible winnings
        uint256 maxBetAmount = 1000 * 10 ** 18; // Max bet per user
        uint256[5] memory winningNumbers = [uint256(1), 5, 15, 25, 35];

        // 5 players place max bets with winning numbers
        for (uint256 i = 0; i < 5; i++) {
            address player = players[i];

            vm.startPrank(player);
            token.approve(address(lottery), maxBetAmount);
            lottery.placeBet(winningNumbers, maxBetAmount);
            vm.stopPrank();
        }

        // End round with those exact numbers
        vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);
        lottery.endRound();
        _simulateVRFResponseWithNumbers(roundId, winningNumbers);

        // Calculate expected total payout
        uint256 individualPayout = (maxBetAmount * 800 * (10000 - lottery.HOUSE_EDGE())) / 10000;
        uint256 totalExpectedPayout = individualPayout * 5;

        // Verify total payout calculation
        uint256 actualTotalPayout = 0;
        for (uint256 i = 0; i < 5; i++) {
            (uint256 winnings,) = lottery.getClaimableWinnings(roundId, players[i]);
            actualTotalPayout += winnings;
        }

        assertEq(actualTotalPayout, totalExpectedPayout);

        // Check if it exceeds maximum (it should)
        assertTrue(totalExpectedPayout > lottery.maxPayoutPerRound());
    }

    function test_PayoutDistribution_AllMatchTypes() public {
        uint256 roundId = lottery.currentRound();
        uint256[5] memory winningNumbers = [uint256(7), 14, 21, 28, 35];

        // Create bets with different match counts
        address[5] memory testPlayers = [players[0], players[1], players[2], players[3], players[4]];
        uint256[5][5] memory betNumbers = [
            [uint256(7), 14, 21, 28, 35], // 5 matches
            [uint256(7), 14, 21, 28, 36], // 4 matches
            [uint256(7), 14, 21, 29, 36], // 3 matches
            [uint256(7), 14, 22, 29, 36], // 2 matches
            [uint256(8), 15, 22, 29, 36] // 0 matches
        ];

        uint256 betAmount = 50 * 10 ** 18;

        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(testPlayers[i]);
            token.approve(address(lottery), betAmount);
            lottery.placeBet(betNumbers[i], betAmount);
            vm.stopPrank();
        }

        // End round with winning numbers
        vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);
        lottery.endRound();
        _simulateVRFResponseWithNumbers(roundId, winningNumbers);

        // Verify match counts and payouts
        uint256[5] memory expectedPayouts = [
            (betAmount * 800 * (10000 - lottery.HOUSE_EDGE())) / 10000, // 5 matches
            (betAmount * 80 * (10000 - lottery.HOUSE_EDGE())) / 10000, // 4 matches
            (betAmount * 8 * (10000 - lottery.HOUSE_EDGE())) / 10000, // 3 matches
            (betAmount * 2 * (10000 - lottery.HOUSE_EDGE())) / 10000, // 2 matches
            0 // 0 matches
        ];

        for (uint256 i = 0; i < 5; i++) {
            (uint256 winnings,) = lottery.getClaimableWinnings(roundId, testPlayers[i]);
            assertEq(winnings, expectedPayouts[i]);

            LotteryGame.Bet memory bet = lottery.getBet(roundId, i);
            assertEq(bet.matchCount, i == 4 ? 0 : (5 - i));
        }
    }

    // =============================================================
    //                      GIFT SYSTEM INTEGRATION
    // =============================================================

    function test_GiftSystem_CompleteFlow() public {
        // Fund gift reserve
        uint256 reserveAmount = 50_000 * 10 ** 18;
        token.approve(address(lottery), reserveAmount);
        lottery.fundGiftReserve(reserveAmount);

        // Setup multiple players with consecutive play
        address[10] memory eligiblePlayers;
        for (uint256 i = 0; i < 10; i++) {
            eligiblePlayers[i] = players[i];
        }

        // Run 3 consecutive rounds for all players
        for (uint256 round = 1; round <= 3; round++) {
            for (uint256 p = 0; p < 10; p++) {
                _placeSingleBet(eligiblePlayers[p], round, _generateNumbers(p + round));
            }

            vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);
            lottery.endRound();
            _simulateVRFResponse(round);
        }

        // Distribute gifts for round 3
        uint256 creatorBalanceBefore = token.balanceOf(creator);

        vm.prank(address(this)); // Has GIFT_DISTRIBUTOR_ROLE
        lottery.distributeGifts(3);

        // Verify creator received gift
        assertEq(token.balanceOf(creator), creatorBalanceBefore + lottery.creatorGiftAmount());

        // Verify gift reserve decreased
        (uint256 newReserve,) = lottery.getGiftReserveStatus();
        assertTrue(newReserve < reserveAmount);
    }

    function test_GiftCooldown_Enforcement() public {
        // Setup and distribute gifts once
        uint256 reserveAmount = 100_000 * 10 ** 18;
        token.approve(address(lottery), reserveAmount);
        lottery.fundGiftReserve(reserveAmount);

        address player = players[0];

        // First round of consecutive play
        for (uint256 round = 1; round <= 3; round++) {
            _placeSingleBet(player, round, _generateNumbers(round));
            vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);
            lottery.endRound();
            _simulateVRFResponse(round);
        }

        vm.prank(address(this));
        lottery.distributeGifts(3);

        // Continue playing and try to get gifts too soon
        for (uint256 round = 4; round <= 6; round++) {
            _placeSingleBet(player, round, _generateNumbers(round));
            vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);
            lottery.endRound();
            _simulateVRFResponse(round);
        }

        LotteryGame.UserStats memory stats = lottery.getUserStats(player);
        assertEq(stats.lastGiftRound, 3); // Should still be round 3

        // Fast forward past cooldown and verify eligibility
        vm.warp(block.timestamp + lottery.GIFT_COOLDOWN());
        // Player would need to play again to become eligible
    }

    // =============================================================
    //                      STRESS TESTS
    // =============================================================

    function test_MaxBetsPerRound() public {
        uint256 roundId = lottery.currentRound();
        uint256 maxAmount = lottery.MAX_BET_PER_USER_PER_ROUND();

        // Each player places maximum allowed bet
        for (uint256 i = 0; i < 10; i++) {
            address player = players[i];

            vm.startPrank(player);
            token.approve(address(lottery), maxAmount);
            lottery.placeBet(_generateNumbers(i), maxAmount);
            vm.stopPrank();
        }

        LotteryGame.Round memory round = lottery.getRound(roundId);
        assertEq(round.totalBets, maxAmount * 10);
        assertEq(round.participants.length, 10);
    }

    function test_RandomNumberGeneration_Uniqueness() public {
        uint256 roundId = lottery.currentRound();

        _placeSingleBet(players[0], roundId, _generateNumbers(1));

        vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);
        lottery.endRound();
        _simulateVRFResponse(roundId);

        LotteryGame.Round memory round = lottery.getRound(roundId);
        uint256[5] memory numbers = round.winningNumbers;

        // Verify all numbers are unique and in valid range
        for (uint256 i = 0; i < 5; i++) {
            assertTrue(numbers[i] >= 1 && numbers[i] <= 49);

            for (uint256 j = i + 1; j < 5; j++) {
                assertTrue(numbers[i] != numbers[j]);
            }
        }

        // Verify numbers are sorted
        for (uint256 i = 0; i < 4; i++) {
            assertTrue(numbers[i] < numbers[i + 1]);
        }
    }

    // =============================================================
    //                      ERROR SCENARIOS
    // =============================================================

    function test_VRFFailure_EmergencyDraw() public {
        uint256 roundId = lottery.currentRound();

        _placeSingleBet(players[0], roundId, _generateNumbers(1));

        // End round but don't fulfill VRF
        vm.warp(block.timestamp + lottery.ROUND_DURATION() + 1);
        lottery.endRound();

        // Wait past emergency threshold
        vm.warp(block.timestamp + 2 hours);

        // Emergency draw should work
        uint256[5] memory emergencyNumbers = [uint256(3), 7, 15, 22, 41];

        vm.prank(address(this)); // Has OPERATOR_ROLE
        lottery.emergencyDrawNumbers(roundId, emergencyNumbers);

        LotteryGame.Round memory round = lottery.getRound(roundId);
        assertTrue(round.numbersDrawn);

        for (uint256 i = 0; i < 5; i++) {
            assertEq(round.winningNumbers[i], emergencyNumbers[i]);
        }
    }

    function test_TokenInteraction_StakeRequirement() public {
        address newPlayer = address(0x999);
        token.transfer(newPlayer, 10_000 * 10 ** 18);

        // Try to bet without staking (should fail)
        vm.startPrank(newPlayer);
        token.approve(address(lottery), 10 * 10 ** 18);
        vm.expectRevert(LotteryGame.NotEligibleForBetting.selector);
        lottery.placeBet(_generateNumbers(1), 10 * 10 ** 18);
        vm.stopPrank();

        // Stake and try again (should work)
        vm.startPrank(newPlayer);
        token.stake(token.MIN_STAKE_AMOUNT());
        vm.warp(block.timestamp + 25 hours);

        token.approve(address(lottery), 10 * 10 ** 18);
        lottery.placeBet(_generateNumbers(1), 10 * 10 ** 18);
        vm.stopPrank();

        // Should succeed this time
        uint256[] memory userBets = lottery.getUserRoundBets(lottery.currentRound(), newPlayer);
        assertEq(userBets.length, 1);
    }

    // =============================================================
    //                      HELPER FUNCTIONS
    // =============================================================

    function _placeVariousBets() internal {
        // 10 random players place 1-3 bets each
        for (uint256 i = 0; i < 10; i++) {
            address player = players[i];
            uint256 numBets = (i % 3) + 1;

            for (uint256 j = 0; j < numBets; j++) {
                uint256 betAmount = ((i + j) % 10 + 1) * 10 ** 18;
                uint256[5] memory numbers = _generateNumbers(i * 10 + j);

                vm.startPrank(player);
                token.approve(address(lottery), betAmount);
                lottery.placeBet(numbers, betAmount);
                vm.stopPrank();
            }
        }
    }

    function _placeSingleBet(address player, uint256 roundId, uint256[5] memory numbers) internal {
        require(lottery.currentRound() == roundId, "Wrong round for bet");

        uint256 betAmount = 20 * 10 ** 18;

        vm.startPrank(player);
        token.approve(address(lottery), betAmount);
        lottery.placeBet(numbers, betAmount);
        vm.stopPrank();
    }

    function _generateNumbers(uint256 seed) internal pure returns (uint256[5] memory) {
        uint256[5] memory numbers;
        bool[50] memory used; // 1-49 plus index 0

        for (uint256 i = 0; i < 5; i++) {
            uint256 num;
            do {
                num = (uint256(keccak256(abi.encode(seed, i))) % 49) + 1;
                seed = uint256(keccak256(abi.encode(seed)));
            } while (used[num]);

            used[num] = true;
            numbers[i] = num;
        }

        // Sort numbers
        for (uint256 i = 0; i < 4; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                if (numbers[i] > numbers[j]) {
                    uint256 temp = numbers[i];
                    numbers[i] = numbers[j];
                    numbers[j] = temp;
                }
            }
        }

        return numbers;
    }

    function _simulateVRFResponse(uint256 roundId) internal {
        uint256[] memory randomWords = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            randomWords[i] = uint256(keccak256(abi.encode(block.timestamp, roundId, i)));
        }

        LotteryGame.Round memory round = lottery.getRound(roundId);
        mockVRF.fulfillRandomWords(round.vrfRequestId, randomWords);
    }

    function _simulateVRFResponseWithNumbers(uint256 roundId, uint256[5] memory specificNumbers) internal {
        LotteryGame.Round memory round = lottery.getRound(roundId);
        mockVRF.fulfillRandomWordsWithNumbers(round.vrfRequestId, specificNumbers);
    }
}
