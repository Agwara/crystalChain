// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../src/VRFConsumer.sol";

/**
 * @title MockVRFCoordinator
 * @dev Mock VRF Coordinator for testing purposes
 */
contract MockVRFCoordinator {
    uint256 private requestIdCounter = 1;

    mapping(uint256 => address) public requestIdToConsumer;
    mapping(uint256 => uint32) public requestIdToNumWords;

    event RandomWordsRequested(
        bytes32 indexed keyHash,
        uint256 requestId,
        uint256 preSeed,
        uint64 indexed subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords,
        address indexed sender
    );

    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId) {
        requestId = requestIdCounter++;
        requestIdToConsumer[requestId] = msg.sender;
        requestIdToNumWords[requestId] = numWords;

        emit RandomWordsRequested(
            keyHash,
            requestId,
            0, // preSeed
            subId,
            minimumRequestConfirmations,
            callbackGasLimit,
            numWords,
            msg.sender
        );
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        address consumer = requestIdToConsumer[requestId];
        require(consumer != address(0), "Invalid request ID");

        VRFConsumer(consumer).rawFulfillRandomWords(requestId, randomWords);
    }

    // Helper function for testing with specific numbers
    function fulfillRandomWordsWithNumbers(uint256 requestId, uint256[5] memory numbers) external {
        address consumer = requestIdToConsumer[requestId];
        require(consumer != address(0), "Invalid request ID");

        uint256[] memory randomWords = new uint256[](5);

        // Convert specific numbers to pseudo-random values that will generate those numbers
        // This is a reverse-engineering approach for testing
        for (uint256 i = 0; i < 5; i++) {
            // Generate a value that when processed will give us the desired number
            randomWords[i] = _generateRandomForNumber(numbers[i], i);
        }

        VRFConsumer(consumer).rawFulfillRandomWords(requestId, randomWords);
    }

    function _generateRandomForNumber(uint256 desiredNumber, uint256 seed) internal pure returns (uint256) {
        // Generate a pseudo-random value that will produce the desired number
        // when processed by the lottery's _generateWinningNumbers function

        // Since the lottery uses (randomValue % 49) + 1, we need to find a value
        // that when modded by 49 gives us (desiredNumber - 1)
        uint256 baseValue = (desiredNumber - 1) + (seed * 49);

        // Add some randomness while maintaining the modulo property
        return baseValue * 1000 + seed;
    }

    function getNextRequestId() external view returns (uint256) {
        return requestIdCounter;
    }
}
