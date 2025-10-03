// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public useEthFork {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, depositor, _amount);

        // Ensure strategy has local balance
        airdropUSDC(address(strategy), _amount);

        vm.prank(keeper);
        strategy.report();

        assertEq(strategy.totalAssets(), _amount * 2, "!totalAssets");

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount * 2, "!totalAssets");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = USDC_ETHEREUM.balanceOf(depositor);

        // Withdraw available funds
        vm.prank(depositor);
        strategy.withdraw(_amount, depositor, depositor);

        assertGe(
            USDC_ETHEREUM.balanceOf(depositor),
            balanceBefore + _amount,
            "!final balance"
        );
    }
}
