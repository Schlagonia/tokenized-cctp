// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {KatanaStrategy} from "../src/KatanaStrategy.sol";
import {KatanaRemoteStrategy} from "../src/KatanaRemoteStrategy.sol";
import {IPolygonZkEVMBridgeV2} from "../src/interfaces/lxly/IPolygonZkEVMBridgeV2.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

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
    string constant STRATEGY_NAME = "Katana vbWBTC/yvUSDC-1 Morpho Lender Borrower";

    // Role addresses
    address constant DEPOSITER = 0x833707cAD24b95e1202A6F6E5FEB9c720f60Fc57;
    address constant GOVERNANCE = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;
    address deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    // Asset configuration - UPDATE THESE FOR EACH DEPLOYMENT
    // Using USDC as example
    address constant UNDERLYING_ASSET = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC on Ethereum
    address constant VB_TOKEN = 0x2C24B57e2CCd1f273045Af6A5f632504C432374F; // vbUSDC on Ethereum

    // Remote vault on Katana - UPDATE THIS
    address constant KATANA_VAULT = address(0x0432337365d89c0D73f1D0Cb263791F8f1B98D43); // ERC4626 vault on Katana that accepts vbToken

    function run() external {
        require(KATANA_VAULT != address(0), "Set KATANA_VAULT address");

        // Step 1: Get deployer nonce on Katana to predict remote address
        vm.createSelectFork(vm.envString("KAT_RPC_URL"));
        uint64 katanaNonce = vm.getNonce(deployer);
        address predictedRemote = computeCreateAddress(deployer, uint256(katanaNonce));

        // Resolve wrapped vbToken on Katana from live bridge mapping
        address wrappedVbToken = IPolygonZkEVMBridgeV2(UNIFIED_BRIDGE)
            .getTokenWrappedAddress(ETHEREUM_NETWORK_ID, VB_TOKEN);
        require(wrappedVbToken != address(0), "WrappedVbTokenNotFound");
        require(
            IERC4626(KATANA_VAULT).asset() == wrappedVbToken,
            "VaultAssetMismatch"
        );

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
