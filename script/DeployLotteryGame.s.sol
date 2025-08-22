// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/LotteryGame.sol";

contract DeployLotteryGame is Script {
    // Sepolia Chainlink VRF Configuration
    address constant SEPOLIA_VRF_COORDINATOR = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625;
    bytes32 constant SEPOLIA_KEY_HASH = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c; // 30 gwei

    // Anvil/Local Configuration (mock values)
    address constant LOCAL_VRF_COORDINATOR = address(0x1234567890123456789012345678901234567890);
    bytes32 constant LOCAL_KEY_HASH = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    // Platform Token Address (already deployed on Sepolia)
    address constant SEPOLIA_PLATFORM_TOKEN = 0xECEfF35FE011694DfCEa93E97bba60D2FEEc2253;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying LotteryGame with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Get network-specific parameters
        (address vrfCoordinator, uint64 subscriptionId, bytes32 keyHash, address platformToken) = getNetworkParams();

        console.log("VRF Coordinator:", vrfCoordinator);
        console.log("Subscription ID:", subscriptionId);
        console.log("Key Hash:", vm.toString(keyHash));
        console.log("Platform Token:", platformToken);

        // Deploy LotteryGame
        LotteryGame lotteryGame = new LotteryGame(
            platformToken,
            vrfCoordinator,
            subscriptionId,
            keyHash,
            deployer // Creator address
        );

        console.log("LotteryGame deployed to:", address(lotteryGame));

        vm.stopBroadcast();

        // Log deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", getChainName());
        console.log("LotteryGame Address:", address(lotteryGame));
        console.log("Platform Token:", platformToken);
        console.log("VRF Coordinator:", vrfCoordinator);
        console.log("Creator:", deployer);

        // Save deployment info
        saveDeployment(address(lotteryGame), platformToken, vrfCoordinator, deployer);
    }

    function getNetworkParams()
        internal
        view
        returns (address vrfCoordinator, uint64 subscriptionId, bytes32 keyHash, address platformToken)
    {
        uint256 chainId = block.chainid;

        if (chainId == 11155111) {
            // Sepolia
            vrfCoordinator = SEPOLIA_VRF_COORDINATOR;
            subscriptionId = uint64(vm.envUint("SEPOLIA_SUBSCRIPTION_ID"));
            keyHash = SEPOLIA_KEY_HASH;
            platformToken = SEPOLIA_PLATFORM_TOKEN;
        } else if (chainId == 31337) {
            // Anvil/Local
            vrfCoordinator = LOCAL_VRF_COORDINATOR;
            subscriptionId = 1; // Mock subscription ID
            keyHash = LOCAL_KEY_HASH;
            // For local testing, you might want to deploy a mock token
            platformToken = vm.envAddress("LOCAL_PLATFORM_TOKEN");
        } else {
            revert("Unsupported network");
        }
    }

    function getChainName() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 11155111) return "Sepolia";
        if (chainId == 31337) return "Anvil";
        return "Unknown";
    }

    function saveDeployment(address lotteryGame, address platformToken, address vrfCoordinator, address creator)
        internal
    {
        string memory json = "deployment";

        vm.serializeAddress(json, "lotteryGame", lotteryGame);
        vm.serializeAddress(json, "platformToken", platformToken);
        vm.serializeAddress(json, "vrfCoordinator", vrfCoordinator);
        vm.serializeAddress(json, "creator", creator);
        vm.serializeUint(json, "chainId", block.chainid);
        string memory finalJson = vm.serializeUint(json, "blockNumber", block.number);

        string memory chainName = getChainName();
        string memory fileName = string.concat("./deployments/", chainName, "_deployment.json");
        vm.writeJson(finalJson, fileName);

        console.log("Deployment info saved to:", fileName);
    }
}
