// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {KatanaInventoryStrategy} from "../src/KatanaInventoryStrategy.sol";
import {KatanaRemoteInventory} from "../src/KatanaRemoteInventory.sol";
import {IPolygonZkEVMBridgeV2} from "../src/interfaces/lxly/IPolygonZkEVMBridgeV2.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";

/// @title DeployKatanaInventory
/// @notice Deployment script for the stcUSD/USDC inventory pair on Katana
/// @dev Deploys:
///   1. KatanaInventoryStrategy on Ethereum (origin)
///   2. KatanaRemoteInventory on Katana (remote inventory swapper)
contract DeployKatanaInventory is Script {
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
    string constant STRATEGY_NAME = "Katana stcUSD Inventory";

    // Role addresses
    address constant DEPOSITER = address(0); // TODO: set treasury depositor
    address constant GOVERNANCE = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;
    address constant MANAGEMENT = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    // ============================================
    // TOKEN / ORACLE / EXCHANGE ADDRESS BOOK
    // ============================================

    // Ethereum
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant STCUSD = 0x88887bE419578051FF9F4eb6C858A951921D8888;
    address constant VB_USDC = 0x53E82ABbb12638F09d9e624578ccB666217a765e;
    /// @dev stcUSD LayerZero OFT adapter (lockbox) on Ethereum
    address constant STCUSD_OFT_ADAPTER = 0x983AEAaA0d0426839158435C43725EA7F45d4137;
    /// @dev stcUSD/USDC Morpho-convention oracle on Ethereum
    address constant STCUSD_ORACLE_ETH = 0x8E3386B2f6084eB1B0988070c3d826995BD175c0;
    /// @dev Looper MetaExchange on mainnet (routes USDC <-> stcUSD via Cap)
    address constant MAINNET_EXCHANGE = address(0); // TODO: set MetaExchange

    // Katana
    /// @dev Bridged USDC (wrapped vbUSDC) on Katana
    address constant KATANA_USDC = 0x203A662b0BD271A6ed5a60EdFbd04bFce608FD36;
    /// @dev stcUSD on Katana (the token IS the OFT)
    address constant KATANA_STCUSD = STCUSD;
    /// @dev stcUSD/USDC Morpho-convention oracle on Katana
    address constant STCUSD_ORACLE_KAT = 0x832AEC697F9031709281e29ACb4fB69b1E3A6f7a;
    /// @dev MetaExchange on Katana that loopers route through
    address constant KATANA_META_EXCHANGE = address(0); // TODO: set forwarder

    /// @dev Initial discount (bps) on remote inventory quotes
    uint256 constant DISCOUNT = 50;

    function run() external {
        require(DEPOSITER != address(0), "Set DEPOSITER address");
        require(MAINNET_EXCHANGE != address(0), "Set MAINNET_EXCHANGE address");

        // Step 1: Get deployer nonce on Katana to predict remote address
        vm.createSelectFork(vm.envString("KAT_RPC_URL"));
        uint64 katanaNonce = vm.getNonce(deployer);
        address predictedRemote = computeCreateAddress(deployer, uint256(katanaNonce));

        // Sanity check the Katana-side address book against the live bridge
        address wrappedUsdc = IPolygonZkEVMBridgeV2(UNIFIED_BRIDGE).getTokenWrappedAddress(ETHEREUM_NETWORK_ID, VB_USDC);
        require(wrappedUsdc == KATANA_USDC, "KatanaUsdcMismatch");
        require(IOracle(STCUSD_ORACLE_KAT).price() > 0, "BadKatanaOracle");

        console.log("=== PRE-DEPLOYMENT INFO ===");
        console.log("Deployer:", deployer);
        console.log("Katana nonce:", uint256(katanaNonce));
        console.log("Predicted remote address:", predictedRemote);

        // Step 2: Deploy origin strategy on Ethereum
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        require(IOracle(STCUSD_ORACLE_ETH).price() > 0, "BadEthOracle");

        vm.startBroadcast(deployer);

        KatanaInventoryStrategy originStrategy = new KatanaInventoryStrategy(
            USDC,
            STRATEGY_NAME,
            STCUSD,
            STCUSD_ORACLE_ETH,
            MAINNET_EXCHANGE,
            VB_USDC,
            STCUSD_OFT_ADAPTER,
            predictedRemote
        );

        // Deposits are closed by default; whitelist the depositer.
        IBaseHealthCheck(address(originStrategy)).setAllowed(DEPOSITER, true);

        IBaseHealthCheck(address(originStrategy)).setKeeper(KEEPER);
        IBaseHealthCheck(address(originStrategy)).setPendingManagement(MANAGEMENT);

        vm.stopBroadcast();

        console.log("");
        console.log("=== ETHEREUM DEPLOYMENT ===");
        console.log("Origin Strategy:", address(originStrategy));

        // Step 3: Deploy remote inventory on Katana
        vm.createSelectFork(vm.envString("KAT_RPC_URL"));

        vm.startBroadcast(deployer);

        KatanaRemoteInventory remoteInventory = new KatanaRemoteInventory(
            KATANA_USDC,
            KATANA_STCUSD,
            STCUSD_ORACLE_KAT,
            DISCOUNT,
            GOVERNANCE,
            KATANA_STCUSD, // stcUSD itself is the OFT on Katana
            address(originStrategy)
        );

        vm.stopBroadcast();

        // Verify address prediction was correct
        require(address(remoteInventory) == predictedRemote, "Remote address mismatch! Nonce changed between forks.");

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Origin (Ethereum):", address(originStrategy));
        console.log("Remote (Katana):", address(remoteInventory));
        console.log("");
        console.log("=== POST-DEPLOY CHECKLIST (governance txs) ===");
        console.log("Ethereum:");
        console.log("  - management: acceptManagement()");
        console.log("  - management: setLossLimitRatio(...) if desired");
        console.log("  - fund origin with ETH for LayerZero fees (or send with bridge calls)");
        console.log("  - allow-list the origin/route caller on the Cap exchange venue");
        console.log("Katana (governance):");
        console.log("  - remote.setKeeper(KEEPER)");
        console.log("  - remote.setAllowedForwarder(KATANA_META_EXCHANGE)");
        console.log("  - remote.setAllowed(<looper>) per looper strategy");
        console.log("  - MetaExchange: setAllowedExchange + setContextAwareExchange(remote)");
        console.log("  - MetaExchange: setRoute(USDC->stcUSD) and (stcUSD->USDC) via remote");
        console.log("  - fund remote with ETH for LayerZero fees (or send with bridge calls)");
    }
}
