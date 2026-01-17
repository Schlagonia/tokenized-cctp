// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract CCTPIntegrationTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLETE DEPOSIT FLOW
    //////////////////////////////////////////////////////////////*/

    function test_e2e_depositFlow() public {
        uint256 depositAmount = 10000e6; // $10k USDC

        // Step 1: User deposits on Ethereum
        vm.selectFork(ethFork);
        airdropUSDC(depositor, depositAmount);

        vm.startPrank(depositor);
        USDC_ETHEREUM.approve(address(strategy), depositAmount);
        uint256 shares = strategy.deposit(depositAmount, depositor);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(strategy.balanceOf(depositor), shares);

        // Step 3: Simulate CCTP message delivery to Base
        vm.selectFork(baseFork);

        // Simulate USDC arrival on Base (in reality CCTP would mint)
        airdropUSDC(address(remoteStrategy), depositAmount);

        // Keeper pushes funds to vault
        vm.prank(keeper);
        remoteStrategy.pushFunds(depositAmount);

        // Step 4: Verify funds are in vault
        uint256 vaultBalance = vault.balanceOf(address(remoteStrategy));
        assertGt(vaultBalance, 0);

        // Earn interest
        skip(1);

        // Step 5: Send exposure report back (report() also pushes any remaining idle funds)
        vm.prank(keeper);
        (uint256 reportedAmount, ) = remoteStrategy.report();

        // Step 6: Process report on Ethereum
        vm.selectFork(ethFork);

        bytes memory reportMessage = abi.encode(reportedAmount);

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            reportMessage
        );

        // Report on origin to update accounting
        vm.prank(keeper);
        strategy.report();

        // Verify accounting after report
        assertApproxEqAbs(calculateRemoteAssets(strategy), reportedAmount, 100);
        assertApproxEqAbs(strategy.totalAssets(), reportedAmount, 100);
    }

    /*//////////////////////////////////////////////////////////////
                        FULL WITHDRAWAL CYCLE
    //////////////////////////////////////////////////////////////*/

    function test_e2e_withdrawalCycle() public {
        // Setup: First complete a deposit and sync accounting
        uint256 depositAmount = 20000e6; // $20k
        _completeDepositFlowWithReport(depositAmount);

        // Now test withdrawal
        uint256 withdrawAmount = 5000e6; // $5k

        vm.selectFork(baseFork);

        skip(1);

        vm.prank(keeper);
        remoteStrategy.processWithdrawal(withdrawAmount);

        // Use approx due to vault rounding
        assertApproxEqAbs(
            remoteStrategy.valueOfDeployedAssets(),
            depositAmount - withdrawAmount,
            100
        );

        // Simulate withdrawal arriving on origin and remote sending updated total assets
        vm.selectFork(ethFork);
        airdropUSDC(address(strategy), withdrawAmount);

        // Send updated remote assets (remaining after withdrawal)
        uint256 remainingRemote = depositAmount - withdrawAmount;
        bytes memory messageBody = abi.encode(remainingRemote);
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            messageBody
        );

        // Disable health check for this test as withdrawal changes accounting significantly
        vm.prank(management);
        strategy.setDoHealthCheck(false);

        // Report to update accounting
        vm.prank(keeper);
        strategy.report();

        // After report: totalAssets = local + remote = withdrawAmount + remainingRemote = depositAmount
        assertApproxEqAbs(strategy.totalAssets(), depositAmount, 1000);

        uint256 sharesBefore = strategy.balanceOf(depositor);
        uint256 userBalanceBefore = USDC_ETHEREUM.balanceOf(depositor);

        // User withdraws
        vm.prank(depositor);
        uint256 withdrawn = strategy.withdraw(
            withdrawAmount,
            depositor,
            depositor
        );

        // After withdrawal: totalAssets = depositAmount - withdrawAmount
        assertApproxEqAbs(
            strategy.totalAssets(),
            depositAmount - withdrawAmount,
            100
        );

        assertApproxEqAbs(withdrawn, withdrawAmount, 100);
        assertLt(strategy.balanceOf(depositor), sharesBefore);
        assertGt(USDC_ETHEREUM.balanceOf(depositor), userBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        PROFIT REPORTING FLOW
    //////////////////////////////////////////////////////////////*/

    function test_e2e_profitReporting() public {
        // Initial deposit with accounting sync
        uint256 depositAmount = 100000e6; // $100k
        _completeDepositFlowWithReport(depositAmount);

        // Simulate yield generation on Base
        vm.selectFork(baseFork);

        skip(1 days);

        // Get current vault balance (after time skip, may have earned yield)
        uint256 vaultShares = vault.balanceOf(address(remoteStrategy));
        uint256 totalValue = vault.convertToAssets(vaultShares) +
            USDC_BASE.balanceOf(address(remoteStrategy));

        // Profit is difference between current value and what was reported initially
        uint256 expectedProfit = totalValue > depositAmount
            ? totalValue - depositAmount
            : 0;

        // Send exposure report (now returns total assets, not profit delta)
        vm.prank(keeper);
        (uint256 reportedTotalAssets, ) = remoteStrategy.report();

        // Total assets should equal vault value + loose balance (with some vault rounding)
        assertApproxEqAbs(reportedTotalAssets, totalValue, 1000);

        // Process on Ethereum
        vm.selectFork(ethFork);

        uint256 sharesPriceBefore = strategy.pricePerShare();

        // Simulate message with total remote assets
        bytes memory reportMessage = abi.encode(reportedTotalAssets);

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            reportMessage
        );

        // Harvest and report
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Verify profit reporting (with vault rounding tolerance)
        assertApproxEqAbs(profit, expectedProfit, 1000);
        assertEq(loss, 0);
        // Price per share should increase or stay same (with profit)
        assertGe(strategy.pricePerShare(), sharesPriceBefore);
    }

    function test_e2e_lossReporting() public {
        // Initial deposit with accounting sync
        uint256 depositAmount = 100000e6;
        _completeDepositFlowWithReport(depositAmount);

        // Simulate loss on Base
        vm.selectFork(baseFork);

        uint256 lossAmount = 1000e6; // $1k loss
        uint256 lossShares = vault.convertToShares(lossAmount);
        vm.prank(address(remoteStrategy));
        vault.transfer(address(69), lossShares);

        // Send exposure report (now returns total assets, which reflects the loss)
        skip(1);
        vm.prank(keeper);
        (uint256 reportedTotalAssets, ) = remoteStrategy.report();

        // Total assets should be approximately depositAmount - lossAmount (with vault rounding)
        assertApproxEqAbs(
            reportedTotalAssets,
            depositAmount - lossAmount,
            1000
        );

        // Process on Ethereum
        vm.selectFork(ethFork);

        uint256 sharesPriceBefore = strategy.pricePerShare();

        // Simulate message with total remote assets (after loss)
        bytes memory reportMessage = abi.encode(reportedTotalAssets);

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            reportMessage
        );

        vm.prank(management);
        strategy.setDoHealthCheck(false);

        // Harvest and report
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Verify loss reporting (with vault rounding tolerance)
        assertApproxEqAbs(loss, lossAmount, 1000);
        assertEq(profit, 0);
        assertLt(strategy.pricePerShare(), sharesPriceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        MULTI-USER SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_e2e_multipleDeposits() public {
        // Multiple deposits
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10000e6; // $10k
        amounts[1] = 25000e6; // $25k
        amounts[2] = 15000e6; // $15k

        // Deposit from multiple users with accounting sync
        // Deposit 1
        _completeDepositFlowWithReport(amounts[0]);

        // Deposit 2
        _completeDepositFlowWithReport(amounts[1]);

        // Deposit 3
        _completeDepositFlowWithReport(amounts[2]);

        vm.selectFork(ethFork);

        uint256 totalDeposited = amounts[0] + amounts[1] + amounts[2];
        // Verify shares proportional to deposits (with cumulative vault rounding from multiple deposits/reports)
        assertApproxEqAbs(strategy.balanceOf(depositor), totalDeposited, 2e6);

        // Process on Base
        vm.selectFork(baseFork);

        uint256 totalValue = vault.convertToAssets(
            vault.balanceOf(address(remoteStrategy))
        ) + USDC_BASE.balanceOf(address(remoteStrategy));
        assertApproxEqAbs(totalValue, totalDeposited, 2e6);

        // Generate profit
        skip(1 days);

        vm.prank(keeper);
        (uint256 reportedTotalAssets, ) = remoteStrategy.report();

        // Report on Ethereum
        vm.selectFork(ethFork);
        bytes memory reportMessage = abi.encode(reportedTotalAssets);

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            reportMessage
        );

        vm.prank(keeper);
        (uint256 profit, ) = strategy.report();

        // Total value should be greater than or equal to total deposited (with vault rounding)
        assertApproxEqAbs(strategy.totalAssets(), totalDeposited + profit, 2e6);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _completeDepositFlow(uint256 _amount) internal {
        // Deposit on Ethereum
        vm.selectFork(ethFork);

        mintAndDepositIntoStrategy(strategy, depositor, _amount);

        // Process on Base
        vm.selectFork(baseFork);
        airdropUSDC(address(remoteStrategy), _amount);

        // Keeper pushes funds to vault
        vm.prank(keeper);
        remoteStrategy.pushFunds(_amount);
    }

    function _completeDepositFlowWithReport(uint256 _amount) internal {
        // Complete deposit flow
        _completeDepositFlow(_amount);

        // Send report from remote to origin to sync accounting
        skip(1);
        vm.prank(keeper);
        (uint256 reportedAssets, ) = remoteStrategy.report();

        // Process report on Ethereum
        vm.selectFork(ethFork);
        bytes memory reportMessage = abi.encode(reportedAssets);
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000,
            reportMessage
        );

        // Report on origin to update accounting
        vm.prank(keeper);
        strategy.report();
    }
}
