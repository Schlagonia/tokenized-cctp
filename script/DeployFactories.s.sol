// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {StrategyFactory} from "../src/StrategyFactory.sol";
import {RemoteStrategyFactory} from "../src/RemoteStrategyFactory.sol";
import {CCTPHelpers} from "../src/libraries/CCTPHelpers.sol";
import {ICreateX} from "../src/interfaces/ICreateX.sol";
import {console2} from "forge-std/console2.sol";

contract DeployFactories is Script {

    ICreateX public immutable createX =
        ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    address public constant deployer = 0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;

    function run() external {
        // Simple configuration - using deployer for all admin roles
        address management = deployer;
        address performanceFeeRecipient = deployer;
        address keeper = deployer;
        address emergencyAdmin = deployer;
        address governance = deployer;
        
        bytes32 salt = bytes32(abi.encode("remote factory test"));

        console.log("\n=================================");
        console.log("Deploying Factories");
        console.log("=================================\n");

        // Deploy StrategyFactory on Ethereum mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.startBroadcast();

        bytes memory creationCode = abi.encodePacked(
            type(RemoteStrategyFactory).creationCode,
            abi.encode(
                management,
                CCTPHelpers.ETHEREUM_USDC,
                CCTPHelpers.TOKEN_MESSENGER,
                CCTPHelpers.MESSAGE_TRANSMITTER
            )
        );

        address _remoteFactory = ICreateX(createX).deployCreate3(
            salt,
            creationCode
        );

        console.log("[COMPUTED] Ethereum RemoteStrategyFactory:", address(_remoteFactory));

        StrategyFactory strategyFactory = new StrategyFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin,
            CCTPHelpers.ETHEREUM_USDC,
            CCTPHelpers.TOKEN_MESSENGER,
            CCTPHelpers.MESSAGE_TRANSMITTER,
            _remoteFactory
        );

        vm.stopBroadcast();

        console.log("[DEPLOYED] Ethereum StrategyFactory:", address(strategyFactory));

        // Deploy RemoteStrategyFactory on Base
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));
        vm.startBroadcast();

        creationCode = abi.encodePacked(
            type(RemoteStrategyFactory).creationCode,
            abi.encode(
                governance,
                CCTPHelpers.BASE_USDC,
                CCTPHelpers.TOKEN_MESSENGER,
                CCTPHelpers.MESSAGE_TRANSMITTER
            )
        );

        address baseFactory = ICreateX(createX).deployCreate3(
            salt,
            creationCode
        );

        vm.stopBroadcast();

        console.log("[DEPLOYED] Base RemoteStrategyFactory:", address(baseFactory));

        // Deploy RemoteStrategyFactory on Polygon
        vm.createSelectFork(vm.envString("POLYGON_RPC_URL"));
        vm.startBroadcast();

        creationCode = abi.encodePacked(
            type(RemoteStrategyFactory).creationCode,
            abi.encode(
                governance,
                CCTPHelpers.POLYGON_USDC,
                CCTPHelpers.TOKEN_MESSENGER,
                CCTPHelpers.MESSAGE_TRANSMITTER
            )
        );

        address polygonFactory = ICreateX(createX).deployCreate3(
            salt,
            creationCode
        );

        vm.stopBroadcast();

        console.log("[DEPLOYED] Polygon RemoteStrategyFactory:", address(polygonFactory));

        // Deploy RemoteStrategyFactory on Arbitrum
        vm.createSelectFork(vm.envString("ARB_RPC_URL"));
        vm.startBroadcast();

        creationCode = abi.encodePacked(
            type(RemoteStrategyFactory).creationCode,
            abi.encode(
                governance,
                CCTPHelpers.ARBITRUM_USDC,
                CCTPHelpers.TOKEN_MESSENGER,
                CCTPHelpers.MESSAGE_TRANSMITTER
            )
        );

        address arbFactory = ICreateX(createX).deployCreate3(
            salt,
            creationCode
        );

        vm.stopBroadcast();

        console.log("[DEPLOYED] Arbitrum RemoteStrategyFactory:", address(arbFactory));

        // Summary
        console.log("\n=================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("=================================");
        console.log("Ethereum StrategyFactory:", address(strategyFactory));
        console.log("Base RemoteStrategyFactory:", address(baseFactory));
        console.log("Polygon RemoteStrategyFactory:", address(polygonFactory));
        console.log("Arbitrum RemoteStrategyFactory:", address(arbFactory));
        console.log("=================================\n");
    }
}