// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup} from "./utils/Setup.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    // Test 1: Verify cross-chain strategy setup and configuration
    function test_setupStrategyOK() public useEthFork {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(USDC_ETHEREUM));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);

        // Generic cross-chain properties
        assertEq(strategy.DEPOSITER(), depositor);
        assertEq(strategy.REMOTE_COUNTERPART(), address(remoteStrategy));
        assertEq(strategy.remoteAssets(), 0);
    }

    // Test 2: Only DEPOSITER can deposit (generic access control test)
    function test_depositLimits() public useEthFork {
        uint256 _amount = 1000e6; // $1000 USDC

        // Non-depositer cannot deposit (availableDepositLimit = 0)
        assertEq(strategy.availableDepositLimit(user), 0);

        // DEPOSITER can deposit (availableDepositLimit = max)
        assertEq(strategy.availableDepositLimit(depositor), type(uint256).max);

        // Try to deposit as user (should fail)
        airdropUSDC(user, _amount);
        vm.startPrank(user);
        USDC_ETHEREUM.approve(address(strategy), _amount);
        vm.expectRevert();
        strategy.deposit(_amount, user);
        vm.stopPrank();

        // Deposit as depositer (should succeed)
        airdropUSDC(depositor, _amount);
        vm.startPrank(depositor);
        USDC_ETHEREUM.approve(address(strategy), _amount);
        strategy.deposit(_amount, depositor);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);
    }

    // Test 2b: Fuzz version of deposit limits
    function test_depositLimitsFuzz(uint256 _amount) public useEthFork {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        // DEPOSITER can deposit (availableDepositLimit = max)
        assertEq(strategy.availableDepositLimit(depositor), type(uint256).max);

        // Deposit as depositer (should succeed)
        airdropUSDC(depositor, _amount);
        vm.startPrank(depositor);
        USDC_ETHEREUM.approve(address(strategy), _amount);
        strategy.deposit(_amount, depositor);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), _amount);
    }

    // Test 4: Remote asset tracking - profit updates
    function test_remoteAssetTracking_profit() public useEthFork {
        uint256 _amount = 10000e6; // $10k USDC
        uint256 profit = 100e6; // $100 profit

        mintAndDepositIntoStrategy(strategy, depositor, _amount);

        vm.selectFork(ethFork);

        // Simulate remote strategy reporting profit
        bytes memory profitMessage = abi.encode(int256(profit));
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000,
            profitMessage
        );

        // Verify remoteAssets updated correctly
        assertEq(strategy.remoteAssets(), _amount + profit);
        // Total assets has not updated
        assertEq(strategy.totalAssets(), _amount);

        vm.prank(keeper);
        strategy.report();

        // Total assets should now include profit
        assertEq(strategy.totalAssets(), _amount + profit);
        assertEq(strategy.remoteAssets(), _amount + profit);
    }

    // Test 5: Remote asset tracking - loss updates
    function test_remoteAssetTracking_loss() public useEthFork {
        uint256 _amount = 10000e6; // $10k USDC
        uint256 loss = 500e6; // $500 loss

        mintAndDepositIntoStrategy(strategy, depositor, _amount);

        vm.selectFork(ethFork);

        // Simulate remote strategy reporting loss
        bytes memory lossMessage = abi.encode(-int256(loss));
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000,
            lossMessage
        );

        // Verify remoteAssets reduced correctly
        assertEq(strategy.remoteAssets(), _amount - loss);
        assertEq(strategy.totalAssets(), _amount);

        vm.prank(management);
        strategy.setDoHealthCheck(false);

        vm.prank(keeper);
        strategy.report();

        // Total assets should now include loss
        assertEq(strategy.totalAssets(), _amount - loss);
        assertEq(strategy.remoteAssets(), _amount - loss);
    }

    // Test 7: Invalid sender/domain rejection
    function test_rejectInvalidSender() public useEthFork {
        uint256 _amount = 1000e6;
        bytes memory message = abi.encode(int256(_amount));

        // Wrong transmitter (should fail)
        vm.prank(user);
        vm.expectRevert();
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000,
            message
        );

        // Wrong domain (should fail)
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        vm.expectRevert();
        strategy.handleReceiveFinalizedMessage(
            ETHEREUM_DOMAIN, // Wrong domain
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000,
            message
        );

        // Wrong counterpart (should fail)
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        vm.expectRevert();
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(user))), // Wrong sender
            2000,
            message
        );
    }
}
