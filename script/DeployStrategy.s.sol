// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {StrategyFactory} from "../src/StrategyFactory.sol";
import {RemoteStrategyFactory} from "../src/RemoteStrategyFactory.sol";
import {CCTPHelpers} from "../src/libraries/CCTPHelpers.sol";

contract DeployStrategy is Script {

    // ============================================
    // SET THESE FACTORY ADDRESSES AFTER DEPLOYING FACTORIES
    // ============================================
    address constant MAINNET_FACTORY = 0x6F8613A9885E45f3f41145e86961Fee9A074c588; // SET THIS
    address constant REMOTE_FACTORY = 0xF2D7217ac9D67DB3c6ec921124E30a94a34db74e;    // SET THIS

    // ============================================
    // STRATEGY PARAMETERS
    // ============================================
    string constant STRATEGY_NAME = "USDC Test CCTP";
    address constant DEPOSITER = 0xC62fC9b0bb3D9c7a47A6af1ed30d7a4C74E37774;

    // Vault addresses
    address constant BASE_VAULT = 0xF115C134c23C7A05FBD489A8bE3116EbF54B0D9f; // Morpho yearn compounder
    address constant POLYGON_VAULT = 0xD811a47cfD17355F47ac49Be02c4744A926dd16B; // Fluid Compounder
    address constant ARB_VAULT = 0x2c28c7d3B482E9BCEceff1a57F9ccEa490E9Daa1;     // Fluid Compounder

    function run() external {
            //deployStrategy(CCTPHelpers.BASE_DOMAIN, BASE_VAULT, "BASE_RPC_URL");
            //deployStrategy(CCTPHelpers.POLYGON_DOMAIN, POLYGON_VAULT, "POLYGON_RPC_URL");
            deployStrategy(CCTPHelpers.ARBITRUM_DOMAIN, ARB_VAULT, "ARB_RPC_URL");
    }

    function deployStrategy(uint32 _remoteDomain, address _remoteVault, string memory _rpc) public {
        // Deploy on mainnet first (origin strategy)
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast();

        address strategy = StrategyFactory(MAINNET_FACTORY).newStrategy(
            STRATEGY_NAME,
            _remoteDomain,
            _remoteVault,
            DEPOSITER
        );

        vm.stopBroadcast();

        console.log("[DEPLOYED] Mainnet Strategy :", strategy);

        // Get the predicted remote address
        address predictedRemote = StrategyFactory(MAINNET_FACTORY).computeRemoteCreateAddress(
            _remoteVault,
            CCTPHelpers.ETHEREUM_DOMAIN,
            strategy
        );

        console.log("[PREDICTED] Remote Strategy: ", predictedRemote);

        // Deploy remote strategy on Base
        vm.createSelectFork(vm.envString(_rpc));
        vm.startBroadcast();

        address remoteStrategy = RemoteStrategyFactory(REMOTE_FACTORY).deployRemoteStrategy(
            _remoteVault,
            CCTPHelpers.ETHEREUM_DOMAIN,
            strategy
        );

        vm.stopBroadcast();

        console.log("[DEPLOYED] Remote Strategy: ", remoteStrategy);
        require(remoteStrategy == predictedRemote, "Address mismatch!");
    }

}