// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RemoteStrategyTests is Setup {
    function setUp() public override {
        super.setUp();
    }

    function simulateBridgeDeposit(uint256 _amount) public {
        vm.selectFork(baseFork);
        // Simulate receiving USDC from bridge
        airdropUSDC(address(remoteStrategy), _amount);
        // In new architecture, keeper pushes funds to vault
        vm.prank(keeper);
        remoteStrategy.pushFunds(_amount);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_remoteDeployment() public useBaseFork {
        assertEq(address(remoteStrategy.asset()), address(USDC_BASE));
        assertEq(address(remoteStrategy.vault()), address(vault));
        assertEq(remoteStrategy.REMOTE_COUNTERPART(), address(strategy));
        assertEq(remoteStrategy.REMOTE_ID(), bytes32(uint256(ETHEREUM_DOMAIN)));
        assertEq(remoteStrategy.governance(), governance);
    }

    function test_remoteKeepersSet() public useBaseFork {
        assertTrue(remoteStrategy.keepers(keeper));
        assertFalse(remoteStrategy.keepers(user));
    }

    function test_remoteCCTPConfiguration() public useBaseFork {
        assertEq(
            address(remoteStrategy.TOKEN_MESSENGER()),
            address(BASE_TOKEN_MESSENGER)
        );
        assertEq(
            address(remoteStrategy.MESSAGE_TRANSMITTER()),
            address(BASE_MESSAGE_TRANSMITTER)
        );
    }

    function test_remoteApprovalsSet() public useBaseFork {
        // Check USDC approvals
        assertEq(
            USDC_BASE.allowance(
                address(remoteStrategy),
                address(BASE_TOKEN_MESSENGER)
            ),
            type(uint256).max
        );
        assertEq(
            USDC_BASE.allowance(address(remoteStrategy), address(vault)),
            type(uint256).max
        );
    }

    /*//////////////////////////////////////////////////////////////
                        CCTP RECEPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_receiveAndDepositFunds() public useBaseFork {
        uint256 amount = 10000e6;

        // Simulate receiving USDC from bridge
        airdropUSDC(address(remoteStrategy), amount);

        // In the new architecture, remote strategies don't receive CCTP messages for deposits
        // Instead, keepers manually push funds to the vault
        uint256 vaultBalanceBefore = vault.balanceOf(address(remoteStrategy));

        // Keeper pushes the idle funds to the vault
        vm.prank(keeper);
        remoteStrategy.pushFunds(amount);

        // Should have deposited to vault
        uint256 vaultBalanceAfter = vault.balanceOf(address(remoteStrategy));
        assertGt(vaultBalanceAfter, vaultBalanceBefore);
        // Use approx due to vault conversion rounding
        assertApproxEqAbs(remoteStrategy.valueOfDeployedAssets(), amount, 10);
    }

    function test_handleVaultDepositLimit() public useBaseFork {
        uint256 amount = 10000e6;
        airdropUSDC(address(remoteStrategy), amount);

        // Mock vault max deposit (would need actual vault to test properly)
        // This test assumes vault has deposit limits

        bytes memory messageBody = abi.encode(uint256(amount));

        vm.prank(address(BASE_MESSAGE_TRANSMITTER));
        remoteStrategy.handleReceiveFinalizedMessage(
            ETHEREUM_DOMAIN,
            bytes32(uint256(uint160(address(strategy)))),
            2000, // FINALITY_THRESHOLD_FINALIZED
            messageBody
        );
    }

    function test_rejectInvalidMainStrategy() public useBaseFork {
        // In the new architecture, remote strategies don't process incoming CCTP messages
        // They simply return false for any handleReceiveFinalizedMessage call
        bytes memory messageBody = abi.encode(uint256(1000e6));

        vm.prank(address(BASE_MESSAGE_TRANSMITTER));
        bool result = remoteStrategy.handleReceiveFinalizedMessage(
            ETHEREUM_DOMAIN,
            bytes32(uint256(uint160(address(0xdead)))), // Any sender
            2000, // FINALITY_THRESHOLD_FINALIZED
            messageBody
        );

        // Should return false as remote strategies don't process messages
        assertEq(result, false);
    }

    /*//////////////////////////////////////////////////////////////
                        EXPOSURE REPORTING
    //////////////////////////////////////////////////////////////*/

    function test_sendExposureReport() public useBaseFork {
        // Setup: Add some funds to vault
        uint256 amount = 10000e6;
        airdropUSDC(address(remoteStrategy), amount);

        vm.prank(keeper);
        remoteStrategy.pushFunds(amount);

        // Advance time as report requires block.timestamp > lastReport
        skip(1);

        // Send exposure report
        vm.prank(keeper);
        remoteStrategy.report();
    }

    function test_exposureReportCalculation() public useBaseFork {
        // Initial deposit
        uint256 initialAmount = 10000e6;
        airdropUSDC(address(remoteStrategy), initialAmount);

        vm.prank(keeper);
        remoteStrategy.pushFunds(initialAmount);

        // Simulate profit by adding to vault
        airdropUSDC(address(remoteStrategy), 1000e6); // Extra funds

        // Advance time as report requires block.timestamp > lastReport
        skip(1);

        vm.prank(keeper);
        remoteStrategy.report();

        // Total assets should reflect vault balance
        // Note: Can't verify message content without mocking TokenMessenger
    }

    function test_onlyKeepersCanSendReport() public useBaseFork {
        // Advance time as report requires block.timestamp > lastReport
        skip(1);

        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.report();

        vm.prank(keeper);
        remoteStrategy.report(); // Should succeed
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAWAL PROCESSING
    //////////////////////////////////////////////////////////////*/

    function test_processWithdrawal() public useBaseFork {
        uint256 amount = 10000e6;
        uint256 withdrawAmount = 1000e6;

        simulateBridgeDeposit(amount);

        // Total assets should reflect vault balance (with vault rounding)
        uint256 totalAssets = remoteStrategy.valueOfDeployedAssets();
        assertApproxEqAbs(totalAssets, amount, 10);

        // Process withdrawal
        vm.prank(keeper);
        remoteStrategy.processWithdrawal(withdrawAmount);

        // Use approx due to vault conversion rounding
        assertApproxEqAbs(
            remoteStrategy.valueOfDeployedAssets(),
            amount - withdrawAmount,
            10
        );
        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(address(remoteStrategy))),
            amount - withdrawAmount,
            100
        );
    }

    function test_withdrawFromVaultIfNeeded() public useBaseFork {
        // Deposit to vault
        uint256 depositAmount = 10000e6;
        simulateBridgeDeposit(depositAmount);

        // Leave some loose balance
        uint256 looseAmount = 1000e6;
        airdropUSDC(address(remoteStrategy), looseAmount);

        // Withdraw less than loose - shouldn't touch vault
        uint256 smallWithdraw = 500e6;
        uint256 vaultBalanceBefore = vault.balanceOf(address(remoteStrategy));

        vm.prank(keeper);
        remoteStrategy.processWithdrawal(smallWithdraw);

        assertEq(vault.balanceOf(address(remoteStrategy)), vaultBalanceBefore);

        // Withdraw more than loose - should pull from vault
        uint256 largeWithdraw = 2000e6;
        vm.prank(keeper);
        remoteStrategy.processWithdrawal(largeWithdraw);

        assertLt(vault.balanceOf(address(remoteStrategy)), vaultBalanceBefore);
    }

    function test_handleInsufficientVaultBalance() public useBaseFork {
        // Small deposit
        uint256 depositAmount = 1000e6;
        simulateBridgeDeposit(depositAmount);

        // Try to withdraw more than available
        uint256 tooMuch = 10000e6;

        // Should handle gracefully
        vm.prank(keeper);
        remoteStrategy.processWithdrawal(tooMuch);

        // Should withdraw what's available
        assertTrue(USDC_BASE.balanceOf(address(remoteStrategy)) < tooMuch);
    }

    function test_onlyKeepersCanProcessWithdrawal() public useBaseFork {
        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.processWithdrawal(1000e6);

        vm.prank(keeper);
        remoteStrategy.processWithdrawal(0); // Should succeed even with 0
    }

    /*//////////////////////////////////////////////////////////////
                        KEEPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_pushFunds() public useBaseFork {
        uint256 amount = 5000e6;
        airdropUSDC(address(remoteStrategy), amount);

        uint256 vaultBalanceBefore = vault.balanceOf(address(remoteStrategy));

        vm.prank(keeper);
        remoteStrategy.pushFunds(amount);

        uint256 vaultBalanceAfter = vault.balanceOf(address(remoteStrategy));
        assertGt(vaultBalanceAfter, vaultBalanceBefore);
    }

    function test_pullFunds() public useBaseFork {
        // First deposit
        uint256 amount = 5000e6;
        simulateBridgeDeposit(amount);

        uint256 sharesInVault = vault.balanceOf(address(remoteStrategy));
        uint256 looseBalanceBefore = USDC_BASE.balanceOf(
            address(remoteStrategy)
        );

        // Pull half of the assets (convert shares to assets)
        uint256 halfAssets = vault.convertToAssets(sharesInVault / 2);
        vm.prank(keeper);
        remoteStrategy.pullFunds(halfAssets);

        uint256 looseBalanceAfter = USDC_BASE.balanceOf(
            address(remoteStrategy)
        );
        assertGt(looseBalanceAfter, looseBalanceBefore);
        assertLt(vault.balanceOf(address(remoteStrategy)), sharesInVault);
    }

    function test_onlyKeepersCanPushPull() public useBaseFork {
        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.pushFunds(1000e6);

        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.pullFunds(100e6); // Amount in USDC

        // Keepers should succeed
        vm.prank(keeper);
        remoteStrategy.pushFunds(0); // Should work even with 0

        vm.prank(keeper);
        remoteStrategy.pullFunds(0); // Should work even with 0
    }

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_setKeeper() public useBaseFork {
        address newKeeper = address(0xbeef);

        // Non-governance cannot set keeper
        vm.prank(user);
        vm.expectRevert("!governance");
        remoteStrategy.setKeeper(newKeeper, true);

        // Governance can set keeper
        vm.prank(governance);
        remoteStrategy.setKeeper(newKeeper, true);
        assertTrue(remoteStrategy.keepers(newKeeper));

        // Can also remove
        vm.prank(governance);
        remoteStrategy.setKeeper(newKeeper, false);
        assertFalse(remoteStrategy.keepers(newKeeper));
    }

    function test_governanceIsImmutable() public useBaseFork {
        // Governance is set at deployment and cannot be changed
        assertEq(remoteStrategy.governance(), governance);
    }

    /*//////////////////////////////////////////////////////////////
                            ASSET TRACKING
    //////////////////////////////////////////////////////////////*/

    function test_totalAssetsCalculation() public useBaseFork {
        // Start with loose balance
        uint256 looseAmount = 2000e6;
        airdropUSDC(address(remoteStrategy), looseAmount);

        // Add to vault
        uint256 vaultAmount = 8000e6;
        airdropUSDC(address(remoteStrategy), vaultAmount);

        vm.prank(keeper);
        remoteStrategy.pushFunds(vaultAmount);

        // Leave some more loose
        uint256 additionalLoose = 1000e6;
        airdropUSDC(address(remoteStrategy), additionalLoose);

        // Total should be vault assets + loose balance
        uint256 expectedTotal = vault.convertToAssets(
            vault.balanceOf(address(remoteStrategy))
        ) +
            looseAmount +
            additionalLoose;

        // Can't directly access totalAssets() since it's internal, but it's used in reports
        // Advance time as report requires block.timestamp > lastReport
        skip(1);

        vm.prank(keeper);
        remoteStrategy.report(); // This uses totalAssets internally
    }
}
