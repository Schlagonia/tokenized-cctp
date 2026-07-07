// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {WstETHKatanaInventoryStrategy} from "../src/WstETHKatanaInventoryStrategy.sol";
import {KatanaRemoteInventory} from "../src/KatanaRemoteInventory.sol";
import {WstETHOracle} from "../src/periphery/WstETHOracle.sol";
import {IPolygonZkEVMBridgeV2} from "../src/interfaces/lxly/IPolygonZkEVMBridgeV2.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";

/// @title DeployWstETHKatanaInventory
/// @notice Deployment script for the wstETH/WETH inventory pair on Katana
/// @dev Deploys:
///   1. WstETHOracle on Ethereum (rate-based, 1e36 Morpho convention)
///   2. WstETHKatanaInventoryStrategy on Ethereum (origin)
///   3. KatanaRemoteInventory on Katana (remote inventory swapper)
contract DeployWstETHKatanaInventory is Script {
    address constant UNIFIED_BRIDGE = 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;

    uint32 constant ETHEREUM_NETWORK_ID = 0;

    string constant STRATEGY_NAME = "Katana wstETH Inventory";

    // Role addresses
    address constant DEPOSITER = address(0); // TODO: set treasury depositor
    address constant GOVERNANCE = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;
    address constant MANAGEMENT = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    // Ethereum
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    /// @dev Looper MetaExchange on mainnet (routes WETH <-> wstETH)
    address constant MAINNET_EXCHANGE = address(0); // TODO: set MetaExchange

    // Katana (LxLy-wrapped representations, verified on-chain)
    address constant KATANA_WETH = 0xEE7D8BCFb72bC1880D0Cf19822eB0A2e6577aB62;
    address constant KATANA_WSTETH = 0x7Fb4D0f51544F24F385a421Db6e7D4fC71Ad8e5C;
    /// @dev wstETH/WETH Morpho-convention oracle on Katana
    address constant WSTETH_ORACLE_KAT = address(0); // TODO: set Katana oracle

    /// @dev Initial discount (bps) on remote inventory quotes
    uint256 constant DISCOUNT = 50;

    function run() external {
        require(DEPOSITER != address(0), "Set DEPOSITER address");
        require(MAINNET_EXCHANGE != address(0), "Set MAINNET_EXCHANGE address");
        require(WSTETH_ORACLE_KAT != address(0), "Set WSTETH_ORACLE_KAT");

        // Step 1: Get deployer nonce on Katana to predict remote address
        vm.createSelectFork(vm.envString("KAT_RPC_URL"));
        uint64 katanaNonce = vm.getNonce(deployer);
        address predictedRemote = computeCreateAddress(deployer, uint256(katanaNonce));

        // Sanity check the Katana-side address book against the live bridge
        address wrappedWsteth =
            IPolygonZkEVMBridgeV2(UNIFIED_BRIDGE).getTokenWrappedAddress(ETHEREUM_NETWORK_ID, WSTETH);
        require(wrappedWsteth == KATANA_WSTETH, "KatanaWstethMismatch");
        require(IOracle(WSTETH_ORACLE_KAT).price() > 0, "BadKatanaOracle");

        console.log("=== PRE-DEPLOYMENT INFO ===");
        console.log("Deployer:", deployer);
        console.log("Katana nonce:", uint256(katanaNonce));
        console.log("Predicted remote address:", predictedRemote);

        // Step 2: Deploy oracle + origin strategy on Ethereum
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        vm.startBroadcast(deployer);

        WstETHOracle wstEthOracle = new WstETHOracle();
        require(wstEthOracle.price() > 0, "BadEthOracle");

        WstETHKatanaInventoryStrategy originStrategy =
            new WstETHKatanaInventoryStrategy(STRATEGY_NAME, address(wstEthOracle), MAINNET_EXCHANGE, predictedRemote);

        // Deposits are closed by default; whitelist the depositer.
        IBaseHealthCheck(address(originStrategy)).setAllowed(DEPOSITER, true);

        IBaseHealthCheck(address(originStrategy)).setKeeper(KEEPER);
        IBaseHealthCheck(address(originStrategy)).setPendingManagement(MANAGEMENT);

        vm.stopBroadcast();

        console.log("");
        console.log("=== ETHEREUM DEPLOYMENT ===");
        console.log("WstETHOracle:", address(wstEthOracle));
        console.log("Origin Strategy:", address(originStrategy));

        // Step 3: Deploy remote inventory on Katana
        vm.createSelectFork(vm.envString("KAT_RPC_URL"));

        vm.startBroadcast(deployer);

        KatanaRemoteInventory remoteInventory = new KatanaRemoteInventory(
            KATANA_WETH,
            KATANA_WSTETH,
            WSTETH_ORACLE_KAT,
            DISCOUNT,
            GOVERNANCE,
            address(0), // no OFT: wstETH bridges home via LxLy
            address(originStrategy)
        );

        vm.stopBroadcast();

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
        console.log("  - allow-list the origin/route caller on the exchange venue");
        console.log("Katana (governance):");
        console.log("  - remote.setKeeper(KEEPER)");
        console.log("  - remote.setAllowedForwarder(<Katana MetaExchange>)");
        console.log("  - remote.setAllowed(<looper>) per looper strategy");
        console.log("  - MetaExchange: setAllowedExchange + setContextAwareExchange(remote)");
        console.log("  - MetaExchange: setRoute(WETH->wstETH) and (wstETH->WETH) via remote");
    }
}
