// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LotteryGameCore} from "../src/LotteryGameCore.sol";
import {LotteryGift} from "../src/LotteryGift.sol";
import {LotteryAdmin} from "../src/LotteryAdmin.sol";
import {IPlatformToken} from "../src/LotteryGameCore.sol";

contract DeployLottery is Script {
    // Sepolia VRF Configuration
    address constant SEPOLIA_VRF_COORDINATOR = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625;
    bytes32 constant SEPOLIA_KEY_HASH = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    // Anvil VRF Configuration (mock)
    address constant ANVIL_VRF_COORDINATOR = address(0); // Will be deployed
    bytes32 constant ANVIL_KEY_HASH = bytes32(0);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get network info
        uint256 chainId = block.chainid;
        bool isAnvil = chainId == 31337;
        bool isSepolia = chainId == 11155111;

        console.log("Deploying to chain ID:", chainId);
        console.log("Deployer:", deployer);

        // Get existing token address
        address platformToken = vm.envAddress("PLATFORM_TOKEN_ADDRESS");
        console.log("Using PlatformToken at:", platformToken);

        vm.startBroadcast(deployerPrivateKey);

        if (isAnvil) {
            deployToAnvil(platformToken, deployer);
        } else if (isSepolia) {
            deployToSepolia(platformToken, deployer);
        } else {
            revert("Unsupported network");
        }

        vm.stopBroadcast();
    }

    function deployToSepolia(address platformToken, address creator) internal {
        uint64 subscriptionId = uint64(vm.envUint("VRF_SUBSCRIPTION_ID"));

        console.log("Deploying to Sepolia...");
        console.log("VRF Subscription ID:", subscriptionId);

        // Deploy Core Contract
        LotteryGameCore coreContract =
            new LotteryGameCore(platformToken, SEPOLIA_VRF_COORDINATOR, subscriptionId, SEPOLIA_KEY_HASH);
        console.log("LotteryGameCore deployed at:", address(coreContract));

        // Deploy Gift Contract
        LotteryGift giftContract = new LotteryGift(address(coreContract), platformToken, creator);
        console.log("LotteryGift deployed at:", address(giftContract));

        // Deploy Admin Contract
        LotteryAdmin adminContract = new LotteryAdmin(address(coreContract), address(giftContract), platformToken);
        console.log("LotteryAdmin deployed at:", address(adminContract));

        // Set contract addresses
        coreContract.updateGiftContract(address(giftContract));
        coreContract.updateAdminContract(address(adminContract));

        console.log("\n=== Sepolia Deployment Complete ===");
        logDeploymentAddresses(address(coreContract), address(giftContract), address(adminContract));
        logNextSteps(true, subscriptionId);
    }

    function deployToAnvil(address platformToken, address creator) internal {
        console.log("Deploying to Anvil (local)...");

        // For Anvil, we'll use a mock VRF or deploy without VRF
        // Using subscription ID 1 for testing
        uint64 subscriptionId = 1;

        // Deploy Core Contract (VRF will need to be mocked)
        LotteryGameCore coreContract = new LotteryGameCore(
            platformToken,
            address(0x1), // Mock VRF coordinator for Anvil
            subscriptionId,
            bytes32(uint256(1)) // Mock key hash
        );
        console.log("LotteryGameCore deployed at:", address(coreContract));

        // Deploy Gift Contract
        LotteryGift giftContract = new LotteryGift(address(coreContract), platformToken, creator);
        console.log("LotteryGift deployed at:", address(giftContract));

        // Deploy Admin Contract
        LotteryAdmin adminContract = new LotteryAdmin(address(coreContract), address(giftContract), platformToken);
        console.log("LotteryAdmin deployed at:", address(adminContract));

        // Set contract addresses
        coreContract.updateGiftContract(address(giftContract));
        coreContract.updateAdminContract(address(adminContract));

        console.log("\n=== Anvil Deployment Complete ===");
        logDeploymentAddresses(address(coreContract), address(giftContract), address(adminContract));
        logNextSteps(false, subscriptionId);
    }

    function logDeploymentAddresses(address core, address gift, address admin) internal pure {
        console.log("Core Contract:", core);
        console.log("Gift Contract:", gift);
        console.log("Admin Contract:", admin);
    }

    function logNextSteps(bool isSepolia, uint64 subscriptionId) internal pure {
        console.log("\n=== Next Steps ===");
        if (isSepolia) {
            console.log("1. Add Core Contract as VRF consumer:");
            console.log("   - Go to https://vrf.chain.link");
            console.log("   - Add consumer with subscription ID:", subscriptionId);
            console.log("2. Fund VRF subscription with LINK tokens");
            console.log("3. Set up authorized burners on PlatformToken");
            console.log("4. Fund gift contract reserve");
        } else {
            console.log("1. For Anvil testing, VRF will need manual triggering");
            console.log("2. Set up authorized burners on PlatformToken");
            console.log("3. Fund gift contract reserve");
        }
    }
}
