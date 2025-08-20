// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PlatformToken.sol";

contract DeployPlatformToken is Script {
    // Deployment configuration
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18; // 1M tokens

    // Deployment addresses (will be populated during deployment)
    address public deployer;
    address public platformToken;

    function run() external {
        // Get deployer from private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying with account:", deployer);
        console.log("Account balance:", deployer.balance);
        console.log("Initial supply:", INITIAL_SUPPLY);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy PlatformToken
        PlatformToken token = new PlatformToken(INITIAL_SUPPLY);
        platformToken = address(token);

        console.log("PlatformToken deployed at:", platformToken);
        console.log("Owner:", token.owner());
        console.log("Total supply:", token.totalSupply());
        console.log("Deployer balance:", token.balanceOf(deployer));

        // Verify initial state
        require(token.owner() == deployer, "Owner not set correctly");
        require(token.totalSupply() == INITIAL_SUPPLY, "Total supply incorrect");
        require(token.balanceOf(deployer) == INITIAL_SUPPLY, "Deployer balance incorrect");
        require(token.authorizedBurners(deployer), "Deployer not authorized burner");
        require(token.authorizedTransferors(deployer), "Deployer not authorized transferor");

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Sepolia");
        console.log("Deployer:", deployer);
        console.log("PlatformToken:", platformToken);
        console.log("Gas used: Check transaction receipt");
        console.log("===========================\n");

        // Save deployment addresses to file
        string memory deploymentInfo = string(
            abi.encodePacked(
                "{\n",
                '  "network": "sepolia",\n',
                '  "deployer": "',
                vm.toString(deployer),
                '",\n',
                '  "platformToken": "',
                vm.toString(platformToken),
                '",\n',
                '  "initialSupply": "',
                vm.toString(INITIAL_SUPPLY),
                '",\n',
                '  "deploymentTimestamp": "',
                vm.toString(block.timestamp),
                '"\n',
                "}"
            )
        );

        vm.writeFile("deployments/sepolia.json", deploymentInfo);

        console.log("Deployment info saved to deployments/sepolia.json");

        // Verification instructions
        console.log("\n=== Verification Instructions ===");
        console.log("Run the following command to verify on Etherscan:");
        console.log(
            string(
                abi.encodePacked(
                    "forge verify-contract ",
                    vm.toString(platformToken),
                    " src/PlatformToken.sol:PlatformToken ",
                    "--chain sepolia ",
                    "--constructor-args $(cast abi-encode 'constructor(uint256)' ",
                    vm.toString(INITIAL_SUPPLY),
                    ")"
                )
            )
        );
        console.log("==================================\n");
    }
}

// Contract for testing deployment on local network
contract LocalDeploymentTest is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy with smaller supply for testing
        uint256 testSupply = 100_000 * 10 ** 18; // 100k tokens
        PlatformToken token = new PlatformToken(testSupply);

        console.log("Test deployment completed:");
        console.log("Token address:", address(token));
        console.log("Test supply:", testSupply);

        // Create some test users
        address alice = address(0x1);
        address bob = address(0x2);

        // Give them some tokens
        token.transfer(alice, 10_000 * 10 ** 18);
        token.transfer(bob, 10_000 * 10 ** 18);

        console.log("Test users funded:");
        console.log("Alice balance:", token.balanceOf(alice));
        console.log("Bob balance:", token.balanceOf(bob));

        vm.stopBroadcast();
    }
}
