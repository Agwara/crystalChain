// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {LotteryGameCore, IPlatformToken} from "./LotteryGameCore.sol";
import {LotteryGift} from "./LotteryGift.sol";

// =============================================================
//                        LOTTERY ADMIN
// =============================================================

/**
 * @title LotteryAdmin
 * @dev Administrative functions with timelock
 */
contract LotteryAdmin is AccessControl {
    LotteryGameCore public immutable coreContract;
    LotteryGift public immutable giftContract;
    IPlatformToken public immutable platformToken;

    mapping(bytes32 => uint256) public timelocks;

    event OperationScheduled(bytes32 indexed operationId, uint256 executeTime);
    event MaxPayoutUpdated(uint256 newMaxPayout);

    error TimelockNotReady();
    error OperationNotScheduled();

    constructor(address _coreContract, address _giftContract, address _platformToken) {
        coreContract = LotteryGameCore(_coreContract);
        giftContract = LotteryGift(_giftContract);
        platformToken = IPlatformToken(_platformToken);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function scheduleMaxPayoutChange(uint256 _maxPayout) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32 operationId = keccak256(abi.encodePacked("setMaxPayout", _maxPayout));
        timelocks[operationId] = block.timestamp + 24 hours;
        emit OperationScheduled(operationId, timelocks[operationId]);
    }

    function setMaxPayoutPerRound(uint256 _maxPayout) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32 operationId = keccak256(abi.encodePacked("setMaxPayout", _maxPayout));
        if (timelocks[operationId] == 0) revert OperationNotScheduled();
        if (block.timestamp < timelocks[operationId]) revert TimelockNotReady();

        coreContract.setMaxPayoutPerRound(_maxPayout);
        delete timelocks[operationId];
        emit MaxPayoutUpdated(_maxPayout);
    }

    function updateGiftSettings(uint256 _recipientsCount, uint256 _creatorAmount, uint256 _userAmount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        giftContract.updateGiftSettings(_recipientsCount, _creatorAmount, _userAmount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        coreContract.pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        coreContract.unpause();
    }

    function emergencyWithdraw(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        coreContract.emergencyWithdraw(amount);
        platformToken.transfer(msg.sender, amount);
    }

    function emergencyWithdrawGiftReserve(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        giftContract.emergencyWithdrawGiftReserve(amount);
    }
}
