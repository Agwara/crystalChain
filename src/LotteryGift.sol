// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {LotteryGameCore, Round, UserStats, IPlatformToken} from "./LotteryGameCore.sol";

// =============================================================
//                        LOTTERY GIFT
// =============================================================

/**
 * @title LotteryGift
 * @dev Gift distribution functionality
 */
contract LotteryGift is AccessControl {
    bytes32 public constant GIFT_DISTRIBUTOR_ROLE = keccak256("GIFT_DISTRIBUTOR_ROLE");

    LotteryGameCore public immutable coreContract;
    IPlatformToken public immutable platformToken;
    address public immutable creator;

    uint256 public constant GIFT_COOLDOWN = 24 hours;
    uint256 public constant CONSECUTIVE_PLAY_REQUIREMENT = 3;
    uint256 public constant ROUND_DURATION = 5 minutes;

    uint256 public giftRecipientsCount = 10;
    uint256 public creatorGiftAmount = 100 * 10 ** 18;
    uint256 public userGiftAmount = 50 * 10 ** 18;
    uint256 public giftReserve;

    event GiftDistributed(uint256 indexed roundId, address indexed recipient, uint256 amount, bool isCreator);
    event GiftSettingsUpdated(uint256 recipientsCount, uint256 creatorAmount, uint256 userAmount);
    event GiftReserveFunded(address indexed funder, uint256 amount);

    error NumbersNotDrawn();
    error GiftsAlreadyDistributed();
    error InsufficientGiftReserve();

    constructor(address _coreContract, address _platformToken, address _creator) {
        coreContract = LotteryGameCore(_coreContract);
        platformToken = IPlatformToken(_platformToken);
        creator = _creator;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GIFT_DISTRIBUTOR_ROLE, msg.sender);
    }

    function fundGiftReserve(uint256 amount) external {
        platformToken.transferFrom(msg.sender, address(this), amount);
        giftReserve += amount;
        emit GiftReserveFunded(msg.sender, amount);
    }

    function distributeGifts(uint256 roundId) external onlyRole(GIFT_DISTRIBUTOR_ROLE) {
        Round memory round = coreContract.getRound(roundId);
        if (!round.numbersDrawn) revert NumbersNotDrawn();
        if (round.giftsDistributed) revert GiftsAlreadyDistributed();

        uint256 totalGiftCost = creatorGiftAmount + (giftRecipientsCount * userGiftAmount);
        if (giftReserve < totalGiftCost) revert InsufficientGiftReserve();

        // Mark gifts as distributed in core contract
        coreContract.markGiftsDistributed(roundId);

        // Gift creator
        platformToken.transfer(creator, creatorGiftAmount);
        giftReserve -= creatorGiftAmount;
        emit GiftDistributed(roundId, creator, creatorGiftAmount, true);

        // Find eligible users for gifts
        address[] memory eligibleUsers = _getEligibleGiftRecipients(roundId);

        if (eligibleUsers.length > 0) {
            uint256 recipientsToGift = giftRecipientsCount;
            if (eligibleUsers.length < recipientsToGift) {
                recipientsToGift = eligibleUsers.length;
            }

            address[] memory selectedRecipients =
                _selectRandomRecipients(eligibleUsers, recipientsToGift, round.winningNumbers);

            for (uint256 i = 0; i < selectedRecipients.length; i++) {
                address recipient = selectedRecipients[i];

                // Update user's last gift round in core contract
                coreContract.updateUserGiftRound(recipient, roundId);

                platformToken.transfer(recipient, userGiftAmount);
                giftReserve -= userGiftAmount;
                emit GiftDistributed(roundId, recipient, userGiftAmount, false);
            }
        }
    }

    function _getEligibleGiftRecipients(uint256 roundId) internal view returns (address[] memory) {
        Round memory round = coreContract.getRound(roundId);
        address[] memory eligible = new address[](round.participants.length);
        uint256 count = 0;

        for (uint256 i = 0; i < round.participants.length; i++) {
            address user = round.participants[i];
            UserStats memory stats = coreContract.getUserStats(user);

            if (
                stats.isEligibleForGift && user != creator
                    && (stats.lastGiftRound == 0 || roundId >= stats.lastGiftRound + GIFT_COOLDOWN / ROUND_DURATION)
            ) {
                eligible[count] = user;
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = eligible[i];
        }

        return result;
    }

    function _selectRandomRecipients(address[] memory eligibleUsers, uint256 count, uint256[5] memory entropy)
        internal
        view
        returns (address[] memory)
    {
        if (eligibleUsers.length <= count) {
            return eligibleUsers;
        }

        address[] memory selected = new address[](count);
        address[] memory remaining = new address[](eligibleUsers.length);

        for (uint256 i = 0; i < eligibleUsers.length; i++) {
            remaining[i] = eligibleUsers[i];
        }

        uint256 remainingCount = eligibleUsers.length;

        uint256 randomSeed = uint256(
            keccak256(
                abi.encodePacked(
                    entropy[0], entropy[1], entropy[2], entropy[3], entropy[4], block.timestamp, block.prevrandao
                )
            )
        );

        for (uint256 i = 0; i < count; i++) {
            randomSeed = uint256(keccak256(abi.encodePacked(randomSeed, i)));
            uint256 randomIndex = randomSeed % remainingCount;

            selected[i] = remaining[randomIndex];

            remaining[randomIndex] = remaining[remainingCount - 1];
            remainingCount--;
        }

        return selected;
    }

    function updateGiftSettings(uint256 _recipientsCount, uint256 _creatorAmount, uint256 _userAmount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        giftRecipientsCount = _recipientsCount;
        creatorGiftAmount = _creatorAmount;
        userGiftAmount = _userAmount;

        emit GiftSettingsUpdated(_recipientsCount, _creatorAmount, _userAmount);
    }

    function getGiftReserveStatus() external view returns (uint256 reserve, uint256 costPerRound) {
        reserve = giftReserve;
        costPerRound = creatorGiftAmount + (giftRecipientsCount * userGiftAmount);
    }

    function emergencyWithdrawGiftReserve(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount <= giftReserve, "Amount exceeds reserve");
        giftReserve -= amount;
        platformToken.transfer(msg.sender, amount);
    }
}
