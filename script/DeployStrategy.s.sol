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
    address constant MAINNET_FACTORY = 0x90e5A75b5Ef2a88E7Dd79ca91FD9119cF1DBC1F0; // SET THIS
    address constant REMOTE_FACTORY = 0x1c11C6e81dA692F9b4D50012fD69161535acFDeD;    // SET THIS

    // ============================================
    // STRATEGY PARAMETERS
    // ============================================
    string constant STRATEGY_NAME = "Arbitrum PT sUSDai Feb 18 Morpho Looper";
    address constant DEPOSITER = 0x696d02Db93291651ED510704c9b286841d506987;

    // Vault addresses
    address BASE_VAULT; // Morpho yearn compounder
    address POLYGON_VAULT; // Fluid Compounder
    address ARB_VAULT = 0x844cB3908172C9FdE0A42Ca6e4A13Ca09A2B44bD;     // sUSDai Looper

    function run() external {
            //deployStrategy(CCTPHelpers.BASE_DOMAIN, BASE_VAULT, "BASE_RPC_URL");
            //deployStrategy(CCTPHelpers.POLYGON_DOMAIN, POLYGON_VAULT, "POLYGON_RPC_URL");
            deployStrategy(CCTPHelpers.ARBITRUM_DOMAIN, uint256(42161), ARB_VAULT, "ARB_RPC_URL");
    }

    function deployStrategy(uint32 _remoteDomain, uint256 _remoteChainId, address _remoteVault, string memory _rpc) public {
        // Deploy on mainnet first (origin strategy)
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast();

        address strategy = StrategyFactory(MAINNET_FACTORY).newStrategy(
            STRATEGY_NAME,
            _remoteDomain,
            _remoteChainId,
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