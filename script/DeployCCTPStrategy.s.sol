// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {CCTPStrategy as Strategy} from "../src/CCTPStrategy.sol";
import {CCTPRemoteStrategy as RemoteStrategy} from "../src/CCTPRemoteStrategy.sol";
import {StrategyFactory} from "../src/StrategyFactory.sol";
import {CCTPHelpers} from "../src/libraries/CCTPHelpers.sol";

contract DeployStrategy is Script {
    // Configuration
    string public strategyName = "CCTP USDC Yield Strategy";
    
    // Addresses will be set based on chain
    address public usdc;
    address public tokenMessenger;
    address public messageTransmitter;
    uint32 public chainDomain;
    
    function run() external {
        // Get chain ID and set configuration
        uint256 chainId = block.chainid;
        _setChainConfig(chainId);
        
        // Get deployment private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying CCTP Strategy");
        console.log("Chain ID:", chainId);
        console.log("Deployer:", deployer);
        console.log("USDC:", usdc);
        
        vm.startBroadcast(deployerPrivateKey);
        
        /** / Deploy strategy
        Strategy strategy = new Strategy(
            usdc,
            strategyName,
            tokenMessenger,
            messageTransmitter,
            
        );
        
        console.log("Strategy deployed at:", address(strategy));
        
        // Configure initial parameters
        strategy.setBridgeLimits(
            100 * 10**6,      // Min: 100 USDC
            10_000_000 * 10**6 // Max: 10M USDC
        );
        
        // Set health check parameters
        strategy.setProfitLimitRatio(10000); // 100% profit limit
        strategy.setLossLimitRatio(500);     // 5% loss limit
        
        vm.stopBroadcast();
        
        // Log deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("Strategy:", address(strategy));
        console.log("Asset (USDC):", usdc);
        console.log("Chain Domain:", chainDomain);
        console.log("Token Messenger:", tokenMessenger);
        console.log("Message Transmitter:", messageTransmitter);
        console.log("\nNext steps:");
        console.log("1. Deploy RemoteStrategy on destination chain");
        console.log("2. Call strategy.setDestinationConfig() with handler address");
        console.log("3. Configure keeper for cross-chain operations");
        */
    }
    
    function _setChainConfig(uint256 chainId) internal {
        if (chainId == 1) {
            // Ethereum Mainnet
            chainDomain = CCTPHelpers.ETHEREUM_DOMAIN;
            usdc = CCTPHelpers.ETHEREUM_USDC;
            tokenMessenger = CCTPHelpers.ETHEREUM_TOKEN_MESSENGER;
            messageTransmitter = CCTPHelpers.ETHEREUM_MESSAGE_TRANSMITTER;
        } else if (chainId == 42161) {
            // Arbitrum
            chainDomain = CCTPHelpers.ARBITRUM_DOMAIN;
            usdc = CCTPHelpers.ARBITRUM_USDC;
            tokenMessenger = CCTPHelpers.ARBITRUM_TOKEN_MESSENGER;
            messageTransmitter = CCTPHelpers.ARBITRUM_MESSAGE_TRANSMITTER;
        } else if (chainId == 10) {
            // Optimism
            chainDomain = CCTPHelpers.OPTIMISM_DOMAIN;
            usdc = CCTPHelpers.OPTIMISM_USDC;
            tokenMessenger = CCTPHelpers.OPTIMISM_TOKEN_MESSENGER;
            messageTransmitter = CCTPHelpers.OPTIMISM_MESSAGE_TRANSMITTER;
        } else if (chainId == 8453) {
            // Base
            chainDomain = CCTPHelpers.BASE_DOMAIN;
            usdc = CCTPHelpers.BASE_USDC;
            tokenMessenger = CCTPHelpers.BASE_TOKEN_MESSENGER;
            messageTransmitter = CCTPHelpers.BASE_MESSAGE_TRANSMITTER;
        } else if (chainId == 137) {
            // Polygon
            chainDomain = CCTPHelpers.POLYGON_DOMAIN;
            usdc = CCTPHelpers.POLYGON_USDC;
            tokenMessenger = CCTPHelpers.POLYGON_TOKEN_MESSENGER;
            messageTransmitter = CCTPHelpers.POLYGON_MESSAGE_TRANSMITTER;
        } else if (chainId == 43114) {
            // Avalanche
            chainDomain = CCTPHelpers.AVALANCHE_DOMAIN;
            usdc = CCTPHelpers.AVALANCHE_USDC;
            tokenMessenger = CCTPHelpers.AVALANCHE_TOKEN_MESSENGER;
            messageTransmitter = CCTPHelpers.AVALANCHE_MESSAGE_TRANSMITTER;
        } else {
            revert("Unsupported chain");
        }
    }
}

