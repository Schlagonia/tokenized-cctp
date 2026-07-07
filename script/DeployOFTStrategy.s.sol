// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {OFTStrategyFactory} from "../src/OFTStrategyFactory.sol";
import {IOFT} from "../src/interfaces/layerzero/IOFT.sol";

/// @title DeployOFTStrategy
/// @notice Deploys the USDG OFT bridge strategy via OFTStrategyFactory: origin
///         on Ethereum, remote on Robinhood chain. USDG bridges via its
///         LayerZero OFT; reports ride the same OFT as compose messages. The
///         factory computes and sets the LayerZero executor options.
contract DeployOFTStrategy is Script {
    string constant STRATEGY_NAME = "USDG Robinhood OFT Strategy";

    uint32 constant ETHEREUM_EID = 30101;
    uint32 constant ROBINHOOD_EID = 30416;
    uint256 constant ROBINHOOD_CHAIN_ID = 4663;

    // Role addresses
    address constant DEPOSITER = address(0); // TODO: set treasury depositor
    address constant GOVERNANCE = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;
    address constant MANAGEMENT = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address constant PERF_RECIPIENT =
        0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69;
    address deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    // Ethereum
    address constant USDG = 0xe343167631d89B6Ffc58B88d6b7fB0228795491D;
    address constant USDG_OFT = 0x147BdE4F997f0d4C7544ED0C55eAcf1E5E6bf9c4;
    address constant ETH_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    // Robinhood (verified on-chain)
    address constant ROBINHOOD_USDG =
        0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168; // USDG token (vault asset)
    address constant ROBINHOOD_USDG_OFT =
        0x0d54755f5106BfdB43f7a35f5D49a23F940628d1; // OFT adapter
    address constant ROBINHOOD_ENDPOINT =
        0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    address constant ROBINHOOD_VAULT =
        0xde770c84FE66E063336b31737cFE9790f18c4087; // spUSDG ERC4626

    function run() external {
        require(DEPOSITER != address(0), "Set DEPOSITER");
        require(
            IOFT(ROBINHOOD_USDG_OFT).token() == ROBINHOOD_USDG,
            "BadRobinhoodOFT"
        );

        // Deploy the factory on Robinhood and predict the remote address
        // (the factory's first CREATE is the remote strategy, nonce 1).
        vm.createSelectFork(vm.envString("HOOD_RPC_URL"));
        vm.startBroadcast(deployer);
        OFTStrategyFactory remoteFactory = new OFTStrategyFactory(
            MANAGEMENT,
            PERF_RECIPIENT,
            KEEPER,
            MANAGEMENT
        );
        vm.stopBroadcast();
        address predictedRemote = computeCreateAddress(
            address(remoteFactory),
            1
        );
        console.log("Remote factory:", address(remoteFactory));
        console.log("Predicted remote:", predictedRemote);

        // Deploy the origin via a factory on Ethereum
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast(deployer);
        OFTStrategyFactory originFactory = new OFTStrategyFactory(
            MANAGEMENT,
            PERF_RECIPIENT,
            KEEPER,
            MANAGEMENT
        );
        address origin = originFactory.newOrigin(
            USDG,
            STRATEGY_NAME,
            USDG_OFT,
            ETH_ENDPOINT,
            ROBINHOOD_EID,
            ROBINHOOD_CHAIN_ID,
            predictedRemote,
            DEPOSITER
        );
        vm.stopBroadcast();
        console.log("Origin (Ethereum):", origin);

        // Deploy the remote via the Robinhood factory
        vm.createSelectFork(vm.envString("HOOD_RPC_URL"));
        vm.startBroadcast(deployer);
        address remote = remoteFactory.newRemote(
            ROBINHOOD_USDG,
            GOVERNANCE,
            ROBINHOOD_USDG_OFT,
            ROBINHOOD_ENDPOINT,
            ETHEREUM_EID,
            origin,
            ROBINHOOD_VAULT
        );
        vm.stopBroadcast();

        require(remote == predictedRemote, "Remote address mismatch");
        console.log("Remote (Robinhood):", remote);
        console.log("");
        console.log("Post-deploy:");
        console.log("  - lzOptions were set by the factory (compose gas)");
        console.log("  - origin: acceptManagement");
        console.log("  - remote: governance.setKeeper(KEEPER)");
        console.log("  - fund both sides with ETH for LayerZero fees");
    }
}
