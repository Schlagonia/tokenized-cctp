// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract EmergencyTests is Setup {
    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY SHUTDOWN
    //////////////////////////////////////////////////////////////*/

    function test_emergencyShutdownAndRecovery() public useEthFork {
        // Combines shutdown with remote funds and partial recovery scenarios
        uint256 depositAmount = 100000e6;

        // Setup and deposit
        mintAndDepositIntoStrategy(strategy, depositor, depositAmount);

        uint256 remoteProfit = 100e6;

        // Simulate remote assets being reported
        bytes memory reportMessage = abi.encode(int256(remoteProfit));

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000,
            reportMessage
        );

        assertEq(strategy.remoteAssets(), depositAmount + remoteProfit);

        // Trigger emergency shutdown
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();
        assertTrue(strategy.isShutdown());

        // Simulate partial recovery
        uint256 recoveredAmount = 40000e6;
        airdropUSDC(address(strategy), recoveredAmount);

        bytes memory recoveryMessage = abi.encode(-int256(recoveredAmount));

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000,
            recoveryMessage
        );

        vm.prank(keeper);
        strategy.report();

        // Verify users can withdraw recovered amount
        uint256 userShares = strategy.balanceOf(depositor);
        uint256 withdrawable = strategy.convertToAssets(userShares);
        assertGt(withdrawable, 0);

        uint256 availableLimit = strategy.availableWithdrawLimit(depositor);
        uint256 toWithdraw = withdrawable > availableLimit
            ? availableLimit
            : withdrawable;

        if (toWithdraw > 0) {
            vm.prank(depositor);
            uint256 withdrawn = strategy.withdraw(
                toWithdraw,
                depositor,
                depositor
            );
            assertGt(withdrawn, 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        CCTP MESSAGE VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_invalidSenderValidation() public useEthFork {
        bytes memory messageBody = abi.encode(int256(1000e6));

        // Wrong transmitter
        vm.prank(user);
        vm.expectRevert();
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000,
            messageBody
        );

        // Empty message
        bytes memory emptyMessage = "";
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        vm.expectRevert();
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000,
            emptyMessage
        );
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function test_vaultSlippage() public useBaseFork {
        uint256 depositAmount = 100000e6;

        // Setup funds in remote strategy
        airdropUSDC(address(remoteStrategy), depositAmount);

        // Push funds to vault
        vm.prank(keeper);
        remoteStrategy.pushFunds(depositAmount);

        uint256 sharesBefore = vault.balanceOf(address(remoteStrategy));
        assertTrue(sharesBefore > 0);

        // Pull half the funds back
        vm.prank(keeper);
        remoteStrategy.pullFunds(sharesBefore / 2);

        uint256 assetsReceived = USDC_BASE.balanceOf(address(remoteStrategy));

        // Strategy should handle slippage gracefully
        assertTrue(assetsReceived > 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function test_emergencyAdminPowers() public useEthFork {
        mintAndDepositIntoStrategy(strategy, depositor, 50000e6);

        // Only emergency admin can shutdown
        vm.prank(user);
        vm.expectRevert();
        strategy.shutdownStrategy();

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();
        assertTrue(strategy.isShutdown());

        // After shutdown, strategy can't accept new deposits
        airdropUSDC(depositor, 10000e6);
        vm.startPrank(depositor);
        USDC_ETHEREUM.approve(address(strategy), 10000e6);
        vm.expectRevert();
        strategy.deposit(10000e6, depositor);
        vm.stopPrank();
    }

    function test_keeperAccessDuringEmergency() public {
        // Setup funds
        vm.selectFork(ethFork);
        mintAndDepositIntoStrategy(strategy, depositor, 20000e6);

        // Shutdown on main chain
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();
        assertTrue(strategy.isShutdown());

        // Keeper can still operate on Base to help recover funds
        vm.selectFork(baseFork);

        // Simulate having funds in remote strategy
        airdropUSDC(address(remoteStrategy), 20000e6);

        bytes memory depositMessage = abi.encode(int256(20000e6));

        vm.prank(address(BASE_MESSAGE_TRANSMITTER));
        remoteStrategy.handleReceiveFinalizedMessage(
            ETHEREUM_DOMAIN,
            bytes32(uint256(uint160(address(strategy)))),
            2000,
            depositMessage
        );

        // Keeper operations should still work
        vm.prank(keeper);
        remoteStrategy.processWithdrawal(10000e6);

        vm.prank(keeper);
        remoteStrategy.sendReport();
    }
}