contract DeployCCTPHandler is Script {
    function run() external {
        // Configuration - set these based on your deployment
        address destinationVault = vm.envAddress("DESTINATION_VAULT");
        address sourceStrategy = vm.envAddress("SOURCE_STRATEGY");
        uint32 sourceDomain = uint32(vm.envUint("SOURCE_DOMAIN"));
        
        // Get chain ID and set configuration
        uint256 chainId = block.chainid;
        
        // Get CCTP contracts for this chain
        (address usdc, address tokenMessenger, address messageTransmitter, ) = _getChainConfig(chainId);
        
        // Get deployment private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying CCTP Handler");
        console.log("Chain ID:", chainId);
        console.log("Deployer:", deployer);
        console.log("Destination Vault:", destinationVault);
        console.log("Source Strategy:", sourceStrategy);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy handler
        /** 
        RemoteStrategy handler = new RemoteStrategy(
            usdc,
            destinationVault,
            sourceStrategy,
            tokenMessenger,
            messageTransmitter,
            sourceDomain
        );
        
        console.log("Handler deployed at:", address(handler));
        
        vm.stopBroadcast();
        
        // Log deployment info
        console.log("\n=== Handler Deployment Summary ===");
        console.log("Handler:", address(handler));
        console.log("USDC:", usdc);
        console.log("Destination Vault:", destinationVault);
        console.log("Source Strategy:", sourceStrategy);
        console.log("Source Domain:", sourceDomain);
        console.log("\nNext steps:");
        console.log("1. Call sourceStrategy.setDestinationConfig() with this handler address");
        console.log("2. Set up keeper to monitor and relay messages");
        */
    }
    
    function _getChainConfig(uint256 chainId) internal pure returns (
        address usdc,
        address tokenMessenger,
        address messageTransmitter,
        uint32 chainDomain
    ) {
        if (chainId == 1) {
            return (
                CCTPHelpers.ETHEREUM_USDC,
                CCTPHelpers.ETHEREUM_TOKEN_MESSENGER,
                CCTPHelpers.ETHEREUM_MESSAGE_TRANSMITTER,
                CCTPHelpers.ETHEREUM_DOMAIN
            );
        } else if (chainId == 42161) {
            return (
                CCTPHelpers.ARBITRUM_USDC,
                CCTPHelpers.ARBITRUM_TOKEN_MESSENGER,
                CCTPHelpers.ARBITRUM_MESSAGE_TRANSMITTER,
                CCTPHelpers.ARBITRUM_DOMAIN
            );
        } else if (chainId == 10) {
            return (
                CCTPHelpers.OPTIMISM_USDC,
                CCTPHelpers.OPTIMISM_TOKEN_MESSENGER,
                CCTPHelpers.OPTIMISM_MESSAGE_TRANSMITTER,
                CCTPHelpers.OPTIMISM_DOMAIN
            );
        } else if (chainId == 8453) {
            return (
                CCTPHelpers.BASE_USDC,
                CCTPHelpers.BASE_TOKEN_MESSENGER,
                CCTPHelpers.BASE_MESSAGE_TRANSMITTER,
                CCTPHelpers.BASE_DOMAIN
            );
        } else if (chainId == 137) {
            return (
                CCTPHelpers.POLYGON_USDC,
                CCTPHelpers.POLYGON_TOKEN_MESSENGER,
                CCTPHelpers.POLYGON_MESSAGE_TRANSMITTER,
                CCTPHelpers.POLYGON_DOMAIN
            );
        } else if (chainId == 43114) {
            return (
                CCTPHelpers.AVALANCHE_USDC,
                CCTPHelpers.AVALANCHE_TOKEN_MESSENGER,
                CCTPHelpers.AVALANCHE_MESSAGE_TRANSMITTER,
                CCTPHelpers.AVALANCHE_DOMAIN
            );
        } else {
            revert("Unsupported chain");
        }
    }
}

contract DeployFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("Deploying CCTP Strategy Factory");
        
        vm.startBroadcast(deployerPrivateKey);
        
        //StrategyFactory factory = new StrategyFactory();
        
        //console.log("Factory deployed at:", address(factory));
        
        vm.stopBroadcast();
    }
}