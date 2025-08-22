// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./VRFConsumer.sol";

interface IPlatformToken is IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function burnFrom(address from, uint256 amount) external;
    function stakedBalance(address user) external view returns (uint256);
    function isEligibleForBenefits(address user) external view returns (bool);
    function getStakingWeight(address user) external view returns (uint256);
    function MIN_STAKE_AMOUNT() external view returns (uint256);
}

/**
 * @title LotteryGame
 * @author Agwara Nnaemeka
 * @dev Decentralized lottery game with 5-number prediction (1-49)
 * @notice Users stake tokens to participate, system gifts tokens to creator and winners
 */
contract LotteryGame is VRFConsumer, ReentrancyGuard, AccessControl, Pausable {
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    /// @notice Numbers range from 1 to MAX_NUMBER
    uint256 public constant MAX_NUMBER = 49;

    /// @notice Number of numbers to draw
    uint256 public constant NUMBERS_COUNT = 5;

    /// @notice Round duration (5 minutes)
    uint256 public constant ROUND_DURATION = 5 minutes;

    /// @notice Minimum bet amount
    uint256 public constant MIN_BET_AMOUNT = 1 * 10 ** 18; // 1 token

    /// @notice Maximum bet amount per user per round
    uint256 public constant MAX_BET_PER_USER_PER_ROUND = 1000 * 10 ** 18; // 1000 tokens

    /// @notice Gift cooldown period (24 hours)
    uint256 public constant GIFT_COOLDOWN = 24 hours;

    /// @notice Consecutive play requirement for gifts (3 rounds)
    uint256 public constant CONSECUTIVE_PLAY_REQUIREMENT = 3;

    /// @notice Number of random words needed
    uint32 private constant NUM_WORDS = 5;

    /// @notice House edge in basis points (5%)
    uint256 public constant HOUSE_EDGE = 500;

    /// @notice Role identifiers
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant GIFT_DISTRIBUTOR_ROLE = keccak256("GIFT_DISTRIBUTOR_ROLE");

    // =============================================================
    //                            STORAGE
    // =============================================================

    /// @notice Platform token contract
    IPlatformToken public immutable platformToken;

    /// @notice Current round number
    uint256 public currentRound;

    /// @notice Number of gift recipients per round (excluding creator)
    uint256 public giftRecipientsCount = 10;

    /// @notice Creator gift amount per round
    uint256 public creatorGiftAmount = 100 * 10 ** 18; // 100 tokens

    /// @notice Regular user gift amount per round
    uint256 public userGiftAmount = 50 * 10 ** 18; // 50 tokens

    /// @notice Platform creator address
    address public immutable creator;

    /// @notice Gift reserve for funding gifts
    uint256 public giftReserve;

    /// @notice Maximum payout per round
    uint256 public maxPayoutPerRound = 10_000 * 10 ** 18; // 10k tokens

    /// @notice Timelock storage for critical operations
    mapping(bytes32 => uint256) public timelocks;

    // Round structure
    struct Round {
        uint256 roundId;
        uint256 startTime;
        uint256 endTime;
        uint256[NUMBERS_COUNT] winningNumbers;
        bool numbersDrawn;
        uint256 totalBets;
        uint256 totalPrizePool;
        address[] participants;
        bool giftsDistributed;
        uint256 vrfRequestId;
    }

    // Bet structure
    struct Bet {
        address user;
        uint256[NUMBERS_COUNT] numbers;
        uint256 amount;
        uint256 timestamp;
        uint8 matchCount;
        bool claimed;
    }

    // User tracking for consecutive play and gifts
    struct UserStats {
        uint256 lastGiftRound;
        uint256 consecutiveRounds;
        uint256 totalBets;
        uint256 totalWinnings;
        bool isEligibleForGift;
    }

    // =============================================================
    //                           MAPPINGS
    // =============================================================

    /// @notice Round information
    mapping(uint256 => Round) public rounds;

    /// @notice Bets for each round
    mapping(uint256 => Bet[]) public roundBets;

    /// @notice User bets in specific round
    mapping(uint256 => mapping(address => uint256[])) public userRoundBets;

    /// @notice Total bet amount per user per round
    mapping(uint256 => mapping(address => uint256)) public userRoundBetAmount;

    /// @notice User statistics
    mapping(address => UserStats) public userStats;

    /// @notice VRF request ID to round mapping
    mapping(uint256 => uint256) public vrfRequestToRound;

    /// @notice Users who participated in each round
    mapping(uint256 => mapping(address => bool)) public roundParticipants;

    /// @notice Last round a user participated in
    mapping(address => uint256) public lastParticipatedRound;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event RoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime);
    event BetPlaced(uint256 indexed roundId, address indexed user, uint256[NUMBERS_COUNT] numbers, uint256 amount);
    event NumbersDrawn(uint256 indexed roundId, uint256[NUMBERS_COUNT] winningNumbers);
    event WinningsClaimed(uint256 indexed roundId, address indexed user, uint256 amount, uint8 matchCount);
    event GiftDistributed(uint256 indexed roundId, address indexed recipient, uint256 amount, bool isCreator);
    event GiftSettingsUpdated(uint256 recipientsCount, uint256 creatorAmount, uint256 userAmount);
    event GiftReserveFunded(address indexed funder, uint256 amount);
    event MaxPayoutUpdated(uint256 newMaxPayout);
    event OperationScheduled(bytes32 indexed operationId, uint256 executeTime);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidNumbers();
    error BetAmountTooLow();
    error BetAmountTooHigh();
    error ExceedsMaxBetPerRound();
    error RoundNotActive();
    error RoundNotEnded();
    error NumbersNotDrawn();
    error NotEligibleForBetting();
    error NoWinnings();
    error AlreadyClaimed();
    error GiftsAlreadyDistributed();
    error InvalidRound();
    error InsufficientGiftReserve();
    error PayoutExceedsMaximum();
    error TimelockNotReady();
    error OperationNotScheduled();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(
        address _platformToken,
        address _vrfCoordinator,
        uint64 _subscriptionId,
        bytes32 _keyHash,
        address _creator
    ) VRFConsumer(_vrfCoordinator, _subscriptionId, _keyHash) {
        platformToken = IPlatformToken(_platformToken);
        creator = _creator;

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(GIFT_DISTRIBUTOR_ROLE, msg.sender);

        // Start first round
        _startNewRound();
    }

    // =============================================================
    //                        BETTING FUNCTIONS
    // =============================================================

    /**
     * @notice Place a bet on current round
     * @param numbers Array of 5 numbers (1-49)
     * @param amount Bet amount in tokens
     */
    function placeBet(uint256[NUMBERS_COUNT] calldata numbers, uint256 amount) external nonReentrant whenNotPaused {
        Round storage round = rounds[currentRound];

        if (block.timestamp >= round.endTime) revert RoundNotActive();
        if (amount < MIN_BET_AMOUNT) revert BetAmountTooLow();
        if (platformToken.getStakingWeight(msg.sender) < platformToken.MIN_STAKE_AMOUNT()) {
            revert NotEligibleForBetting();
        }

        // Check max bet per user per round
        if (userRoundBetAmount[currentRound][msg.sender] + amount > MAX_BET_PER_USER_PER_ROUND) {
            revert ExceedsMaxBetPerRound();
        }

        // Validate numbers (1-49, no duplicates, sorted)
        _validateNumbers(numbers);

        // Transfer bet amount from user
        platformToken.transferFrom(msg.sender, address(this), amount);

        // Create bet
        Bet memory newBet = Bet({
            user: msg.sender,
            numbers: numbers,
            amount: amount,
            timestamp: block.timestamp,
            matchCount: 0,
            claimed: false
        });

        // Store bet
        uint256 betIndex = roundBets[currentRound].length;
        roundBets[currentRound].push(newBet);
        userRoundBets[currentRound][msg.sender].push(betIndex);
        userRoundBetAmount[currentRound][msg.sender] += amount;

        // Update round stats
        round.totalBets += amount;
        round.totalPrizePool += amount;

        // Track participation
        if (!roundParticipants[currentRound][msg.sender]) {
            roundParticipants[currentRound][msg.sender] = true;
            round.participants.push(msg.sender);

            // Update user consecutive rounds
            UserStats storage stats = userStats[msg.sender];

            if (lastParticipatedRound[msg.sender] == currentRound - 1) {
                stats.consecutiveRounds++;
            } else if (lastParticipatedRound[msg.sender] != currentRound) {
                stats.consecutiveRounds = 1;
            }

            lastParticipatedRound[msg.sender] = currentRound;
            stats.isEligibleForGift = stats.consecutiveRounds >= CONSECUTIVE_PLAY_REQUIREMENT;
        }

        userStats[msg.sender].totalBets += amount;

        emit BetPlaced(currentRound, msg.sender, numbers, amount);

        // Auto-end round if time is up
        if (block.timestamp >= round.endTime && !round.numbersDrawn) {
            _endRound();
        }
    }

    /**
     * @notice Get user's bets for a specific round
     * @param roundId Round to check
     * @param user User address
     * @return Array of bet indices
     */
    function getUserRoundBets(uint256 roundId, address user) external view returns (uint256[] memory) {
        return userRoundBets[roundId][user];
    }

    /**
     * @notice Get bet details
     * @param roundId Round number
     * @param betIndex Index of bet in round
     */
    function getBet(uint256 roundId, uint256 betIndex) external view returns (Bet memory) {
        return roundBets[roundId][betIndex];
    }

    // =============================================================
    //                        ROUND MANAGEMENT
    // =============================================================

    /**
     * @notice End current round and request random numbers
     */
    function endRound() external {
        Round storage round = rounds[currentRound];
        if (block.timestamp < round.endTime) revert RoundNotEnded();
        if (round.numbersDrawn) revert InvalidRound();

        _endRound();
    }

    /**
     * @notice Internal function to end round and request VRF
     */
    function _endRound() internal {
        Round storage round = rounds[currentRound];

        // Request random numbers from Chainlink VRF
        uint256 requestId = _requestRandomWords(NUM_WORDS);

        round.vrfRequestId = requestId;
        vrfRequestToRound[requestId] = currentRound;
    }

    /**
     * @notice Handle random words from VRF
     * @dev Overrides VRFConsumer's _handleRandomWords function
     */
    function _handleRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 roundId = vrfRequestToRound[requestId];
        Round storage round = rounds[roundId];

        // Generate 5 unique numbers from 1-49
        uint256[NUMBERS_COUNT] memory winningNumbers = _generateWinningNumbers(randomWords);
        round.winningNumbers = winningNumbers;
        round.numbersDrawn = true;

        // Calculate match counts for all bets
        _calculateMatches(roundId);

        emit NumbersDrawn(roundId, winningNumbers);

        // Start new round if this was current round
        if (roundId == currentRound) {
            _startNewRound();
        }
    }

    /**
     * @notice Start a new round
     */
    function _startNewRound() internal {
        currentRound++;

        Round storage newRound = rounds[currentRound];
        newRound.roundId = currentRound;
        newRound.startTime = block.timestamp;
        newRound.endTime = block.timestamp + ROUND_DURATION;

        emit RoundStarted(currentRound, newRound.startTime, newRound.endTime);
    }

    /**
     * @notice Emergency draw numbers when VRF fails
     * @param roundId Round to draw numbers for
     * @param numbers Winning numbers to set
     */
    function emergencyDrawNumbers(uint256 roundId, uint256[NUMBERS_COUNT] calldata numbers)
        external
        onlyRole(OPERATOR_ROLE)
    {
        Round storage round = rounds[roundId];
        require(!round.numbersDrawn, "Numbers already drawn");
        require(block.timestamp > round.endTime + 1 hours, "Not enough time passed");

        _validateNumbers(numbers);
        round.winningNumbers = numbers;
        round.numbersDrawn = true;

        _calculateMatches(roundId);
        emit NumbersDrawn(roundId, numbers);

        if (roundId == currentRound) {
            _startNewRound();
        }
    }

    // =============================================================
    //                        WINNING & CLAIMING
    // =============================================================

    /**
     * @notice Claim winnings for specific bets
     * @param roundId Round to claim from
     * @param betIndices Array of bet indices to claim
     */
    function claimWinnings(uint256 roundId, uint256[] calldata betIndices) external nonReentrant {
        Round storage round = rounds[roundId];
        if (!round.numbersDrawn) revert NumbersNotDrawn();

        uint256 totalWinnings = 0;

        for (uint256 i = 0; i < betIndices.length; i++) {
            uint256 betIndex = betIndices[i];
            Bet storage bet = roundBets[roundId][betIndex];

            if (bet.user != msg.sender) continue;
            if (bet.claimed) revert AlreadyClaimed();
            if (bet.matchCount < 2) continue; // Minimum 2 matches for payout

            uint256 payout = _calculatePayout(bet.amount, bet.matchCount);
            bet.claimed = true;
            totalWinnings += payout;

            emit WinningsClaimed(roundId, msg.sender, payout, bet.matchCount);
        }

        if (totalWinnings == 0) revert NoWinnings();

        // Check if total payout exceeds maximum
        uint256 roundTotalPayout = _calculateTotalPayout(roundId);
        if (roundTotalPayout > maxPayoutPerRound) revert PayoutExceedsMaximum();

        userStats[msg.sender].totalWinnings += totalWinnings;
        platformToken.transfer(msg.sender, totalWinnings);
    }

    /**
     * @notice Calculate payout based on match count with house edge
     */
    function _calculatePayout(uint256 betAmount, uint8 matchCount) internal pure returns (uint256) {
        uint256 basePayout;
        if (matchCount == 5) basePayout = betAmount * 800; // 800x (reduced from 1000x)

        else if (matchCount == 4) basePayout = betAmount * 80; // 80x (reduced from 100x)

        else if (matchCount == 3) basePayout = betAmount * 8; // 8x (reduced from 10x)

        else if (matchCount == 2) basePayout = betAmount * 2; // 2x (same)

        else return 0;

        // Apply house edge
        return basePayout * (10000 - HOUSE_EDGE) / 10000;
    }

    /**
     * @notice Calculate total potential payout for a round
     */
    function _calculateTotalPayout(uint256 roundId) internal view returns (uint256 total) {
        Bet[] storage bets = roundBets[roundId];

        for (uint256 i = 0; i < bets.length; i++) {
            if (bets[i].matchCount >= 2) {
                total += _calculatePayout(bets[i].amount, bets[i].matchCount);
            }
        }
    }

    // =============================================================
    //                        GIFT SYSTEM
    // =============================================================

    /**
     * @notice Fund the gift reserve
     * @param amount Amount of tokens to add to gift reserve
     */
    function fundGiftReserve(uint256 amount) external {
        platformToken.transferFrom(msg.sender, address(this), amount);
        giftReserve += amount;
        emit GiftReserveFunded(msg.sender, amount);
    }

    /**
     * @notice Distribute gifts for completed round
     * @param roundId Round to distribute gifts for
     */
    function distributeGifts(uint256 roundId) external onlyRole(GIFT_DISTRIBUTOR_ROLE) {
        Round storage round = rounds[roundId];
        if (!round.numbersDrawn) revert NumbersNotDrawn();
        if (round.giftsDistributed) revert GiftsAlreadyDistributed();

        uint256 totalGiftCost = creatorGiftAmount + (giftRecipientsCount * userGiftAmount);
        if (giftReserve < totalGiftCost) revert InsufficientGiftReserve();

        round.giftsDistributed = true;

        // Gift creator
        platformToken.transfer(creator, creatorGiftAmount);
        giftReserve -= creatorGiftAmount;
        emit GiftDistributed(roundId, creator, creatorGiftAmount, true);

        // Find eligible users for gifts
        address[] memory eligibleUsers = _getEligibleGiftRecipients(roundId);

        uint256 recipientsToGift = giftRecipientsCount;
        if (eligibleUsers.length < recipientsToGift) {
            recipientsToGift = eligibleUsers.length;
        }

        // Randomly select and gift users
        for (uint256 i = 0; i < recipientsToGift; i++) {
            address recipient = eligibleUsers[i];
            userStats[recipient].lastGiftRound = roundId;

            platformToken.transfer(recipient, userGiftAmount);
            giftReserve -= userGiftAmount;
            emit GiftDistributed(roundId, recipient, userGiftAmount, false);
        }
    }

    /**
     * @notice Get eligible gift recipients for a round
     */
    function _getEligibleGiftRecipients(uint256 roundId) internal view returns (address[] memory) {
        Round storage round = rounds[roundId];
        address[] memory eligible = new address[](round.participants.length);
        uint256 count = 0;

        for (uint256 i = 0; i < round.participants.length; i++) {
            address user = round.participants[i];
            UserStats storage stats = userStats[user];

            // Check eligibility: consecutive play, not recently gifted
            if (
                stats.isEligibleForGift && user != creator
                    && (stats.lastGiftRound == 0 || roundId >= stats.lastGiftRound + GIFT_COOLDOWN / ROUND_DURATION)
            ) {
                eligible[count] = user;
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

    // =============================================================
    //                        HELPER FUNCTIONS
    // =============================================================

    /**
     * @notice Validate lottery numbers
     */
    function _validateNumbers(uint256[NUMBERS_COUNT] calldata numbers) internal pure {
        for (uint256 i = 0; i < NUMBERS_COUNT; i++) {
            if (numbers[i] == 0 || numbers[i] > MAX_NUMBER) revert InvalidNumbers();

            // Check for duplicates
            for (uint256 j = i + 1; j < NUMBERS_COUNT; j++) {
                if (numbers[i] == numbers[j]) revert InvalidNumbers();
            }
        }

        // Ensure numbers are sorted
        for (uint256 i = 0; i < NUMBERS_COUNT - 1; i++) {
            if (numbers[i] >= numbers[i + 1]) revert InvalidNumbers();
        }
    }

    /**
     * @notice Generate winning numbers from VRF random words
     */
    function _generateWinningNumbers(uint256[] memory randomWords)
        internal
        pure
        returns (uint256[NUMBERS_COUNT] memory)
    {
        uint256[NUMBERS_COUNT] memory numbers;
        bool[MAX_NUMBER + 1] memory used;

        for (uint256 i = 0; i < NUMBERS_COUNT; i++) {
            uint256 randomValue = randomWords[i];
            uint256 number;

            do {
                number = (randomValue % MAX_NUMBER) + 1;
                randomValue = uint256(keccak256(abi.encode(randomValue)));
            } while (used[number]);

            used[number] = true;
            numbers[i] = number;
        }

        // Sort numbers
        for (uint256 i = 0; i < NUMBERS_COUNT - 1; i++) {
            for (uint256 j = i + 1; j < NUMBERS_COUNT; j++) {
                if (numbers[i] > numbers[j]) {
                    uint256 temp = numbers[i];
                    numbers[i] = numbers[j];
                    numbers[j] = temp;
                }
            }
        }

        return numbers;
    }

    /**
     * @notice Calculate matches for all bets in a round
     */
    function _calculateMatches(uint256 roundId) internal {
        Round storage round = rounds[roundId];
        Bet[] storage bets = roundBets[roundId];

        for (uint256 i = 0; i < bets.length; i++) {
            uint8 matches = 0;

            for (uint256 j = 0; j < NUMBERS_COUNT; j++) {
                for (uint256 k = 0; k < NUMBERS_COUNT; k++) {
                    if (bets[i].numbers[j] == round.winningNumbers[k]) {
                        matches++;
                        break;
                    }
                }
            }

            bets[i].matchCount = matches;
        }
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Get current round information
     */
    function getCurrentRound() external view returns (Round memory) {
        return rounds[currentRound];
    }

    /**
     * @notice Get round information
     */
    function getRound(uint256 roundId) external view returns (Round memory) {
        return rounds[roundId];
    }

    /**
     * @notice Get user statistics
     */
    function getUserStats(address user) external view returns (UserStats memory) {
        return userStats[user];
    }

    /**
     * @notice Check if user can claim winnings for specific bets
     */
    function getClaimableWinnings(uint256 roundId, address user)
        external
        view
        returns (uint256 totalWinnings, uint256[] memory claimableBets)
    {
        Round storage round = rounds[roundId];
        if (!round.numbersDrawn) return (0, new uint256[](0));

        uint256[] storage userBets = userRoundBets[roundId][user];
        uint256[] memory claimable = new uint256[](userBets.length);
        uint256 count = 0;

        for (uint256 i = 0; i < userBets.length; i++) {
            uint256 betIndex = userBets[i];
            Bet storage bet = roundBets[roundId][betIndex];

            if (!bet.claimed && bet.matchCount >= 2) {
                claimable[count] = betIndex;
                count++;
                totalWinnings += _calculatePayout(bet.amount, bet.matchCount);
            }
        }

        // Resize array
        claimableBets = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            claimableBets[i] = claimable[i];
        }
    }

    /**
     * @notice Get gift reserve status
     */
    function getGiftReserveStatus() external view returns (uint256 reserve, uint256 costPerRound) {
        reserve = giftReserve;
        costPerRound = creatorGiftAmount + (giftRecipientsCount * userGiftAmount);
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    /**
     * @notice Schedule max payout change (with timelock)
     */
    function scheduleMaxPayoutChange(uint256 _maxPayout) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32 operationId = keccak256(abi.encodePacked("setMaxPayout", _maxPayout));
        timelocks[operationId] = block.timestamp + 24 hours;
        emit OperationScheduled(operationId, timelocks[operationId]);
    }

    /**
     * @notice Execute max payout change (after timelock)
     */
    function setMaxPayoutPerRound(uint256 _maxPayout) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32 operationId = keccak256(abi.encodePacked("setMaxPayout", _maxPayout));
        if (timelocks[operationId] == 0) revert OperationNotScheduled();
        if (block.timestamp < timelocks[operationId]) revert TimelockNotReady();

        maxPayoutPerRound = _maxPayout;
        delete timelocks[operationId];
        emit MaxPayoutUpdated(_maxPayout);
    }

    /**
     * @notice Update gift settings
     */
    function updateGiftSettings(uint256 _recipientsCount, uint256 _creatorAmount, uint256 _userAmount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        giftRecipientsCount = _recipientsCount;
        creatorGiftAmount = _creatorAmount;
        userGiftAmount = _userAmount;

        emit GiftSettingsUpdated(_recipientsCount, _creatorAmount, _userAmount);
    }

    /**
     * @notice Pause contract
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency withdraw tokens
     */
    function emergencyWithdraw(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        platformToken.transfer(msg.sender, amount);
    }

    /**
     * @notice Withdraw gift reserve (emergency only)
     */
    function emergencyWithdrawGiftReserve(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount <= giftReserve, "Amount exceeds reserve");
        giftReserve -= amount;
        platformToken.transfer(msg.sender, amount);
    }
}
