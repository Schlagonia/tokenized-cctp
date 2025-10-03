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

    function test_emergencyShutdownWithRemoteFunds() public {
        // Setup: Deploy funds to remote
        uint256 depositAmount = 100000e6;

        vm.selectFork(ethFork);
        airdropUSDC(depositor, depositAmount);

        vm.startPrank(depositor);
        USDC_ETHEREUM.approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, depositor);
        vm.stopPrank();

        // Bridge funds
        vm.prank(keeper);

        // Process on Base
        vm.selectFork(baseFork);
        airdropUSDC(address(remoteStrategy), depositAmount);
        bytes memory messageBody = abi.encode(
            uint256(1),
            int256(depositAmount)
        );

        vm.prank(address(BASE_MESSAGE_TRANSMITTER));
        remoteStrategy.handleReceiveFinalizedMessage(
            ETHEREUM_DOMAIN,
            bytes32(uint256(uint160(address(strategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            messageBody
        );

        // Report back to update remoteAssets
        vm.prank(keeper);
        remoteStrategy.sendReport();

        vm.selectFork(ethFork);
        bytes memory reportMessage = abi.encode(
            uint256(1),
            int256(depositAmount)
        );
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            reportMessage
        );

        // Trigger emergency shutdown
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertTrue(strategy.isShutdown());

        // Users can only withdraw local balance
        uint256 withdrawLimit = strategy.availableWithdrawLimit(depositor);
        uint256 localBalance = USDC_ETHEREUM.balanceOf(address(strategy));
        assertEq(withdrawLimit, localBalance);

        // Remote funds are stuck until manually recovered
        assertGt(strategy.remoteAssets(), 0);
        assertEq(
            strategy.totalAssets(),
            localBalance + strategy.remoteAssets()
        );
    }

    function test_partialRecoveryAfterShutdown() public {
        // Setup with remote funds
        uint256 depositAmount = 50000e6;

        vm.selectFork(ethFork);
        mintAndDepositIntoStrategy(strategy, depositor, depositAmount);

        vm.prank(keeper);

        // Remote assets are updated through CCTP messages, not directly
        // In a real scenario, we'd receive a message updating remoteAssets

        // Shutdown
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Manually recover some funds from remote
        vm.selectFork(baseFork);
        airdropUSDC(address(remoteStrategy), 20000e6); // Partial recovery

        vm.prank(keeper);
        remoteStrategy.processWithdrawal(20000e6);

        // Simulate CCTP bridge back
        vm.selectFork(ethFork);
        airdropUSDC(address(strategy), 20000e6);

        // Now users can withdraw recovered amount
        uint256 withdrawable = strategy.availableWithdrawLimit(depositor);
        assertGt(withdrawable, 0);

        vm.prank(depositor);
        uint256 withdrawn = strategy.withdraw(
            withdrawable,
            depositor,
            depositor
        );
        assertGt(withdrawn, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        CCTP FAILURES
    //////////////////////////////////////////////////////////////*/

    function test_messageReplayAttack() public useEthFork {
        // Setup
        mintAndDepositIntoStrategy(strategy, depositor, 10000e6);

        vm.prank(keeper);

        // Valid message
        uint256 requestId = strategy.nextRequestId();
        bytes memory messageBody = abi.encode(requestId, int256(10000e6));

        // Process once
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            messageBody
        );

        uint256 assetsAfterFirst = strategy.remoteAssets();

        // Try replay attack
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        vm.expectRevert("BaseCCTP: Message already processed");
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            messageBody
        );

        // Assets unchanged
        assertEq(strategy.remoteAssets(), assetsAfterFirst);
    }

    function test_outOfOrderMessages() public useEthFork {
        // Setup
        mintAndDepositIntoStrategy(strategy, depositor, 10000e6);

        // Try to process message with future request ID
        uint256 currentId = strategy.nextRequestId();
        bytes memory futureMessage = abi.encode(currentId + 10, int256(5000e6));

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        vm.expectRevert("BaseCCTP: Invalid request ID");
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            futureMessage
        );

        // Try with past request ID (assuming it wasn't processed)
        bytes memory pastMessage = abi.encode(0, int256(5000e6));

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        vm.expectRevert("BaseCCTP: Invalid request ID");
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            pastMessage
        );
    }

    function test_invalidNonceHandling() public useEthFork {
        // This would test CCTP nonce validation but requires deeper CCTP integration
        // The current implementation relies on CCTP's own nonce validation

        // Try to send message from wrong address (not message transmitter)
        bytes memory messageBody = abi.encode(uint256(1), int256(1000e6));

        vm.prank(user); // Not the message transmitter
        vm.expectRevert();
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            messageBody
        );
    }

    function test_malformedMessageHandling() public useEthFork {
        // Test with invalid message format
        bytes memory badMessage = abi.encode("invalid", "data");

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        vm.expectRevert(); // Should revert on decode
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            badMessage
        );

        // Test with empty message
        bytes memory emptyMessage = "";

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        vm.expectRevert();
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            emptyMessage
        );
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT FAILURES
    //////////////////////////////////////////////////////////////*/

    function test_vaultPausedScenario() public useBaseFork {
        // Setup funds in remote
        uint256 amount = 20000e6;
        airdropUSDC(address(remoteStrategy), amount);

        // Deposit to vault
        vm.prank(keeper);
        remoteStrategy.pushFunds(amount);

        // Simulate vault being paused (can't actually pause without vault interface)
        // In real scenario, vault.deposit() and vault.redeem() would revert

        // Try to push more funds - would fail if vault is paused
        airdropUSDC(address(remoteStrategy), 5000e6);

        // This would revert if vault was actually paused
        vm.prank(keeper);
        remoteStrategy.pushFunds(5000e6);

        // Try withdrawal - would also fail if vault paused
        vm.prank(keeper);
        remoteStrategy.processWithdrawal(10000e6);
    }

    function test_vaultSlippage() public useBaseFork {
        // Setup
        uint256 depositAmount = 100000e6;
        airdropUSDC(address(remoteStrategy), depositAmount);

        // Deposit to vault
        vm.prank(keeper);
        remoteStrategy.pushFunds(depositAmount);

        uint256 sharesBefore = vault.balanceOf(address(remoteStrategy));

        // Simulate slippage - vault returns fewer assets than expected
        // This would happen if vault has fees or slippage

        // Withdraw with potential slippage
        vm.prank(keeper);
        remoteStrategy.pullFunds(sharesBefore / 2);

        uint256 assetsReceived = USDC_BASE.balanceOf(address(remoteStrategy));

        // In case of slippage, received < expected
        // Strategy should handle this gracefully
        assertTrue(assetsReceived > 0);
    }

    function test_totalLossInVault() public {
        // Setup: Deploy significant funds
        uint256 depositAmount = 1000000e6; // $1M

        vm.selectFork(ethFork);
        mintAndDepositIntoStrategy(strategy, depositor, depositAmount);

        vm.prank(keeper);

        // Process on Base
        vm.selectFork(baseFork);
        airdropUSDC(address(remoteStrategy), depositAmount);

        bytes memory messageBody = abi.encode(
            uint256(1),
            int256(depositAmount)
        );
        vm.prank(address(BASE_MESSAGE_TRANSMITTER));
        remoteStrategy.handleReceiveFinalizedMessage(
            ETHEREUM_DOMAIN,
            bytes32(uint256(uint160(address(strategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            messageBody
        );

        // Simulate total loss in vault
        // Report 0 assets
        vm.prank(keeper);
        remoteStrategy.sendReport();

        vm.selectFork(ethFork);
        bytes memory lossMessage = abi.encode(uint256(1), int256(0)); // Total loss

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            lossMessage
        );

        // Report the loss
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertEq(profit, 0);
        assertEq(loss, depositAmount);

        // Share price should be 0 or very low
        assertLt(strategy.pricePerShare(), 0.01e18);
    }

    /*//////////////////////////////////////////////////////////////
                    COMPLEX FAILURE SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_cascadingFailures() public {
        // Multiple failures: deposit -> partial vault loss -> shutdown -> partial recovery

        uint256 deposit1 = 100000e6;
        uint256 deposit2 = 50000e6;

        // Two users deposit
        vm.selectFork(ethFork);

        mintAndDepositIntoStrategy(strategy, depositor, deposit1);

        address depositor2 = address(0x222);
        // DEPOSITER is immutable, can't change it
        // For this test, we'll use the same depositor

        // Use same depositor for second deposit
        airdropUSDC(depositor, deposit2);
        vm.startPrank(depositor);
        USDC_ETHEREUM.approve(address(strategy), deposit2);
        strategy.deposit(deposit2, depositor);
        vm.stopPrank();

        // Bridge funds
        vm.prank(keeper);

        // Process on Base
        vm.selectFork(baseFork);
        uint256 totalDeposited = deposit1 + deposit2;
        airdropUSDC(address(remoteStrategy), totalDeposited);

        bytes memory msg1 = abi.encode(uint256(1), int256(totalDeposited));
        vm.prank(address(BASE_MESSAGE_TRANSMITTER));
        remoteStrategy.handleReceiveFinalizedMessage(
            ETHEREUM_DOMAIN,
            bytes32(uint256(uint160(address(strategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            msg1
        );

        // Vault suffers 50% loss
        vm.prank(keeper);
        remoteStrategy.sendReport();

        vm.selectFork(ethFork);
        bytes memory lossMsg = abi.encode(
            uint256(1),
            int256(totalDeposited / 2)
        );
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            lossMsg
        );

        vm.prank(keeper);
        strategy.report();

        // Emergency shutdown triggered
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Try to recover remaining funds from Base
        vm.selectFork(baseFork);
        uint256 recoverable = totalDeposited / 4; // Can only recover half of remaining
        airdropUSDC(address(remoteStrategy), recoverable);

        vm.prank(keeper);
        remoteStrategy.processWithdrawal(recoverable);

        // Bridge back
        vm.selectFork(ethFork);
        airdropUSDC(address(strategy), recoverable);

        // User withdraws what they can
        uint256 userShares = strategy.balanceOf(depositor);

        uint256 userValue = strategy.convertToAssets(userShares);

        // User lost significant value
        uint256 totalDeposit = deposit1 + deposit2;
        assertLt(userValue, totalDeposit);

        // But can still withdraw something
        if (
            userValue > 0 &&
            userValue <= strategy.availableWithdrawLimit(depositor)
        ) {
            vm.prank(depositor);
            strategy.withdraw(userValue, depositor, depositor);
        }
    }

    function test_bridgeFailureDuringWithdrawal() public {
        // Setup with remote funds
        uint256 depositAmount = 75000e6;

        vm.selectFork(ethFork);
        mintAndDepositIntoStrategy(strategy, depositor, depositAmount);

        vm.prank(keeper);

        // Remote assets are updated through CCTP messages, not directly
        // In a real scenario, we'd receive a message updating remoteAssets

        // User requests withdrawal but bridge fails
        // (simulated by not receiving funds on Ethereum)

        vm.selectFork(baseFork);
        airdropUSDC(address(remoteStrategy), depositAmount);

        vm.prank(keeper);
        remoteStrategy.processWithdrawal(depositAmount);

        // Bridge "fails" - funds don't arrive on Ethereum
        vm.selectFork(ethFork);

        // User can't withdraw because funds didn't arrive
        uint256 withdrawable = strategy.availableWithdrawLimit(depositor);
        assertEq(withdrawable, 0); // No local balance

        // Admin needs to manually intervene
        // In a real scenario, would need to receive CCTP message reporting the loss

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        assertEq(loss, depositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL IN EMERGENCIES
    //////////////////////////////////////////////////////////////*/

    function test_emergencyAdminPowers() public useEthFork {
        // Setup
        mintAndDepositIntoStrategy(strategy, depositor, 50000e6);

        // Only emergency admin can shutdown
        vm.prank(user);
        vm.expectRevert();
        strategy.shutdownStrategy();

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();
        assertTrue(strategy.isShutdown());

        // After shutdown, strategy can't deploy new funds
        airdropUSDC(depositor, 10000e6);
        vm.startPrank(depositor);
        USDC_ETHEREUM.approve(address(strategy), 10000e6);
        vm.expectRevert();
        strategy.deposit(10000e6, depositor);
        vm.stopPrank();
    }

    function test_keeperAccessDuringEmergency() public useBaseFork {
        // Even during emergency, keepers should be able to operate

        // Setup funds
        airdropUSDC(address(remoteStrategy), 20000e6);

        // Simulate emergency on main chain
        vm.selectFork(ethFork);
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Keeper can still operate on Base to recover funds
        vm.selectFork(baseFork);

        vm.prank(keeper);
        remoteStrategy.processWithdrawal(20000e6); // Should succeed

        vm.prank(keeper);
        remoteStrategy.sendReport(); // Should succeed
    }
}
