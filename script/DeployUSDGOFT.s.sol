// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {OFTStrategy} from "../src/oft/OFTStrategy.sol";
import {OFTRemoteStrategy} from "../src/oft/OFTRemoteStrategy.sol";
import {OFTOptions} from "../src/libraries/OFTOptions.sol";
import {IOFTStrategy} from "../src/interfaces/IOFTStrategy.sol";
import {IOFT} from "../src/interfaces/layerzero/IOFT.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title DeployUSDGOFT
/// @notice One-off, factory-less deployment of the USDG LayerZero OFT bridge
///         strategy pair: origin on Ethereum, remote on Robinhood chain. USDG
///         (and its accounting reports, as compose messages) travel over the
///         USDG OFT in both directions.
/// @dev RPC endpoints come from the ETH_RPC_URL / HOOD_RPC_URL env vars. The
///      remote is deployed by the same deployer at a simulated nonce, so the
///      origin can be constructed already pointing at it; the remote is then
///      deployed pointing back at the origin and the simulated address is
///      asserted.
contract DeployUSDGOFT is Script {
    string constant STRATEGY_NAME = "Robinhood spUSDG/USDG Morpho Looper";

    // LayerZero endpoint IDs / chain id
    uint32 constant ETHEREUM_EID = 30101;
    uint32 constant ROBINHOOD_EID = 30416;
    uint256 constant ROBINHOOD_CHAIN_ID = 4663;

    // Destination executor gas: lzReceive for token delivery (both sides) and
    // lzCompose for running the remote's reports on the origin.
    uint128 constant LZ_RECEIVE_GAS = 80_000;
    uint128 constant LZ_COMPOSE_GAS = 100_000;

    // Deployer, also management (origin) / governance (remote) / keeper.
    address constant DEPLOYER = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

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
        0xC7d60aBfa6f4D79C2C42Bf84A54795bD8c586957;

    function run() external {
        // Step 1: simulate the remote address from the deployer's Robinhood nonce.
        vm.createSelectFork(vm.envString("HOOD_RPC_URL"));
        require(
            IOFT(ROBINHOOD_USDG_OFT).token() == ROBINHOOD_USDG,
            "BadRobinhoodOFT"
        );
        require(
            IERC4626(ROBINHOOD_VAULT).asset() == ROBINHOOD_USDG,
            "VaultAssetMismatch"
        );
        uint64 remoteNonce = vm.getNonce(DEPLOYER);
        address predictedRemote = computeCreateAddress(
            DEPLOYER,
            uint256(remoteNonce)
        );

        console.log("=== PRE-DEPLOYMENT INFO ===");
        console.log("Deployer / manager:", DEPLOYER);
        console.log("Robinhood nonce:", uint256(remoteNonce));
        console.log("Simulated remote:", predictedRemote);

        // Step 2: deploy the origin on Ethereum, pointing at the simulated remote.
        // Origin sends are plain token transfers (no compose), so it carries
        // lzReceive-only options for destination delivery gas. The deployer is
        // the initial management, so it configures roles directly.
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast(DEPLOYER);

        OFTStrategy origin = new OFTStrategy(
            USDG,
            STRATEGY_NAME,
            USDG_OFT,
            ETH_ENDPOINT,
            ROBINHOOD_EID,
            ROBINHOOD_CHAIN_ID,
            predictedRemote,
            OFTOptions.receiveOptions(LZ_RECEIVE_GAS)
        );

        // Deposits are gated by the BaseHealthCheck allowed mapping; whitelist
        // the deployer here and let management setAllowed/setOpen for others.
        IOFTStrategy s = IOFTStrategy(address(origin));
        s.setPerformanceFee(0);
        s.setProfitMaxUnlockTime(0);
        s.setPerformanceFeeRecipient(DEPLOYER);
        s.setKeeper(DEPLOYER);
        s.setEmergencyAdmin(DEPLOYER);
        s.setAllowed(DEPLOYER, true);

        vm.stopBroadcast();

        console.log("");
        console.log("=== ETHEREUM DEPLOYMENT ===");
        console.log("Origin:", address(origin));

        // Step 3: deploy the remote on Robinhood, pointing back at the origin.
        // Remote reports ride the OFT as compose messages, so it carries the
        // type-3 executor options (lzReceive + lzCompose gas). The deployer is
        // governance, so it sets the keeper directly.
        vm.createSelectFork(vm.envString("HOOD_RPC_URL"));
        vm.startBroadcast(DEPLOYER);

        OFTRemoteStrategy remote = new OFTRemoteStrategy(
            ROBINHOOD_USDG,
            DEPLOYER,
            ROBINHOOD_USDG_OFT,
            ROBINHOOD_ENDPOINT,
            ETHEREUM_EID,
            address(origin),
            ROBINHOOD_VAULT,
            OFTOptions.composeOptions(LZ_RECEIVE_GAS, LZ_COMPOSE_GAS)
        );
        remote.setKeeper(DEPLOYER);

        vm.stopBroadcast();

        require(
            address(remote) == predictedRemote,
            "Remote address mismatch! Nonce changed between forks."
        );

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Origin (Ethereum):", address(origin));
        console.log("Remote (Robinhood):", address(remote));
        console.log("");
        console.log("Post-deploy:");
        console.log("  - fund both sides with ETH for LayerZero fees");
        console.log("  - origin: setAllowed(depositor) or setOpen(true)");
    }
}
