// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {OFTStrategy} from "../src/OFTStrategy.sol";
import {OFTRemoteStrategy} from "../src/OFTRemoteStrategy.sol";
import {IOFT} from "../src/interfaces/layerzero/IOFT.sol";
import {IBaseHealthCheck} from "@periphery/Bases/HealthCheck/IBaseHealthCheck.sol";

/// @title DeployOFTStrategy
/// @notice Deploys the USDG OFT bridge strategy: origin on Ethereum, remote on
///         Robinhood chain. USDG bridges via its LayerZero OFT; reports travel
///         back over LayerZero messaging.
contract DeployOFTStrategy is Script {
    string constant STRATEGY_NAME = "USDG Robinhood OFT Strategy";

    // LayerZero endpoint IDs
    uint32 constant ETHEREUM_EID = 30101;
    uint32 constant ROBINHOOD_EID = 30416;
    uint256 constant ROBINHOOD_CHAIN_ID = 0; // TODO: set Robinhood chain id

    // Role addresses
    address constant DEPOSITER = address(0); // TODO: set treasury depositor
    address constant GOVERNANCE = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;
    address constant MANAGEMENT = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    // Ethereum
    address constant USDG = 0xe343167631d89B6Ffc58B88d6b7fB0228795491D;
    address constant USDG_OFT = 0x147BdE4F997f0d4C7544ED0C55eAcf1E5E6bf9c4;
    address constant ETH_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    // Robinhood (verified on-chain 2026-07-06)
    address constant ROBINHOOD_USDG =
        0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168; // USDG token (vault asset)
    address constant ROBINHOOD_USDG_OFT =
        0x0d54755f5106BfdB43f7a35f5D49a23F940628d1; // OFT adapter, peered to mainnet
    address constant ROBINHOOD_ENDPOINT =
        0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    address constant ROBINHOOD_VAULT =
        0xde770c84FE66E063336b31737cFE9790f18c4087; // spUSDG ERC4626

    function run() external {
        require(DEPOSITER != address(0), "Set DEPOSITER");

        // Predict the remote address via deployer nonce on Robinhood
        vm.createSelectFork(vm.envString("HOOD_RPC_URL"));
        uint64 remoteNonce = vm.getNonce(deployer);
        address predictedRemote = computeCreateAddress(
            deployer,
            uint256(remoteNonce)
        );
        require(
            IOFT(ROBINHOOD_USDG_OFT).token() == ROBINHOOD_USDG,
            "BadRobinhoodOFT"
        );

        console.log("Predicted remote:", predictedRemote);

        // Deploy origin on Ethereum
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast(deployer);

        OFTStrategy origin = new OFTStrategy(
            USDG,
            STRATEGY_NAME,
            USDG_OFT,
            ETH_ENDPOINT,
            ROBINHOOD_EID,
            ROBINHOOD_CHAIN_ID,
            predictedRemote,
            DEPOSITER,
            MANAGEMENT // delegate (configures DVNs/libraries)
        );

        IBaseHealthCheck(address(origin)).setKeeper(KEEPER);
        IBaseHealthCheck(address(origin)).setPendingManagement(MANAGEMENT);

        vm.stopBroadcast();

        console.log("Origin (Ethereum):", address(origin));

        // Deploy remote on Robinhood
        vm.createSelectFork(vm.envString("HOOD_RPC_URL"));
        vm.startBroadcast(deployer);

        OFTRemoteStrategy remote = new OFTRemoteStrategy(
            ROBINHOOD_USDG,
            GOVERNANCE,
            ROBINHOOD_USDG_OFT,
            ROBINHOOD_ENDPOINT,
            ETHEREUM_EID,
            address(origin),
            ROBINHOOD_VAULT,
            GOVERNANCE // delegate
        );

        vm.stopBroadcast();

        require(address(remote) == predictedRemote, "Remote address mismatch");

        console.log("Remote (Robinhood):", address(remote));
        console.log("");
        console.log("Post-deploy (LayerZero OApp wiring, via delegates):");
        console.log("  - both sides: configure send/receive libraries + DVNs");
        console.log("  - both sides: set enforced options, or setLzOptions");
        console.log("  - origin: acceptManagement, setAllowed depositor");
        console.log("  - fund both sides with ETH for LayerZero fees");
    }
}
