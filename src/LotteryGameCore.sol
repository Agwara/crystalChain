// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VRFConsumer} from "./VRFConsumer.sol";

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

// =============================================================
//                        SHARED STRUCTURES
// =============================================================

struct Round {
    uint256 roundId;
    uint256 startTime;
    uint256 endTime;
    uint256[5] winningNumbers;
    bool numbersDrawn;
    uint256 totalBets;
    uint256 totalPrizePool;
    address[] participants;
    bool giftsDistributed;
    uint256 vrfRequestId;
}

struct Bet {
    address user;
    uint256[5] numbers;
    uint256 amount;
    uint256 timestamp;
    uint8 matchCount;
    bool claimed;
}

struct UserStats {
    uint256 lastGiftRound;
    uint256 consecutiveRounds;
    uint256 totalBets;
    uint256 totalWinnings;
    bool isEligibleForGift;
}

// =============================================================
//                        LOTTERY CORE
// =============================================================

/**
 * @title LotteryGameCore
 * @dev Core lottery functionality: betting, rounds, claiming
 */
contract LotteryGameCore is VRFConsumer, ReentrancyGuard, AccessControl, Pausable {
    // =============================================================
    //                           CONSTANTS
    // =============================================================

    uint256 public constant MAX_NUMBER = 49;
    uint256 public constant NUMBERS_COUNT = 5;
    uint256 public constant ROUND_DURATION = 5 minutes;
    uint256 public constant MIN_BET_AMOUNT = 1 * 10 ** 18;
    uint256 public constant MAX_BET_PER_USER_PER_ROUND = 1000 * 10 ** 18;
    uint32 private constant NUM_WORDS = 5;
    uint256 public constant HOUSE_EDGE = 500;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // =============================================================
    //                            STORAGE
    // =============================================================

    IPlatformToken public immutable platformToken;
    address public giftContract;
    address public adminContract;

    // Add a flag to track if gift contract has been set
    bool public giftContractSet;
    bool public adminContractSet;

    uint256 public currentRound;
    uint256 public maxPayoutPerRound = 10_000 * 10 ** 18;

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => Bet[]) public roundBets;
    mapping(uint256 => mapping(address => uint256[])) public userRoundBets;
    mapping(uint256 => mapping(address => uint256)) public userRoundBetAmount;
    mapping(address => UserStats) public userStats;
    mapping(uint256 => uint256) public vrfRequestToRound;
    mapping(uint256 => mapping(address => bool)) public roundParticipants;
    mapping(address => uint256) public lastParticipatedRound;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event RoundStarted(uint256 indexed roundId, uint256 startTime, uint256 endTime);
    event BetPlaced(uint256 indexed roundId, address indexed user, uint256[5] numbers, uint256 amount);
    event NumbersDrawn(uint256 indexed roundId, uint256[5] winningNumbers);
    event WinningsClaimed(uint256 indexed roundId, address indexed user, uint256 amount, uint8 matchCount);
    event GiftContractSet(address indexed newGiftContract);
    event AdminContractSet(address indexed newAdminContract);

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
    error InvalidRound();
    error PayoutExceedsMaximum();
    error UnauthorizedCaller();
    error GiftContractAlreadySet();
    error AdminContractAlreadySet();
    error NoZeroAddress();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(address _platformToken, address _vrfCoordinator, uint64 _subscriptionId, bytes32 _keyHash)
        VRFConsumer(_vrfCoordinator, _subscriptionId, _keyHash)
    {
        platformToken = IPlatformToken(_platformToken);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);

        _startNewRound();
    }

    modifier onlyGiftContract() {
        if (msg.sender != giftContract) revert UnauthorizedCaller();
        _;
    }

    modifier onlyAdminContract() {
        if (msg.sender != adminContract) revert UnauthorizedCaller();
        _;
    }

    // =============================================================
    //                        BETTING FUNCTIONS
    // =============================================================

    function placeBet(uint256[5] calldata numbers, uint256 amount) external nonReentrant whenNotPaused {
        Round storage round = rounds[currentRound];

        if (block.timestamp >= round.endTime) revert RoundNotActive();
        if (amount < MIN_BET_AMOUNT) revert BetAmountTooLow();
        if (platformToken.getStakingWeight(msg.sender) < platformToken.MIN_STAKE_AMOUNT()) {
            revert NotEligibleForBetting();
        }

        if (userRoundBetAmount[currentRound][msg.sender] + amount > MAX_BET_PER_USER_PER_ROUND) {
            revert ExceedsMaxBetPerRound();
        }

        _validateNumbers(numbers);

        platformToken.transferFrom(msg.sender, address(this), amount);

        Bet memory newBet = Bet({
            user: msg.sender,
            numbers: numbers,
            amount: amount,
            timestamp: block.timestamp,
            matchCount: 0,
            claimed: false
        });

        uint256 betIndex = roundBets[currentRound].length;
        roundBets[currentRound].push(newBet);
        userRoundBets[currentRound][msg.sender].push(betIndex);
        userRoundBetAmount[currentRound][msg.sender] += amount;

        round.totalBets += amount;
        round.totalPrizePool += amount;

        if (!roundParticipants[currentRound][msg.sender]) {
            roundParticipants[currentRound][msg.sender] = true;
            round.participants.push(msg.sender);

            UserStats storage stats = userStats[msg.sender];

            if (lastParticipatedRound[msg.sender] == currentRound - 1) {
                stats.consecutiveRounds++;
            } else if (lastParticipatedRound[msg.sender] != currentRound) {
                stats.consecutiveRounds = 1;
            }

            lastParticipatedRound[msg.sender] = currentRound;
            stats.isEligibleForGift = stats.consecutiveRounds >= 3; // CONSECUTIVE_PLAY_REQUIREMENT
        }

        userStats[msg.sender].totalBets += amount;

        emit BetPlaced(currentRound, msg.sender, numbers, amount);

        if (block.timestamp >= round.endTime && !round.numbersDrawn) {
            _endRound();
        }
    }

    // =============================================================
    //                        ROUND MANAGEMENT
    // =============================================================

    function endRound() external {
        Round storage round = rounds[currentRound];
        if (block.timestamp < round.endTime) revert RoundNotEnded();
        if (round.numbersDrawn) revert InvalidRound();

        _endRound();
    }

    function _endRound() internal {
        Round storage round = rounds[currentRound];

        uint256 requestId = _requestRandomWords(NUM_WORDS);

        round.vrfRequestId = requestId;
        vrfRequestToRound[requestId] = currentRound;
    }

    function _handleRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 roundId = vrfRequestToRound[requestId];
        Round storage round = rounds[roundId];

        uint256[5] memory winningNumbers = _generateWinningNumbers(randomWords);
        round.winningNumbers = winningNumbers;
        round.numbersDrawn = true;

        _calculateMatches(roundId);

        emit NumbersDrawn(roundId, winningNumbers);

        if (roundId == currentRound) {
            _startNewRound();
        }
    }

    function _startNewRound() internal {
        currentRound++;

        Round storage newRound = rounds[currentRound];
        newRound.roundId = currentRound;
        newRound.startTime = block.timestamp;
        newRound.endTime = block.timestamp + ROUND_DURATION;

        emit RoundStarted(currentRound, newRound.startTime, newRound.endTime);
    }

    function emergencyDrawNumbers(uint256 roundId, uint256[5] calldata numbers) external onlyRole(OPERATOR_ROLE) {
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
    // Users can claim winnings for multiple bets in a single transaction

    function claimWinnings(uint256 roundId, uint256[] calldata betIndices) external nonReentrant {
        Round storage round = rounds[roundId];
        if (!round.numbersDrawn) revert NumbersNotDrawn();

        uint256 totalWinnings = 0;

        for (uint256 i = 0; i < betIndices.length; i++) {
            uint256 betIndex = betIndices[i];
            Bet storage bet = roundBets[roundId][betIndex];

            if (bet.user != msg.sender) continue;
            if (bet.claimed) revert AlreadyClaimed();
            if (bet.matchCount < 2) continue;

            uint256 payout = _calculatePayout(bet.amount, bet.matchCount);
            bet.claimed = true;
            totalWinnings += payout;

            emit WinningsClaimed(roundId, msg.sender, payout, bet.matchCount);
        }

        if (totalWinnings == 0) revert NoWinnings();

        uint256 roundTotalPayout = _calculateTotalPayout(roundId);
        if (roundTotalPayout > maxPayoutPerRound) revert PayoutExceedsMaximum();

        userStats[msg.sender].totalWinnings += totalWinnings;
        platformToken.transfer(msg.sender, totalWinnings);
    }

    function _calculatePayout(uint256 betAmount, uint8 matchCount) internal pure returns (uint256) {
        uint256 basePayout;
        if (matchCount == 5) basePayout = betAmount * 800;
        else if (matchCount == 4) basePayout = betAmount * 80;
        else if (matchCount == 3) basePayout = betAmount * 8;
        else if (matchCount == 2) basePayout = betAmount * 2;
        else return 0;

        return basePayout * (10000 - HOUSE_EDGE) / 10000;
    }

    function _calculateTotalPayout(uint256 roundId) internal view returns (uint256 total) {
        Bet[] storage bets = roundBets[roundId];

        for (uint256 i = 0; i < bets.length; i++) {
            if (bets[i].matchCount >= 2) {
                total += _calculatePayout(bets[i].amount, bets[i].matchCount);
            }
        }
    }

    // =============================================================
    //                        HELPER FUNCTIONS
    // =============================================================

    function _validateNumbers(uint256[5] calldata numbers) internal pure {
        for (uint256 i = 0; i < 5; i++) {
            if (numbers[i] == 0 || numbers[i] > MAX_NUMBER) revert InvalidNumbers();

            for (uint256 j = i + 1; j < 5; j++) {
                if (numbers[i] == numbers[j]) revert InvalidNumbers();
            }
        }

        for (uint256 i = 0; i < 4; i++) {
            if (numbers[i] >= numbers[i + 1]) revert InvalidNumbers();
        }
    }

    function _generateWinningNumbers(uint256[] memory randomWords) internal pure returns (uint256[5] memory) {
        uint256[5] memory numbers;
        bool[50] memory used; // 0-49, but we use 1-49

        for (uint256 i = 0; i < 5; i++) {
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

    function _calculateMatches(uint256 roundId) internal {
        Round storage round = rounds[roundId];
        Bet[] storage bets = roundBets[roundId];

        for (uint256 i = 0; i < bets.length; i++) {
            uint8 matches = 0;

            for (uint256 j = 0; j < 5; j++) {
                for (uint256 k = 0; k < 5; k++) {
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
    //                        ADMIN FUNCTIONS (called by AdminContract)
    // =============================================================

    function setMaxPayoutPerRound(uint256 _maxPayout) external onlyAdminContract {
        maxPayoutPerRound = _maxPayout;
    }

    function markGiftsDistributed(uint256 roundId) external onlyGiftContract {
        rounds[roundId].giftsDistributed = true;
    }

    // Alternative: Allow updating gift contract with additional security
    function updateGiftContract(address _giftContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_giftContract == address(0)) revert NoZeroAddress();

        giftContract = _giftContract;

        emit GiftContractSet(_giftContract);
    }

    // Alternative: Allow updating admin contract with additional security
    function updateAdminContract(address _adminContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_adminContract == address(0)) revert NoZeroAddress();

        adminContract = _adminContract;

        emit AdminContractSet(_adminContract);
    }

    function updateUserGiftRound(address user, uint256 roundId) external onlyGiftContract {
        userStats[user].lastGiftRound = roundId;
    }

    function pause() external onlyAdminContract {
        _pause();
    }

    function unpause() external onlyAdminContract {
        _unpause();
    }

    function emergencyWithdraw(uint256 amount) external onlyAdminContract {
        platformToken.transfer(adminContract, amount);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    function getUserRoundBets(uint256 roundId, address user) external view returns (uint256[] memory) {
        return userRoundBets[roundId][user];
    }

    function getBet(uint256 roundId, uint256 betIndex) external view returns (Bet memory) {
        return roundBets[roundId][betIndex];
    }

    function getCurrentRound() external view returns (Round memory) {
        return rounds[currentRound];
    }

    function getRound(uint256 roundId) external view returns (Round memory) {
        return rounds[roundId];
    }

    function getUserStats(address user) external view returns (UserStats memory) {
        return userStats[user];
    }

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

        claimableBets = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            claimableBets[i] = claimable[i];
        }
    }
}
