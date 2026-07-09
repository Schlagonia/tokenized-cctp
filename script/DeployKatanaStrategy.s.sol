// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {KatanaStrategy} from "../src/KatanaStrategy.sol";
import {KatanaRemoteStrategy} from "../src/KatanaRemoteStrategy.sol";
import {IPolygonZkEVMBridgeV2} from "../src/interfaces/lxly/IPolygonZkEVMBridgeV2.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";

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
    string constant STRATEGY_NAME = "Katana yvUSDC Compounder";

    address constant SOURCE_STRATEGY = 0xc5b16E7eFe1CA05714477b8edcAb4deE9b93a27C;

    // Role addresses
    address constant GOVERNANCE = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;
    address constant MANAGEMENT = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address constant PERFORMANCE_FEE_RECIPIENT = 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69;
    address constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address constant EMERGENCY_ADMIN = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    // Asset configuration cloned from SOURCE_STRATEGY
    address constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC on Ethereum
    address constant VB_TOKEN = 0x53E82ABbb12638F09d9e624578ccB666217a765e; // vbUSDC on Ethereum

    // Remote vault on Katana cloned from SOURCE_STRATEGY remote counterpart
    address constant KATANA_VAULT = 0x80c34BD3A3569E126e7055831036aa7b212cB159; // ERC4626 vault on Katana that accepts vbToken

    function run() external {
        require(KATANA_VAULT != address(0), "Set KATANA_VAULT address");

        // Step 1: Get deployer nonce on Katana to predict remote address
        vm.createSelectFork(vm.envString("KAT_RPC_URL"));
        uint64 katanaNonce = vm.getNonce(deployer);
        address predictedRemote = computeCreateAddress(deployer, uint256(katanaNonce));

        // Resolve wrapped vbToken on Katana from live bridge mapping
        address wrappedVbToken =
            IPolygonZkEVMBridgeV2(UNIFIED_BRIDGE).getTokenWrappedAddress(ETHEREUM_NETWORK_ID, VB_TOKEN);
        require(wrappedVbToken != address(0), "WrappedVbTokenNotFound");
        require(IERC4626(KATANA_VAULT).asset() == wrappedVbToken, "VaultAssetMismatch");

        console.log("=== PRE-DEPLOYMENT INFO ===");
        console.log("Deployer:", deployer);
        console.log("Katana nonce:", uint256(katanaNonce));
        console.log("Predicted remote address:", predictedRemote);
        console.log("Wrapped vbToken on Katana:", wrappedVbToken);

        // Step 2: Deploy origin strategy on Ethereum
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast(deployer);

        KatanaStrategy originStrategy = new KatanaStrategy(
            UNDERLYING_ASSET, STRATEGY_NAME, VB_TOKEN, UNIFIED_BRIDGE, KATANA_NETWORK_ID, predictedRemote
        );

        IBaseHealthCheck(address(originStrategy)).setPendingManagement(MANAGEMENT);

        vm.stopBroadcast();

        console.log("");
        console.log("=== ETHEREUM DEPLOYMENT ===");
        console.log("Origin Strategy:", address(originStrategy));

        // Step 3: Deploy remote strategy on Katana
        vm.createSelectFork(vm.envString("KAT_RPC_URL"));

        vm.startBroadcast(deployer);

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
        require(address(remoteStrategy) == predictedRemote, "Remote address mismatch! Nonce changed between forks.");

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Origin (Ethereum):", address(originStrategy));
        console.log("Remote (Katana):", address(remoteStrategy));
        console.log("");
    }
}
