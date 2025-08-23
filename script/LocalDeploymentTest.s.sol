// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PlatformToken} from "../src/PlatformToken.sol";

contract LocalDeploymentTest is Script {
    function run() external {
        // Load accounts from Anvil
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // anvil[0]
        address alice = vm.addr(vm.envUint("ALICE_KEY")); // anvil[1]
        address bob = vm.addr(vm.envUint("BOB_KEY")); // anvil[2]

        vm.startBroadcast(deployerPrivateKey);

        // Deploy with smaller supply for testing
        uint256 testSupply = 100_000 * 10 ** 18;
        PlatformToken token = new PlatformToken(testSupply);

        console.log("Test deployment completed:");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Token address:", address(token));
        console.log("Test supply:", testSupply);

        // Give them some tokens
        token.transfer(alice, 10_000 * 10 ** 18);
        token.transfer(bob, 10_000 * 10 ** 18);

        console.log("Test users funded:");
        console.log("Alice:", alice, "balance:", token.balanceOf(alice));
        console.log("Bob:", bob, "balance:", token.balanceOf(bob));

        vm.stopBroadcast();
    }
}
