// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

/**
 * @title VRFConsumer
 * @author Agwara Nnaemeka
 * @dev Abstract contract for Chainlink VRF integration
 * @notice Handles VRF requests and responses, to be inherited by consumer contracts
 */
abstract contract VRFConsumer is VRFConsumerBaseV2 {
    // =============================================================
    //                         CHAINLINK VRF
    // =============================================================

    VRFCoordinatorV2Interface internal immutable vrfCoordinator;
    uint64 internal immutable subscriptionId;
    bytes32 internal immutable keyHash;
    uint32 internal constant callbackGasLimit = 2500000;
    uint16 internal constant requestConfirmations = 3;

    // =============================================================
    //                            MAPPINGS
    // =============================================================

    /// @notice VRF request ID to callback address mapping
    mapping(uint256 => address) public vrfRequestToCallback;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event VRFRequested(uint256 indexed requestId, address indexed caller);
    event VRFReceived(uint256 indexed requestId, uint256[] randomWords);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error OnlyVRFCoordinator();
    error InvalidVRFRequest();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(address _vrfCoordinator, uint64 _subscriptionId, bytes32 _keyHash) VRFConsumerBaseV2(_vrfCoordinator) {
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
    }

    // =============================================================
    //                        VRF FUNCTIONS
    // =============================================================

    /**
     * @notice Request random words from Chainlink VRF
     * @param numWords Number of random words to request
     * @return requestId The VRF request ID
     */
    function _requestRandomWords(uint32 numWords) internal returns (uint256 requestId) {
        requestId =
            vrfCoordinator.requestRandomWords(keyHash, subscriptionId, requestConfirmations, callbackGasLimit, numWords);

        vrfRequestToCallback[requestId] = msg.sender;
        emit VRFRequested(requestId, msg.sender);
    }

    /**
     * @notice Chainlink VRF callback function
     * @dev Must be implemented by the inheriting contract
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal virtual override {
        if (vrfRequestToCallback[requestId] == address(0)) {
            revert InvalidVRFRequest();
        }

        emit VRFReceived(requestId, randomWords);
        _handleRandomWords(requestId, randomWords);
    }

    /**
     * @notice Internal function to handle random words
     * @dev Must be implemented by the inheriting contract
     */
    function _handleRandomWords(uint256 requestId, uint256[] memory randomWords) internal virtual;
}
