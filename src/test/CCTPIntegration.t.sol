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

        // Simulate CCTP message
        bytes memory messageBody = abi.encode(int256(depositAmount));

        vm.prank(address(BASE_MESSAGE_TRANSMITTER));
        remoteStrategy.handleReceiveFinalizedMessage(
            ETHEREUM_DOMAIN,
            bytes32(uint256(uint160(address(strategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            messageBody
        );

        // Step 4: Verify funds are in vault
        uint256 vaultBalance = vault.balanceOf(address(remoteStrategy));
        assertGt(vaultBalance, 0);

        // Earn intrest
        skip(1);

        // Step 5: Send exposure report back
        vm.prank(keeper);
        int256 reportedAmount = remoteStrategy.sendReport();

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

        // Verify accounting
        assertEq(
            strategy.remoteAssets(),
            uint256(int256(depositAmount) + reportedAmount)
        );
        assertApproxEqAbs(
            strategy.totalAssets(),
            uint256(int256(depositAmount) + reportedAmount),
            100
        );
    }

    /*//////////////////////////////////////////////////////////////
                        FULL WITHDRAWAL CYCLE
    //////////////////////////////////////////////////////////////*/

    function test_e2e_withdrawalCycle() public {
        // Setup: First complete a deposit
        uint256 depositAmount = 20000e6; // $20k
        _completeDepositFlow(depositAmount);

        // Now test withdrawal
        uint256 withdrawAmount = 5000e6; // $5k

        vm.selectFork(baseFork);

        vm.prank(keeper);
        remoteStrategy.processWithdrawal(withdrawAmount);

        assertEq(
            remoteStrategy.trackedAssets(),
            depositAmount - withdrawAmount
        );
        assertApproxEqAbs(
            remoteStrategy.totalAssets(),
            depositAmount - withdrawAmount,
            100
        );

        vm.selectFork(ethFork);
        airdropUSDC(address(strategy), withdrawAmount);
        bytes memory messageBody = abi.encode(-int256(withdrawAmount));
        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            messageBody
        );

        assertEq(strategy.remoteAssets(), depositAmount - withdrawAmount);
        assertEq(strategy.totalAssets(), depositAmount);
        uint256 sharesBefore = strategy.balanceOf(depositor);
        uint256 userBalanceBefore = USDC_ETHEREUM.balanceOf(depositor);

        // User withdraws
        vm.prank(depositor);
        uint256 withdrawn = strategy.withdraw(
            withdrawAmount,
            depositor,
            depositor
        );

        assertEq(strategy.remoteAssets(), depositAmount - withdrawAmount);
        assertEq(strategy.totalAssets(), depositAmount - withdrawAmount);

        assertApproxEqAbs(withdrawn, withdrawAmount, 100);
        assertLt(strategy.balanceOf(depositor), sharesBefore);
        assertGt(USDC_ETHEREUM.balanceOf(depositor), userBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        PROFIT REPORTING FLOW
    //////////////////////////////////////////////////////////////*/

    function test_e2e_profitReporting() public {
        // Initial deposit
        uint256 depositAmount = 100000e6; // $100k
        _completeDepositFlow(depositAmount);

        // Simulate yield generation on Base
        vm.selectFork(baseFork);

        skip(1 days);

        // Get current vault balance
        uint256 vaultShares = vault.balanceOf(address(remoteStrategy));
        uint256 totalValue = vault.convertToAssets(vaultShares) +
            USDC_BASE.balanceOf(address(remoteStrategy));

        uint256 expectedProfit = totalValue - depositAmount;

        // Send exposure report
        vm.prank(keeper);
        int256 reportedProfit = remoteStrategy.sendReport();

        assertApproxEqAbs(uint256(reportedProfit), expectedProfit, 1);

        // Process on Ethereum
        vm.selectFork(ethFork);

        uint256 sharesPriceBefore = strategy.pricePerShare();

        // Simulate message with profit
        bytes memory reportMessage = abi.encode(int256(reportedProfit));

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

        // Verify profit reporting
        assertEq(uint256(reportedProfit), profit);
        assertEq(loss, 0);
        assertGt(strategy.pricePerShare(), sharesPriceBefore);
    }

    function test_e2e_lossReporting() public {
        // Initial deposit
        uint256 depositAmount = 100000e6;
        _completeDepositFlow(depositAmount);

        // Simulate loss on Base
        vm.selectFork(baseFork);

        uint256 lossAmount = 1000e6; // $1k loss
        uint256 lossShares = vault.convertToShares(lossAmount);
        vm.prank(address(remoteStrategy));
        vault.transfer(address(69), lossShares);

        // Send exposure report with loss
        vm.prank(keeper);
        int256 reportedProfit = remoteStrategy.sendReport();

        assertApproxEqAbs(uint256(-reportedProfit), lossAmount, 10);

        // Process on Ethereum
        vm.selectFork(ethFork);

        uint256 sharesPriceBefore = strategy.pricePerShare();

        // Simulate message with loss
        bytes memory reportMessage = abi.encode(int256(reportedProfit));

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

        // Verify loss reporting
        assertApproxEqAbs(uint256(-reportedProfit), loss, 1);
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

        // Deposit from multiple users
        vm.selectFork(ethFork);

        // Deposit 1
        _completeDepositFlow(amounts[0]);

        // Deposit 2
        _completeDepositFlow(amounts[1]);

        // Deposit 3
        _completeDepositFlow(amounts[2]);

        vm.selectFork(ethFork);

        uint256 totalDeposited = amounts[0] + amounts[1] + amounts[2];
        // Verify shares proportional to deposits
        assertEq(strategy.balanceOf(depositor), totalDeposited);

        // Process on Base
        vm.selectFork(baseFork);

        uint256 totalValue = vault.convertToAssets(
            vault.balanceOf(address(remoteStrategy))
        ) + USDC_BASE.balanceOf(address(remoteStrategy));
        assertApproxEqAbs(totalValue, totalDeposited, 100);

        // Generate profit
        skip(1 days);

        vm.prank(keeper);
        int256 reportedProfit = remoteStrategy.sendReport();

        // Report profit on Ethereum
        vm.selectFork(ethFork);
        bytes memory reportMessage = abi.encode(int256(reportedProfit));

        vm.prank(address(ETH_MESSAGE_TRANSMITTER));
        strategy.handleReceiveFinalizedMessage(
            BASE_DOMAIN,
            bytes32(uint256(uint160(address(remoteStrategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            reportMessage
        );

        vm.prank(keeper);
        (uint256 profit, ) = strategy.report();

        // Total value should be greater than total deposited due to profit
        assertEq(strategy.totalAssets(), totalDeposited + profit);
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

        bytes memory messageBody = abi.encode(int256(_amount));
        vm.prank(address(BASE_MESSAGE_TRANSMITTER));
        remoteStrategy.handleReceiveFinalizedMessage(
            ETHEREUM_DOMAIN,
            bytes32(uint256(uint160(address(strategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            messageBody
        );
    }
}
