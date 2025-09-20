// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title VRFConsumer
 * @author Agwara Nnaemeka
 * @dev Abstract contract for Chainlink VRF v2.5 integration
 * @notice Handles VRF requests and responses, to be inherited by consumer contracts
 */
abstract contract VRFConsumer is VRFConsumerBaseV2Plus {
    // =============================================================
    //                         CHAINLINK VRF V2.5
    // =============================================================

    uint256 internal immutable subscriptionId;
    bytes32 internal immutable keyHash;
    uint32 internal constant callbackGasLimit = 500000;
    uint16 internal constant requestConfirmations = 3;
    bool internal constant nativePayment = true; // Set to true if paying with native token

    // =============================================================
    //                            MAPPINGS
    // =============================================================

    /// @notice VRF request ID to requesting contract mapping
    mapping(uint256 => bool) public validVRFRequests;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event VRFRequested(uint256 indexed requestId, address indexed caller);
    event VRFReceived(uint256 indexed requestId, uint256[] randomWords);

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidVRFRequest();

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(address _vrfCoordinator, uint256 _subscriptionId, bytes32 _keyHash)
        VRFConsumerBaseV2Plus(_vrfCoordinator)
    {
        subscriptionId = _subscriptionId;
        keyHash = _keyHash;
    }

    // =============================================================
    //                        VRF FUNCTIONS
    // =============================================================

    /**
     * @notice Request random words from Chainlink VRF v2.5
     * @param numWords Number of random words to request
     * @return requestId The VRF request ID
     */
    function _requestRandomWords(uint32 numWords) internal returns (uint256 requestId) {
        // Build the request struct for v2.5
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: keyHash,
            subId: subscriptionId,
            requestConfirmations: requestConfirmations,
            callbackGasLimit: callbackGasLimit,
            numWords: numWords,
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment}))
        });

        requestId = s_vrfCoordinator.requestRandomWords(request);

        validVRFRequests[requestId] = true;
        emit VRFRequested(requestId, address(this));
    }

    /**
     * @notice Chainlink VRF callback function
     * @dev Called by VRF Coordinator when random words are ready
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual override {
        if (!validVRFRequests[requestId]) {
            revert InvalidVRFRequest();
        }

        // Clean up to prevent replay
        delete validVRFRequests[requestId];

        emit VRFReceived(requestId, randomWords);
        _handleRandomWords(requestId, randomWords);
    }

    /**
     * @notice Internal function to handle random words
     * @dev Must be implemented by the inheriting contract
     */
    function _handleRandomWords(uint256 requestId, uint256[] memory randomWords) internal virtual;
}
