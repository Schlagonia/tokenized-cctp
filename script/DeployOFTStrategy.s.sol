// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {OFTStrategyFactory} from "../src/OFTStrategyFactory.sol";
import {OFTRemoteStrategyFactory} from "../src/OFTRemoteStrategyFactory.sol";
import {IOFT} from "../src/interfaces/layerzero/IOFT.sol";

/// @title DeployOFTStrategy
/// @notice Deploys the USDG OFT bridge strategy via the factory pair (mirrors
///         the CCTP factory flow): the remote factory is deployed at the same
///         address on both chains so the origin factory can precompute the
///         remote counterpart. USDG bridges via its LayerZero OFT; reports ride
///         the same OFT as compose messages.
/// @dev For a real deploy, deploy OFTRemoteStrategyFactory deterministically
///      (CreateX) so it lands at the same address on Ethereum and Robinhood,
///      then pass that address as the origin factory's REMOTE_FACTORY.
contract DeployOFTStrategy is Script {
    string constant STRATEGY_NAME = "USDG Robinhood OFT Strategy";

    uint32 constant ETHEREUM_EID = 30101;
    uint32 constant ROBINHOOD_EID = 30416;
    uint256 constant ROBINHOOD_CHAIN_ID = 4663;

    address constant DEPOSITER = address(0); // TODO: set treasury depositor
    address constant GOVERNANCE = 0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6;
    address constant MANAGEMENT = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address constant PERF_RECIPIENT =
        0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69;

    // Ethereum
    address constant USDG = 0xe343167631d89B6Ffc58B88d6b7fB0228795491D;
    address constant USDG_OFT = 0x147BdE4F997f0d4C7544ED0C55eAcf1E5E6bf9c4;
    address constant ETH_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    // Robinhood
    address constant ROBINHOOD_USDG =
        0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant ROBINHOOD_USDG_OFT =
        0x0d54755f5106BfdB43f7a35f5D49a23F940628d1;
    address constant ROBINHOOD_ENDPOINT =
        0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    address constant ROBINHOOD_VAULT =
        0xde770c84FE66E063336b31737cFE9790f18c4087;

    function run() external {
        require(DEPOSITER != address(0), "Set DEPOSITER");
        require(
            IOFT(ROBINHOOD_USDG_OFT).token() == ROBINHOOD_USDG,
            "BadRobinhoodOFT"
        );

        // Deploy the remote factory on Robinhood (deploy deterministically via
        // CreateX in production so its address matches on Ethereum).
        vm.createSelectFork(vm.envString("HOOD_RPC_URL"));
        vm.broadcast();
        OFTRemoteStrategyFactory remoteFactory = new OFTRemoteStrategyFactory(
            GOVERNANCE,
            ROBINHOOD_USDG,
            ROBINHOOD_USDG_OFT,
            ROBINHOOD_ENDPOINT,
            80_000,
            100_000
        );
        console.log("Remote factory:", address(remoteFactory));

        // Deploy the origin factory + strategy on Ethereum. The origin factory
        // precomputes the remote counterpart via the remote factory address.
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast();
        OFTStrategyFactory originFactory = new OFTStrategyFactory(
            MANAGEMENT,
            PERF_RECIPIENT,
            KEEPER,
            MANAGEMENT,
            address(remoteFactory),
            USDG,
            USDG_OFT,
            ETH_ENDPOINT,
            ETHEREUM_EID
        );
        address origin = originFactory.newStrategy(
            STRATEGY_NAME,
            ROBINHOOD_EID,
            ROBINHOOD_CHAIN_ID,
            ROBINHOOD_VAULT,
            DEPOSITER
        );
        vm.stopBroadcast();
        console.log("Origin (Ethereum):", origin);

        // Deploy the remote deterministically to the precomputed address.
        vm.createSelectFork(vm.envString("HOOD_RPC_URL"));
        vm.broadcast();
        address remote = remoteFactory.deployRemoteStrategy(
            ROBINHOOD_VAULT,
            ETHEREUM_EID,
            origin
        );

        require(
            remote ==
                originFactory.computeRemoteCreateAddress(
                    ROBINHOOD_VAULT,
                    origin
                ),
            "Remote address mismatch"
        );
        console.log("Remote (Robinhood):", remote);
        console.log("");
        console.log("Post-deploy:");
        console.log("  - lzOptions set by the factory (compose gas)");
        console.log("  - origin: acceptManagement");
        console.log("  - remote: governance.setKeeper(KEEPER)");
        console.log("  - fund both sides with ETH for LayerZero fees");
    }
}
