// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {KatanaInventorySetup, MockExchange} from "./utils/KatanaInventorySetup.sol";
import {IOracle} from "../interfaces/IOracle.sol";

contract MockJunk is ERC20 {
    constructor() ERC20("Junk", "JUNK") {
        _mint(msg.sender, 1_000_000e18);
    }
}

/// @notice Origin-side unit tests and full E2E flows for the Katana
///         inventory strategy pair.
contract KatanaInventoryTests is KatanaInventorySetup {
    uint256 internal ethPrice;

    function setUp() public override {
        super.setUp();
        vm.selectFork(ethFork);
        ethPrice = IOracle(STCUSD_ORACLE_ETH).price();
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP / CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_setup() public useEthFork {
        assertEq(strategy.asset(), USDC);
        assertEq(strategy.collateral(), STCUSD);
        assertEq(address(strategy.oracle()), STCUSD_ORACLE_ETH);
        assertEq(strategy.exchange(), address(exchange));
        assertEq(strategy.maxSlippageBps(), 50);
        assertEq(strategy.pendingRedemptions(), 0);
        assertTrue(strategy.allowed(depositor));
        assertFalse(strategy.open());
        assertEq(strategy.REMOTE_COUNTERPART(), address(remoteInventory));
        assertEq(strategy.REMOTE_CHAIN_ID(), 747474);
        assertEq(uint256(strategy.REMOTE_ID()), uint256(KATANA_NETWORK_ID));
        assertEq(address(strategy.VB_TOKEN()), VB_USDC);
        assertEq(address(strategy.COLLATERAL_OFT()), STCUSD_OFT_ADAPTER);
        assertEq(strategy.REMOTE_EID(), 30375);
        assertEq(strategy.management(), management);
        assertEq(strategy.keeper(), keeper);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSITS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_onlyDepositor() public useEthFork {
        assertEq(strategy.availableDepositLimit(depositor), type(uint256).max);
        assertEq(strategy.availableDepositLimit(user), 0);

        airdrop(asset, user, 1_000e6);
        vm.prank(user);
        asset.approve(address(strategy), 1_000e6);

        vm.prank(user);
        vm.expectRevert();
        strategy.deposit(1_000e6, user);
    }

    function test_deposit_doesNotBridge() public useEthFork {
        uint256 amount = 100_000e6;
        mintAndDepositIntoStrategy(strategy, depositor, amount);

        // Funds stay local until a keeper directs them
        assertEq(strategy.balanceOfAsset(), amount);
        assertEq(strategy.remoteAssets(), 0);
        assertEq(strategy.totalAssets(), amount);
        // Only local idle is withdrawable
        assertEq(strategy.availableWithdrawLimit(depositor), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            CONVERSIONS
    //////////////////////////////////////////////////////////////*/

    function test_convertToCollateral() public useEthFork {
        uint256 amount = 100_000e6;
        mintAndDepositIntoStrategy(strategy, depositor, amount);

        uint256 expected = Math.mulDiv(amount, 1e36, ethPrice);

        vm.prank(keeper);
        uint256 out = strategy.convertToCollateral(amount);

        assertEq(out, expected);
        assertEq(strategy.balanceOfAsset(), 0);
        assertEq(strategy.balanceOfCollateral(), expected);

        // Value is preserved (mock exchange fills exactly at oracle)
        assertApproxEqAbs(estimatedTotalAssets(), amount, 2);
    }

    function test_convertToAsset() public useEthFork {
        uint256 amount = 100_000e6;
        mintAndDepositIntoStrategy(strategy, depositor, amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);

        uint256 collateralBalance = strategy.balanceOfCollateral();

        vm.prank(keeper);
        uint256 out = strategy.convertToAsset(collateralBalance);

        assertApproxEqAbs(out, amount, 2);
        assertEq(strategy.balanceOfCollateral(), 0);
    }

    function test_convert_capsToBalance() public useEthFork {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, depositor, amount);

        // Requesting more than held converts only what is held
        vm.prank(keeper);
        strategy.convertToCollateral(type(uint256).max);

        assertEq(strategy.balanceOfAsset(), 0);
    }

    function test_convert_zeroReverts() public useEthFork {
        vm.prank(keeper);
        vm.expectRevert(bytes("ZeroAmount"));
        strategy.convertToCollateral(1_000e6);
    }

    function test_convert_slippageFloor() public useEthFork {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, depositor, amount);

        // Exchange skims 1% -- above the 0.5% oracle floor
        exchange.setSkim(100);

        vm.prank(keeper);
        vm.expectRevert(bytes("slippage"));
        strategy.convertToCollateral(amount);

        // Within the floor passes
        exchange.setSkim(10);
        vm.prank(keeper);
        strategy.convertToCollateral(amount);
    }

    function test_convert_onlyKeepers() public useEthFork {
        vm.prank(user);
        vm.expectRevert(bytes("!keeper"));
        strategy.convertToCollateral(1e6);

        vm.prank(user);
        vm.expectRevert(bytes("!keeper"));
        strategy.convertToAsset(1e6);
    }

    /*//////////////////////////////////////////////////////////////
                            BRIDGING
    //////////////////////////////////////////////////////////////*/

    function test_bridgeAsset() public useEthFork {
        uint256 amount = 100_000e6;
        mintAndDepositIntoStrategy(strategy, depositor, amount);

        vm.prank(keeper);
        strategy.bridgeAsset(amount);

        assertEq(strategy.balanceOfAsset(), 0);
        assertEq(strategy.remoteAssets(), amount);
        assertEq(strategy.lastRemoteAssetsReport(), block.timestamp);
        assertEq(strategy.totalAssets(), amount);
    }

    function test_bridgeCollateral() public useEthFork {
        uint256 amount = 100_000e6;
        mintAndDepositIntoStrategy(strategy, depositor, amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);

        uint256 collateralBalance = strategy.balanceOfCollateral();

        vm.prank(keeper);
        strategy.bridgeCollateral(collateralBalance);

        // Only shared-decimal dust stays behind
        assertLt(strategy.balanceOfCollateral(), 1e12);

        // Credited at oracle value of the dust-truncated amount
        uint256 sent = collateralBalance - (collateralBalance % 1e12);
        assertEq(strategy.remoteAssets(), Math.mulDiv(sent, ethPrice, 1e36));
        assertEq(strategy.lastRemoteAssetsReport(), block.timestamp);
    }

    function test_bridge_onlyKeepers() public useEthFork {
        vm.prank(user);
        vm.expectRevert(bytes("!keeper"));
        strategy.bridgeAsset(1e6);

        vm.prank(user);
        vm.expectRevert(bytes("!keeper"));
        strategy.bridgeCollateral(1e18);
    }

    function test_bridge_zeroReverts() public useEthFork {
        vm.prank(keeper);
        vm.expectRevert(bytes("ZeroAmount"));
        strategy.bridgeAsset(0);

        vm.prank(keeper);
        vm.expectRevert(bytes("ZeroAmount"));
        strategy.bridgeCollateral(0);
    }

    /*//////////////////////////////////////////////////////////////
                        MESSAGE HANDLING
    //////////////////////////////////////////////////////////////*/

    function test_staleReportIgnored() public useEthFork {
        uint256 amount = 100_000e6;
        mintAndDepositIntoStrategy(strategy, depositor, amount);

        vm.prank(keeper);
        strategy.bridgeAsset(amount);

        uint256 watermark = strategy.lastRemoteAssetsReport();

        // A report timestamped at (or before) the watermark is ignored
        simulateBridgeMessageAt(0, watermark);
        assertEq(strategy.remoteAssets(), amount);

        simulateBridgeMessageAt(0, watermark - 1);
        assertEq(strategy.remoteAssets(), amount);
    }

    function test_freshReportUpdates() public useEthFork {
        uint256 amount = 100_000e6;
        mintAndDepositIntoStrategy(strategy, depositor, amount);

        vm.prank(keeper);
        strategy.bridgeAsset(amount);

        uint256 watermark = strategy.lastRemoteAssetsReport();

        simulateBridgeMessageAt(amount + 500e6, watermark + 1);

        assertEq(strategy.remoteAssets(), amount + 500e6);
        assertEq(strategy.lastRemoteAssetsReport(), watermark + 1);
    }

    function test_onMessageReceived_validation() public useEthFork {
        bytes memory data = abi.encode(uint256(1e6), block.timestamp);

        // Not the bridge
        vm.expectRevert(bytes("InvalidBridge"));
        strategy.onMessageReceived(
            address(remoteInventory),
            KATANA_NETWORK_ID,
            data
        );

        // Wrong network
        vm.prank(UNIFIED_BRIDGE);
        vm.expectRevert(bytes("InvalidNetwork"));
        strategy.onMessageReceived(address(remoteInventory), 5, data);

        // Wrong counterpart
        vm.prank(UNIFIED_BRIDGE);
        vm.expectRevert(bytes("InvalidSender"));
        strategy.onMessageReceived(user, KATANA_NETWORK_ID, data);

        // Empty payload
        vm.prank(UNIFIED_BRIDGE);
        vm.expectRevert(bytes("EmptyMessage"));
        strategy.onMessageReceived(
            address(remoteInventory),
            KATANA_NETWORK_ID,
            ""
        );
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT / RESCUE
    //////////////////////////////////////////////////////////////*/

    function test_rescue_blocksProtectedTokens() public useEthFork {
        vm.startPrank(management);

        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(USDC, management, 1e6);

        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(STCUSD, management, 1e18);

        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(VB_USDC, management, 1e6);

        vm.stopPrank();
    }

    function test_rescue_allowsOtherTokens() public useEthFork {
        MockJunk junk = new MockJunk();
        junk.transfer(address(strategy), 100e18);

        vm.prank(management);
        strategy.rescue(address(junk), management, 100e18);
        assertEq(junk.balanceOf(management), 100e18);

        vm.expectRevert(bytes("!management"));
        strategy.rescue(address(junk), management, 0);
    }

    function test_rescueETH() public useEthFork {
        uint256 strategyBalance = address(strategy).balance;
        uint256 managementBalance = management.balance;

        vm.prank(management);
        strategy.rescueETH(management, 1 ether);

        assertEq(management.balance, managementBalance + 1 ether);
        assertEq(address(strategy).balance, strategyBalance - 1 ether);

        vm.expectRevert(bytes("!management"));
        strategy.rescueETH(user, 1 ether);
    }

    function test_setExchange_rotatesApprovals() public useEthFork {
        MockExchange newExchange = new MockExchange(
            USDC,
            STCUSD,
            STCUSD_ORACLE_ETH
        );

        address oldExchange = strategy.exchange();

        vm.prank(management);
        strategy.setExchange(address(newExchange));

        assertEq(strategy.exchange(), address(newExchange));
        assertEq(asset.allowance(address(strategy), oldExchange), 0);
        assertEq(collateral.allowance(address(strategy), oldExchange), 0);
        assertEq(
            asset.allowance(address(strategy), address(newExchange)),
            type(uint256).max
        );
        assertEq(
            collateral.allowance(address(strategy), address(newExchange)),
            type(uint256).max
        );

        vm.expectRevert(bytes("!management"));
        strategy.setExchange(address(newExchange));
    }

    function test_setMaxSlippageBps() public useEthFork {
        vm.prank(management);
        strategy.setMaxSlippageBps(100);
        assertEq(strategy.maxSlippageBps(), 100);

        vm.prank(management);
        vm.expectRevert(bytes("!bps"));
        strategy.setMaxSlippageBps(MAX_BPS);

        vm.expectRevert(bytes("!management"));
        strategy.setMaxSlippageBps(100);
    }

    function test_setOracle() public useEthFork {
        vm.prank(management);
        vm.expectRevert(bytes("ZeroAddress"));
        strategy.setOracle(address(0));

        vm.prank(management);
        strategy.setOracle(STCUSD_ORACLE_ETH);
        assertEq(address(strategy.oracle()), STCUSD_ORACLE_ETH);

        vm.expectRevert(bytes("!management"));
        strategy.setOracle(STCUSD_ORACLE_ETH);
    }

    function test_zeroPendingRedemptions() public useEthFork {
        vm.prank(management);
        strategy.zeroPendingRedemptions();
        assertEq(strategy.pendingRedemptions(), 0);

        vm.expectRevert(bytes("!management"));
        strategy.zeroPendingRedemptions();
    }

    /*//////////////////////////////////////////////////////////////
                            REPORTING
    //////////////////////////////////////////////////////////////*/

    function test_report_countsBothTokens() public useEthFork {
        uint256 amount = 100_000e6;
        mintAndDepositIntoStrategy(strategy, depositor, amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount / 2);

        vm.prank(keeper);
        strategy.report();

        assertApproxEqAbs(strategy.totalAssets(), estimatedTotalAssets(), 2);
        assertApproxEqAbs(strategy.totalAssets(), amount, 2);
    }

    function test_report_redeemsVbTokens() public useEthFork {
        uint256 amount = 50_000e6;

        // Deposit and bridge out so the return leg has a base to settle into
        mintAndDepositIntoStrategy(strategy, depositor, amount);
        vm.prank(keeper);
        strategy.bridgeAsset(amount);

        // Simulate the USDC coming home from Katana as vbUSDC plus the
        // remote reporting it no longer holds the funds
        simulateVbUsdcArrival(amount);
        simulateBridgeMessage(0);

        assertApproxEqAbs(strategy.valueOfVault(), amount, 2);

        vm.prank(keeper);
        strategy.report();

        // vbUSDC was redeemed into loose USDC during harvest
        assertEq(strategy.valueOfVault(), 0);
        assertApproxEqAbs(strategy.balanceOfAsset(), amount, 2);
        assertApproxEqAbs(strategy.totalAssets(), amount, 2);
    }

    /*//////////////////////////////////////////////////////////////
                            E2E FLOWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Full lever-up supply cycle:
    ///         deposit -> convert -> bridge collateral out -> looper buys
    ///         collateral with USDC -> report home -> bridge USDC home ->
    ///         withdraw.
    function test_e2e_leverUpCycle() public {
        uint256 amount = 100_000e6;

        // 1. Treasury deposits USDC on mainnet
        vm.selectFork(ethFork);
        mintAndDepositIntoStrategy(strategy, depositor, amount);
        checkInventoryInvariant();

        // 2. Keeper converts USDC -> stcUSD
        vm.prank(keeper);
        strategy.convertToCollateral(amount);
        uint256 collateralBalance = strategy.balanceOfCollateral();

        // 3. Keeper bridges stcUSD to Katana via OFT
        vm.prank(keeper);
        strategy.bridgeCollateral(collateralBalance);
        uint256 sent = collateralBalance - (collateralBalance % 1e12);
        assertGt(strategy.remoteAssets(), 0);

        // 4. stcUSD arrives at the remote inventory
        simulateArrivalOnKatana(KATANA_STCUSD, sent);

        // 5. Looper levers up: swaps USDC for stcUSD against the inventory
        uint256 swapIn = 50_000e6;
        uint256 out = looperSwap(KATANA_USDC, KATANA_STCUSD, swapIn);
        assertGt(out, 0);
        assertEq(
            ERC20(KATANA_USDC).balanceOf(address(remoteInventory)),
            swapIn
        );

        // 6. Remote reports total assets home
        vm.selectFork(katFork);
        skip(1);
        vm.prank(keeper);
        (uint256 remoteTotal, ) = remoteInventory.report();

        simulateBridgeMessage(remoteTotal);
        assertEq(strategy.remoteAssets(), remoteTotal);

        // 7. Origin report books the discount spread within health bounds
        vm.selectFork(ethFork);
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        checkInventoryInvariant();
        // Discount spread should outweigh any small oracle divergence
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // 8. Keeper bridges the accumulated USDC home
        vm.selectFork(katFork);
        skip(1);
        vm.prank(keeper);
        remoteInventory.processWithdrawal(swapIn);

        uint256 remoteTotalAfter = remoteInventory.totalAssets();

        // 9. USDC arrives home as vbUSDC + fresh report
        simulateVbUsdcArrival(swapIn);
        simulateBridgeMessage(remoteTotalAfter);

        // 10. Report redeems the vbUSDC into withdrawable USDC
        vm.selectFork(ethFork);
        vm.prank(keeper);
        strategy.report();
        checkInventoryInvariant();

        assertApproxEqAbs(strategy.balanceOfAsset(), swapIn, 2);

        // 11. Treasury can withdraw the local balance
        uint256 withdrawable = strategy.availableWithdrawLimit(depositor);
        assertApproxEqAbs(withdrawable, swapIn, 2);

        uint256 balanceBefore = asset.balanceOf(depositor);
        vm.prank(depositor);
        strategy.withdraw(withdrawable, depositor, depositor);
        assertEq(asset.balanceOf(depositor), balanceBefore + withdrawable);
    }

    /// @notice Full lever-down replenish cycle:
    ///         deposit -> bridge USDC out -> looper sells collateral for
    ///         USDC -> bridge collateral home -> redeem -> withdraw.
    function test_e2e_leverDownCycle() public {
        uint256 amount = 100_000e6;

        // 1. Treasury deposits USDC on mainnet
        vm.selectFork(ethFork);
        mintAndDepositIntoStrategy(strategy, depositor, amount);

        // 2. Keeper bridges USDC to Katana to replenish inventory
        vm.prank(keeper);
        strategy.bridgeAsset(amount);
        assertEq(strategy.remoteAssets(), amount);

        // 3. USDC arrives at the remote inventory
        simulateArrivalOnKatana(KATANA_USDC, amount);

        // 4. Looper levers down: sells stcUSD for USDC
        uint256 swapIn = 50_000e18;
        uint256 out = looperSwap(KATANA_STCUSD, KATANA_USDC, swapIn);
        assertGt(out, 0);

        // 5. Keeper bridges accumulated stcUSD home (reports automatically)
        vm.selectFork(katFork);
        skip(1);

        uint256 remoteCollateral = remoteInventory.balanceOfCollateral();
        vm.prank(keeper);
        remoteInventory.bridgeCollateral(remoteCollateral);

        uint256 remoteTotalAfter = remoteInventory.totalAssets();
        uint256 sent = remoteCollateral - (remoteCollateral % 1e12);

        // 6. stcUSD arrives on mainnet + fresh report
        simulateArrivalOnEthereum(STCUSD, sent);
        simulateBridgeMessage(remoteTotalAfter);

        // 7. Keeper redeems stcUSD -> USDC through the exchange
        vm.selectFork(ethFork);
        vm.prank(keeper);
        strategy.convertToAsset(sent);

        // 8. Report and verify the discount spread accrued
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        checkInventoryInvariant();
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // 9. Treasury withdraws what is local
        uint256 withdrawable = strategy.availableWithdrawLimit(depositor);
        assertGt(withdrawable, 0);

        vm.prank(depositor);
        strategy.withdraw(withdrawable, depositor, depositor);
        assertEq(asset.balanceOf(depositor), withdrawable);
    }
}
