// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {CCTPStrategy} from "../src/CCTPStrategy.sol";
import {HyperRemoteStrategy} from "../src/HyperRemoteStrategy.sol";
import {CCTPHelpers} from "../src/libraries/CCTPHelpers.sol";

/// @title DeployHyperStrategy
/// @notice Deployment script for CCTP Strategy bridging to HyperEVM HLP vault
/// @dev Deploys:
///   1. CCTPStrategy on Ethereum (origin)
///   2. HyperRemoteStrategy on HyperEVM (remote)
contract DeployHyperStrategy is Script {
    // ============================================
    // CCTP ADDRESSES (same on all chains)
    // ============================================
    address constant TOKEN_MESSENGER = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address constant MESSAGE_TRANSMITTER = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;

    // ============================================
    // STRATEGY PARAMETERS - CONFIGURE THESE
    // ============================================
    string constant STRATEGY_NAME = "HLP CCTP USDC";
    address constant DEPOSITER = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;
    address constant GOVERNANCE = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    function run() external {
        // Step 1: Compute the remote strategy address before deployment
        // This allows us to deploy the origin strategy with the correct counterpart
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));

        // Get deployer nonce on HyperEVM to predict remote address
        vm.createSelectFork(vm.envString("HYPER_RPC_URL"));
        uint64 hyperNonce = vm.getNonce(deployer);
        address predictedRemote = computeCreateAddress(deployer, uint256(hyperNonce));

        console.log("Deployer:", deployer);
        console.log("HyperEVM nonce:", hyperNonce);
        console.log("Predicted remote address:", predictedRemote);

        // Step 2: Deploy origin strategy on Ethereum
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast();

        CCTPStrategy originStrategy = new CCTPStrategy(
            CCTPHelpers.ETHEREUM_USDC,
            STRATEGY_NAME,
            TOKEN_MESSENGER,
            MESSAGE_TRANSMITTER,
            CCTPHelpers.HYPEREVM_DOMAIN,
            predictedRemote,
            DEPOSITER
        );

        vm.stopBroadcast();

        console.log("=== ETHEREUM ===");
        console.log("Origin Strategy:", address(originStrategy));

        // Step 3: Deploy remote strategy on HyperEVM
        vm.createSelectFork(vm.envString("HYPER_RPC_URL"));
        vm.startBroadcast();

        HyperRemoteStrategy remoteStrategy = new HyperRemoteStrategy(
            CCTPHelpers.HYPEREVM_USDC,
            GOVERNANCE,
            TOKEN_MESSENGER,
            MESSAGE_TRANSMITTER,
            address(originStrategy)
        );

        vm.stopBroadcast();

        console.log("=== HYPEREVM ===");
        console.log("Remote Strategy:", address(remoteStrategy));

        // Verify address prediction was correct
        require(
            address(remoteStrategy) == predictedRemote,
            "Remote address mismatch! Nonce changed between forks."
        );

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Origin (Ethereum):", address(originStrategy));
        console.log("Remote (HyperEVM):", address(remoteStrategy));
    }

}
