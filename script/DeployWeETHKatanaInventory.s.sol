// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {WeETHKatanaInventoryStrategy} from "../src/WeETHKatanaInventoryStrategy.sol";
import {KatanaRemoteInventory} from "../src/KatanaRemoteInventory.sol";
import {WeETHOracle} from "../src/periphery/WeETHOracle.sol";
import {IPolygonZkEVMBridgeV2} from "../src/interfaces/lxly/IPolygonZkEVMBridgeV2.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";

/// @title DeployWeETHKatanaInventory
/// @notice Deployment script for the weETH/WETH inventory pair on Katana.
/// @dev Both WETH (via vbETH) and weETH bridge over the LxLy/Agglayer
///      canonical bridge — weETH on Katana is the LxLy-wrapped token, not a
///      LayerZero OFT. Collateral is redeemed on mainnet through the EtherFi
///      withdrawal flow.
contract DeployWeETHKatanaInventory is Script {
    address constant UNIFIED_BRIDGE = 0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;
    uint32 constant ETHEREUM_NETWORK_ID = 0;

    string constant STRATEGY_NAME = "Katana weETH Inventory";

    // Role addresses
    address constant DEPOSITER = address(0); // TODO: set treasury depositor
    address constant GOVERNANCE = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;
    address constant MANAGEMENT = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    // Ethereum
    address constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    /// @dev Looper MetaExchange on mainnet (routes WETH <-> weETH)
    address constant MAINNET_EXCHANGE = address(0); // TODO: set MetaExchange

    // Katana (LxLy-wrapped, verified on-chain)
    address constant KATANA_WETH = 0xEE7D8BCFb72bC1880D0Cf19822eB0A2e6577aB62;
    address constant KATANA_WEETH = 0x9893989433e7a383Cb313953e4c2365107dc19a7;
    /// @dev weETH/WETH Morpho-convention oracle on Katana
    address constant WEETH_ORACLE_KAT = address(0); // TODO: set Katana oracle

    uint256 constant DISCOUNT = 50;

    function run() external {
        require(DEPOSITER != address(0), "Set DEPOSITER");
        require(MAINNET_EXCHANGE != address(0), "Set MAINNET_EXCHANGE");
        require(WEETH_ORACLE_KAT != address(0), "Set WEETH_ORACLE_KAT");

        // Predict remote address via deployer nonce on Katana
        vm.createSelectFork(vm.envString("KAT_RPC_URL"));
        uint64 katanaNonce = vm.getNonce(deployer);
        address predictedRemote = computeCreateAddress(deployer, uint256(katanaNonce));

        // Sanity check the Katana wrapped weETH against the live bridge
        address wrappedWeeth = IPolygonZkEVMBridgeV2(UNIFIED_BRIDGE).getTokenWrappedAddress(ETHEREUM_NETWORK_ID, WEETH);
        require(wrappedWeeth == KATANA_WEETH, "KatanaWeethMismatch");
        require(IOracle(WEETH_ORACLE_KAT).price() > 0, "BadKatanaOracle");

        console.log("Predicted remote:", predictedRemote);

        // Deploy oracle + origin strategy on Ethereum
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast(deployer);

        WeETHOracle weEthOracle = new WeETHOracle();
        require(weEthOracle.price() > 0, "BadEthOracle");

        WeETHKatanaInventoryStrategy originStrategy =
            new WeETHKatanaInventoryStrategy(STRATEGY_NAME, address(weEthOracle), MAINNET_EXCHANGE, predictedRemote);

        IBaseHealthCheck(address(originStrategy)).setAllowed(DEPOSITER, true);
        IBaseHealthCheck(address(originStrategy)).setKeeper(KEEPER);
        IBaseHealthCheck(address(originStrategy)).setPendingManagement(MANAGEMENT);

        vm.stopBroadcast();

        console.log("WeETHOracle:", address(weEthOracle));
        console.log("Origin Strategy:", address(originStrategy));

        // Deploy remote inventory on Katana (weETH via LxLy, no OFT)
        vm.createSelectFork(vm.envString("KAT_RPC_URL"));
        vm.startBroadcast(deployer);

        KatanaRemoteInventory remoteInventory = new KatanaRemoteInventory(
            KATANA_WETH,
            KATANA_WEETH,
            WEETH_ORACLE_KAT,
            DISCOUNT,
            GOVERNANCE,
            address(0), // no OFT: weETH bridges home via LxLy
            address(originStrategy)
        );

        vm.stopBroadcast();

        require(address(remoteInventory) == predictedRemote, "Remote address mismatch");

        console.log("Remote (Katana):", address(remoteInventory));
        console.log("");
        console.log("Post-deploy: whitelist forwarder/looper on remote, wire");
        console.log("MetaExchange routes, fund origin with ETH for LZ (none");
        console.log("needed for the LxLy bridge legs).");
    }
}
