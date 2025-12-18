// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {KatanaStrategy} from "../src/KatanaStrategy.sol";
import {KatanaRemoteStrategy} from "../src/KatanaRemoteStrategy.sol";
import {KatanaHelpers} from "../src/libraries/KatanaHelpers.sol";
import {IPolygonZkEVMBridgeV2} from "../src/interfaces/lxly/IPolygonZkEVMBridgeV2.sol";

/// @title DeployKatanaStrategy
/// @notice Deployment script for Katana Strategy bridging to Katana L2 via LxLy/Agglayer
/// @dev Deploys:
///   1. KatanaStrategy on Ethereum (origin)
///   2. KatanaRemoteStrategy on Katana (remote)
contract DeployKatanaStrategy is Script {
    // ============================================
    // BRIDGE ADDRESSES
    // ============================================
    address constant UNIFIED_BRIDGE = 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;

    // ============================================
    // NETWORK IDs
    // ============================================
    uint32 constant ETHEREUM_NETWORK_ID = 0;
    uint32 constant KATANA_NETWORK_ID = 20;

    // ============================================
    // STRATEGY PARAMETERS - CONFIGURE THESE
    // ============================================
    string constant STRATEGY_NAME = "Katana vbUSDC yvUSDT Morpho LooperStrategy";

    // Role addresses
    address constant DEPOSITER = 0xC62fC9b0bb3D9c7a47A6af1ed30d7a4C74E37774;
    address constant GOVERNANCE = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;
    address deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    // Asset configuration - UPDATE THESE FOR EACH DEPLOYMENT
    // Using USDC as example
    address constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC on Ethereum
    address constant VB_TOKEN = 0x53E82ABbb12638F09d9e624578ccB666217a765e; // vbUSDC on Ethereum

    // Remote vault on Katana - UPDATE THIS
    address constant KATANA_VAULT = address(0xfF513347Aea1734324B9E7852c685221Cf899fA8); // ERC4626 vault on Katana that accepts vbToken

    function run() external {
        require(KATANA_VAULT != address(0), "Set KATANA_VAULT address");

        // Step 1: Get deployer nonce on Katana to predict remote address
        vm.createSelectFork(vm.envString("KAT_RPC_URL"));
        uint64 katanaNonce = vm.getNonce(deployer);
        address predictedRemote = computeCreateAddress(deployer, uint256(katanaNonce));

        // Get the wrapped vbToken address on Katana
        address wrappedVbToken = 0x203A662b0BD271A6ed5a60EdFbd04bFce608FD36;

        console.log("=== PRE-DEPLOYMENT INFO ===");
        console.log("Deployer:", deployer);
        console.log("Katana nonce:", katanaNonce);
        console.log("Predicted remote address:", predictedRemote);
        console.log("Wrapped vbToken on Katana:", wrappedVbToken);

        // Step 2: Deploy origin strategy on Ethereum
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast();

        KatanaStrategy originStrategy = new KatanaStrategy(
            UNDERLYING_ASSET,
            STRATEGY_NAME,
            VB_TOKEN,
            UNIFIED_BRIDGE,
            KATANA_NETWORK_ID,
            predictedRemote,
            DEPOSITER
        );

        vm.stopBroadcast();

        console.log("");
        console.log("=== ETHEREUM DEPLOYMENT ===");
        console.log("Origin Strategy:", address(originStrategy));

        // Step 3: Deploy remote strategy on Katana
        vm.createSelectFork(vm.envString("KAT_RPC_URL"));

        vm.startBroadcast();

        KatanaRemoteStrategy remoteStrategy = new KatanaRemoteStrategy(
            wrappedVbToken, // The bridged vbToken on Katana
            GOVERNANCE,
            UNIFIED_BRIDGE,
            ETHEREUM_NETWORK_ID,
            address(originStrategy),
            KATANA_VAULT
        );

        vm.stopBroadcast();


        // Verify address prediction was correct
        require(
            address(remoteStrategy) == predictedRemote,
            "Remote address mismatch! Nonce changed between forks."
        );

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Origin (Ethereum):", address(originStrategy));
        console.log("Remote (Katana):", address(remoteStrategy));
        console.log("");
    }

}
