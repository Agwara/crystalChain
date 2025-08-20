// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PlatformToken} from "./PlatformToken.sol";

/**
 * @title LotteryGame
 * @author Agwara Nnaemeka
 * @notice A decentralized lottery game contract that allows users to place bets, participate in rounds, and receive gifts.
 * @dev This contract manages the lottery rounds, user bets, and prize distributions.
 * It uses PlatformToken for token transfers and staking benefits.
 * The game operates in 5-minute rounds with specific rules for betting and gift distribution.
 */
contract LotteryGame is Ownable, ReentrancyGuard {
    PlatformToken public immutable platformToken;

    // Game Configuration
    uint256 public constant ROUND_DURATION = 5 minutes;
    uint256 public constant NUMBERS_COUNT = 5;
    uint256 public constant MAX_NUMBER = 49;
    uint256 public constant BET_AMOUNT = 10 * 10 ** 18; // 10 tokens

    // Gift Configuration
    uint256 public constant GIFT_WINNERS_COUNT = 10;
    uint256 public constant GIFT_COOLDOWN = 7 days; // Users can't receive gifts for 7 days
    uint256 public constant CREATOR_GIFT_AMOUNT = 100 * 10 ** 18;
    uint256 public constant WINNER_GIFT_AMOUNT = 50 * 10 ** 18;

    // Current Round Data
    struct Round {
        uint256 roundId;
        uint256 startTime;
        uint256 endTime;
        uint256[5] winningNumbers;
        bool numbersDrawn;
        address[] participants;
        mapping(address => uint256[5]) predictions;
        uint256 totalPrizePool;
    }

    // Gift Tracking
    mapping(address => uint256) public lastGiftTime;
    mapping(address => uint256) public consecutiveRounds;
    mapping(address => bool) public hasPlayedInCurrentRound;

    uint256 public currentRoundId;
    mapping(uint256 => Round) public rounds;

    address public creator;

    // Events
    event RoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime);
    event BetPlaced(address indexed player, uint256 indexed roundId, uint256[5] numbers);
    event NumbersDrawn(uint256 indexed roundId, uint256[5] winningNumbers);
    event PrizeDistributed(uint256 indexed roundId, address indexed winner, uint256 amount);
    event GiftDistributed(address indexed recipient, uint256 amount, bool isCreator);

    constructor(address _platformToken, address _creator) Ownable(msg.sender) {
        platformToken = PlatformToken(_platformToken);
        creator = _creator;
        _startNewRound();
    }

    /**
     * @notice Place a bet for the current round
     * @param numbers Array of 5 numbers (1-49) to predict
     */
    function placeBet(uint256[5] memory numbers) external nonReentrant {
        Round storage round = rounds[currentRoundId];

        // Validation
        require(block.timestamp < round.endTime, "Round ended");
        require(platformToken.isEligibleForBenefits(msg.sender), "Must stake tokens first");
        require(!hasPlayedInCurrentRound[msg.sender], "Already played this round");

        // Validate numbers
        for (uint256 i = 0; i < 5; i++) {
            require(numbers[i] >= 1 && numbers[i] <= MAX_NUMBER, "Invalid number");
        }

        // Transfer bet amount
        platformToken.transferFrom(msg.sender, address(this), BET_AMOUNT);

        // Record bet
        round.participants.push(msg.sender);
        round.predictions[msg.sender] = numbers;
        round.totalPrizePool += BET_AMOUNT;
        hasPlayedInCurrentRound[msg.sender] = true;

        // Update consecutive rounds counter
        consecutiveRounds[msg.sender]++;

        emit BetPlaced(msg.sender, currentRoundId, numbers);
    }

    /**
     * @notice End current round and start new one (called by automation or admin)
     */
    function endRoundAndStartNew() external onlyOwner {
        Round storage round = rounds[currentRoundId];
        require(block.timestamp >= round.endTime, "Round not finished");
        require(!round.numbersDrawn, "Numbers already drawn");

        // Generate random numbers (simplified - use Chainlink VRF in production)
        uint256[5] memory winningNumbers = _generateRandomNumbers();
        round.winningNumbers = winningNumbers;
        round.numbersDrawn = true;

        emit NumbersDrawn(currentRoundId, winningNumbers);

        // Distribute prizes
        _distributePrizes(currentRoundId);

        // Distribute gifts
        _distributeGifts();

        // Reset consecutive counters for non-participants
        _resetNonParticipants();

        // Start new round
        _startNewRound();
    }

    /**
     * @notice Start a new round
     */
    function _startNewRound() internal {
        currentRoundId++;
        Round storage newRound = rounds[currentRoundId];
        newRound.roundId = currentRoundId;
        newRound.startTime = block.timestamp;
        newRound.endTime = block.timestamp + ROUND_DURATION;

        // Reset current round participation
        // Note: We'll need to track participants to reset this mapping

        emit RoundStarted(currentRoundId, newRound.startTime, newRound.endTime);
    }

    /**
     * @notice Distribute gifts to creator and random winners
     */
    function _distributeGifts() internal {
        // Gift creator (always eligible)
        if (consecutiveRounds[creator] > 0) {
            platformToken.transfer(creator, CREATOR_GIFT_AMOUNT);
            emit GiftDistributed(creator, CREATOR_GIFT_AMOUNT, true);
        }

        // Select random winners from eligible participants
        address[] memory eligibleWinners = _getEligibleGiftRecipients();

        uint256 winnersToGift =
            eligibleWinners.length < GIFT_WINNERS_COUNT ? eligibleWinners.length : GIFT_WINNERS_COUNT;

        // Distribute gifts to random winners (simplified selection)
        for (uint256 i = 0; i < winnersToGift; i++) {
            uint256 randomIndex = uint256(keccak256(abi.encode(block.timestamp, i))) % eligibleWinners.length;
            address winner = eligibleWinners[randomIndex];

            platformToken.transfer(winner, WINNER_GIFT_AMOUNT);
            lastGiftTime[winner] = block.timestamp;
            emit GiftDistributed(winner, WINNER_GIFT_AMOUNT, false);

            // Remove winner from array to avoid duplicates
            eligibleWinners[randomIndex] = eligibleWinners[eligibleWinners.length - 1];
            // Note: This is simplified - proper implementation needs array manipulation
        }
    }

    /**
     * @notice Get users eligible for gifts
     */
    function _getEligibleGiftRecipients() internal view returns (address[] memory) {
        Round storage round = rounds[currentRoundId];
        address[] memory eligible = new address[](round.participants.length);
        uint256 count = 0;

        for (uint256 i = 0; i < round.participants.length; i++) {
            address participant = round.participants[i];

            // Must be staking, playing consecutively, and not recently gifted
            if (
                platformToken.stakedBalance(participant) >= platformToken.MIN_STAKE_AMOUNT()
                    && consecutiveRounds[participant] >= 2 // At least 2 consecutive rounds
                    && block.timestamp >= lastGiftTime[participant] + GIFT_COOLDOWN && participant != creator
            ) {
                eligible[count] = participant;
                count++;
            }
        }

        // Resize array
        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = eligible[i];
        }

        return result;
    }

    /**
     * @notice Reset consecutive rounds for users who didn't participate
     */
    function _resetNonParticipants() internal {
        // This would need a more sophisticated approach in production
        // Maybe maintain a list of all users who have ever played
    }

    /**
     * @notice Generate random numbers (placeholder - use Chainlink VRF)
     */
    function _generateRandomNumbers() internal view returns (uint256[5] memory) {
        uint256[5] memory numbers;
        for (uint256 i = 0; i < 5; i++) {
            numbers[i] = (uint256(keccak256(abi.encode(block.timestamp, block.prevrandao, i))) % MAX_NUMBER) + 1;
        }
        return numbers;
    }

    /**
     * @notice Distribute prizes based on matching numbers
     */
    function _distributePrizes(uint256 roundId) internal view {
        // Round storage round = rounds[roundId];
        // Implementation for prize distribution based on number matches
        // This would check each participant's predictions against winning numbers
    }

    // View functions
    function getCurrentRound()
        external
        view
        returns (uint256 roundId, uint256 startTime, uint256 endTime, uint256 totalPrizePool)
    {
        Round storage round = rounds[currentRoundId];
        return (round.roundId, round.startTime, round.endTime, round.totalPrizePool);
    }

    function getUserPrediction(uint256 roundId, address user) external view returns (uint256[5] memory) {
        return rounds[roundId].predictions[user];
    }

    function isEligibleForGifts(address user) external view returns (bool) {
        return platformToken.stakedBalance(user) >= platformToken.MIN_STAKE_AMOUNT() && consecutiveRounds[user] >= 2
            && block.timestamp >= lastGiftTime[user] + GIFT_COOLDOWN;
    }
}
