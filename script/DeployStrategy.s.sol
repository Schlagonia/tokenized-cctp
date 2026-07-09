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
    address constant MAINNET_FACTORY = 0x08Bdc770Fe79D560566fFd7E97BeccB3b230c7A1;
    address constant REMOTE_FACTORY = 0x710d72A845ad66102B60CFe4Fe2C14366208dd14;

    address constant SOURCE_STRATEGY = 0x908244B6ef0e52911a380a5454aEC0743598Fb20;

    // ============================================
    // STRATEGY PARAMETERS
    // ============================================
    string constant STRATEGY_NAME = "Base Yearn Morpho OG USDC v2";

    // Vault addresses
    address constant BASE_VAULT = 0xef417a2512C5a41f69AE4e021648b69a7CdE5D03; // Source strategy remote vault
    address constant POLYGON_VAULT = address(0);
    address constant ARB_VAULT = address(0);

    function run() external {
        deployStrategy(CCTPHelpers.BASE_DOMAIN, uint256(8453), BASE_VAULT, "BASE_RPC_URL");
        //deployStrategy(CCTPHelpers.POLYGON_DOMAIN, POLYGON_VAULT, "POLYGON_RPC_URL");
        //deployStrategy(CCTPHelpers.ARBITRUM_DOMAIN, uint256(42161), ARB_VAULT, "ARB_RPC_URL");
    }

    function deployStrategy(uint32 _remoteDomain, uint256 _remoteChainId, address _remoteVault, string memory _rpc)
        public
    {
        // Deploy on mainnet first (origin strategy)
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast();

        address strategy =
            StrategyFactory(MAINNET_FACTORY).newStrategy(STRATEGY_NAME, _remoteDomain, _remoteChainId, _remoteVault);

        vm.stopBroadcast();

        console.log("[DEPLOYED] Mainnet Strategy :", strategy);

        // Get the predicted remote address
        address predictedRemote = StrategyFactory(MAINNET_FACTORY)
            .computeRemoteCreateAddress(_remoteVault, CCTPHelpers.ETHEREUM_DOMAIN, strategy);

        console.log("[PREDICTED] Remote Strategy: ", predictedRemote);

        // Deploy remote strategy
        vm.createSelectFork(vm.envString(_rpc));
        vm.startBroadcast();

        address remoteStrategy = RemoteStrategyFactory(REMOTE_FACTORY)
            .deployRemoteStrategy(_remoteVault, CCTPHelpers.ETHEREUM_DOMAIN, strategy);

        vm.stopBroadcast();

        console.log("[DEPLOYED] Remote Strategy: ", remoteStrategy);
        require(remoteStrategy == predictedRemote, "Address mismatch!");
    }
}
