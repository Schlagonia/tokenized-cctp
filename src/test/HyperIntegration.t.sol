// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CCTPStrategy} from "../CCTPStrategy.sol";
import {CCTPHelpers} from "../libraries/CCTPHelpers.sol";
import {ITokenMessenger} from "../interfaces/circle/ITokenMessenger.sol";
import {IMessageTransmitter} from "../interfaces/circle/IMessageTransmitter.sol";

/// @title HyperIntegration Tests
/// @notice Tests for CCTP strategy bridging to HyperEVM for HyperCore HLP vault
/// @dev Uses base CCTPStrategy with HyperEVM domain (19)
contract HyperIntegrationTest is Test {
    // Ethereum mainnet contracts
    IERC20 public constant USDC_ETHEREUM =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ITokenMessenger public constant ETH_TOKEN_MESSENGER =
        ITokenMessenger(0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d);
    IMessageTransmitter public constant ETH_MESSAGE_TRANSMITTER =
        IMessageTransmitter(0x81D40F21F12A8F0E3252Bccb954D722d4c464B64);

    // Test addresses
    address public depositor = address(0x1234);
    address public management = address(0x5678);
    address public keeper = address(0x9ABC);
    address public governance = address(0xDEF0);

    // Mock remote strategy address (would be deployed on HyperEVM)
    address public mockRemoteStrategy = address(0xBEEF);

    // Fork ID
    uint256 public ethFork;

    CCTPStrategy public strategy;

    function setUp() public {
        // Create Ethereum fork
        string memory ethRpc = vm.envString("ETH_RPC_URL");
        ethFork = vm.createFork(ethRpc);
        vm.selectFork(ethFork);

        // Deploy CCTPStrategy on Ethereum with HyperEVM domain
        strategy = new CCTPStrategy(
            address(USDC_ETHEREUM),
            "Hyper CCTP USDC Strategy",
            address(ETH_TOKEN_MESSENGER),
            address(ETH_MESSAGE_TRANSMITTER),
            CCTPHelpers.HYPEREVM_DOMAIN, // domain 19
            mockRemoteStrategy,
            depositor
        );

        // Label addresses
        vm.label(address(strategy), "CCTPStrategy");
        vm.label(address(USDC_ETHEREUM), "USDC_ETHEREUM");
        vm.label(depositor, "depositor");
        vm.label(management, "management");
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_strategyConfiguration() public {
        assertEq(
            strategy.REMOTE_COUNTERPART(),
            mockRemoteStrategy,
            "Wrong remote counterpart"
        );
        assertEq(
            uint32(uint256(strategy.REMOTE_ID())),
            CCTPHelpers.HYPEREVM_DOMAIN,
            "Wrong remote domain"
        );
        assertEq(strategy.DEPOSITER(), depositor, "Wrong depositor");
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT LIMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_depositLimit_depositor() public {
        uint256 limit = strategy.availableDepositLimit(depositor);
        assertEq(limit, type(uint256).max, "Depositor should have max limit");
    }

    function test_depositLimit_nonDepositor() public {
        uint256 limit = strategy.availableDepositLimit(address(0x999));
        assertEq(limit, 0, "Non-depositor should have zero limit");
    }

    /*//////////////////////////////////////////////////////////////
                        DOMAIN AND ADDRESS CONSTANTS
    //////////////////////////////////////////////////////////////*/

    function test_hyperEvmDomain() public {
        assertEq(CCTPHelpers.HYPEREVM_DOMAIN, 19, "Wrong HyperEVM domain");
    }

    function test_hyperEvmUsdcAddress() public {
        assertEq(
            CCTPHelpers.HYPEREVM_USDC,
            0xb88339CB7199b77E23DB6E890353E22632Ba630f,
            "Wrong HyperEVM USDC address"
        );
    }

    function test_getUSDC_hyperEvm() public {
        address usdc = CCTPHelpers.getUSDC(CCTPHelpers.HYPEREVM_DOMAIN);
        assertEq(
            usdc,
            CCTPHelpers.HYPEREVM_USDC,
            "getUSDC failed for HyperEVM"
        );
    }
}
