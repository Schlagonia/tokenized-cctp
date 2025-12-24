// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {KatanaSetup, MockVault, MockERC20} from "./utils/KatanaSetup.sol";
import {KatanaStrategy} from "../KatanaStrategy.sol";
import {KatanaRemoteStrategy} from "../KatanaRemoteStrategy.sol";
import {KatanaHelpers} from "../libraries/KatanaHelpers.sol";
import {IKatanaStrategy} from "../interfaces/IKatanaStrategy.sol";
import {IVaultBridgeToken} from "../interfaces/lxly/IVaultBridgeToken.sol";
import {IPolygonZkEVMBridgeV2} from "../interfaces/lxly/IPolygonZkEVMBridgeV2.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/*//////////////////////////////////////////////////////////////
            KATANA STRATEGY CONSTRUCTOR TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaStrategyConstructorTest
/// @notice Tests for KatanaStrategy constructor and initialization
contract KatanaStrategyConstructorTest is KatanaSetup {
    function setUp() public override {
        // Only create forks, don't deploy full setup yet
        string memory ethRpc = vm.envString("ETH_RPC_URL");
        string memory katRpc = vm.envString("KAT_RPC_URL");

        require(bytes(ethRpc).length > 0, "ETH_RPC_URL required");
        require(bytes(katRpc).length > 0, "KAT_RPC_URL required");

        ethFork = vm.createFork(ethRpc);
        katFork = vm.createFork(katRpc);

        vm.selectFork(ethFork);

        asset = ERC20(USDC);
        vbToken = IVaultBridgeToken(VB_USDC);
        lxlyBridge = IPolygonZkEVMBridgeV2(UNIFIED_BRIDGE);
        decimals = asset.decimals();
    }

    function test_constructor_success() public useEthFork {
        address remoteCounterpart = address(0xBEEF);

        IKatanaStrategy newStrategy = IKatanaStrategy(
            address(
                new KatanaStrategy(
                    USDC,
                    "Katana USDC Strategy",
                    VB_USDC,
                    UNIFIED_BRIDGE,
                    KATANA_NETWORK_ID,
                    remoteCounterpart,
                    depositor
                )
            )
        );

        // Verify immutables
        assertEq(newStrategy.asset(), USDC, "Asset mismatch");
        assertEq(address(newStrategy.VB_TOKEN()), VB_USDC, "VB_TOKEN mismatch");
        assertEq(
            address(newStrategy.LXLY_BRIDGE()),
            UNIFIED_BRIDGE,
            "Bridge mismatch"
        );
        assertEq(
            newStrategy.REMOTE_ID(),
            bytes32(uint256(KATANA_NETWORK_ID)),
            "Remote ID mismatch"
        );
        assertEq(
            newStrategy.REMOTE_COUNTERPART(),
            remoteCounterpart,
            "Remote counterpart mismatch"
        );
        assertEq(newStrategy.DEPOSITER(), depositor, "Depositer mismatch");
    }

    function test_constructor_verifyRealVbTokenProperties() public useEthFork {
        // Test that the real VB_USDC contract works as expected
        uint256 testAmount = 1000e6;

        // Airdrop USDC
        deal(USDC, address(this), testAmount);
        IERC20(USDC).approve(VB_USDC, testAmount);

        // Deposit into vbToken
        uint256 sharesBefore = vbToken.balanceOf(address(this));
        uint256 shares = vbToken.deposit(testAmount, address(this));

        assertGt(shares, 0, "Should receive vbToken shares");
        assertEq(
            vbToken.balanceOf(address(this)),
            sharesBefore + shares,
            "Balance should increase"
        );

        // Verify convertToAssets works
        uint256 assets = vbToken.convertToAssets(shares);
        assertApproxEqAbs(
            assets,
            testAmount,
            10,
            "Assets should match deposit"
        );
    }

    function test_constructor_approvalSetToVbToken() public useEthFork {
        address remoteCounterpart = address(0xBEEF);

        IKatanaStrategy newStrategy = IKatanaStrategy(
            address(
                new KatanaStrategy(
                    USDC,
                    "Katana USDC Strategy",
                    VB_USDC,
                    UNIFIED_BRIDGE,
                    KATANA_NETWORK_ID,
                    remoteCounterpart,
                    depositor
                )
            )
        );

        // Check approval to vbToken is max
        uint256 allowance = IERC20(USDC).allowance(
            address(newStrategy),
            VB_USDC
        );
        assertEq(allowance, type(uint256).max, "Approval not set to max");
    }

    function test_constructor_zeroVbToken_reverts() public useEthFork {
        address remoteCounterpart = address(0xBEEF);

        vm.expectRevert("ZeroVbToken");
        new KatanaStrategy(
            USDC,
            "Katana USDC Strategy",
            address(0),
            UNIFIED_BRIDGE,
            KATANA_NETWORK_ID,
            remoteCounterpart,
            depositor
        );
    }

    function test_constructor_assetMismatch_reverts() public useEthFork {
        address remoteCounterpart = address(0xBEEF);

        // VB_WETH has WETH as underlying, not USDC
        vm.expectRevert("AssetMismatch");
        new KatanaStrategy(
            USDC,
            "Katana USDC Strategy",
            VB_WETH,
            UNIFIED_BRIDGE,
            KATANA_NETWORK_ID,
            remoteCounterpart,
            depositor
        );
    }

    function test_constructor_zeroRemoteCounterpart_reverts()
        public
        useEthFork
    {
        vm.expectRevert("ZeroAddress");
        new KatanaStrategy(
            USDC,
            "Katana USDC Strategy",
            VB_USDC,
            UNIFIED_BRIDGE,
            KATANA_NETWORK_ID,
            address(0),
            depositor
        );
    }

    function test_constructor_zeroDepositor_reverts() public useEthFork {
        address remoteCounterpart = address(0xBEEF);

        vm.expectRevert("ZeroAddress");
        new KatanaStrategy(
            USDC,
            "Katana USDC Strategy",
            VB_USDC,
            UNIFIED_BRIDGE,
            KATANA_NETWORK_ID,
            remoteCounterpart,
            address(0)
        );
    }

    function test_constructor_zeroBridge_reverts() public useEthFork {
        address remoteCounterpart = address(0xBEEF);

        vm.expectRevert("ZeroAddress");
        new KatanaStrategy(
            USDC,
            "Katana USDC Strategy",
            VB_USDC,
            address(0),
            KATANA_NETWORK_ID,
            remoteCounterpart,
            depositor
        );
    }

    function test_constructor_localNetworkIdFromBridge() public useEthFork {
        address remoteCounterpart = address(0xBEEF);

        IKatanaStrategy newStrategy = IKatanaStrategy(
            address(
                new KatanaStrategy(
                    USDC,
                    "Katana USDC Strategy",
                    VB_USDC,
                    UNIFIED_BRIDGE,
                    KATANA_NETWORK_ID,
                    remoteCounterpart,
                    depositor
                )
            )
        );

        // LOCAL_NETWORK_ID should be fetched from bridge
        assertEq(
            newStrategy.LOCAL_NETWORK_ID(),
            ETHEREUM_NETWORK_ID,
            "Local network ID should be 0 (Ethereum)"
        );
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA STRATEGY DEPOSIT AND BRIDGE TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaStrategyDepositBridgeTest
/// @notice Tests for deposit and bridge functionality
contract KatanaStrategyDepositBridgeTest is KatanaSetup {
    function setUp() public override {
        super.setUp();
        vm.selectFork(ethFork);
    }

    function test_deposit_callsVbTokenDepositAndBridge() public useEthFork {
        uint256 depositAmount = 10_000e6;

        // Fund depositor with USDC
        airdropUSDC(depositor, depositAmount);

        uint256 usdcBefore = IERC20(USDC).balanceOf(address(strategy));
        uint256 remoteAssetsBefore = strategy.remoteAssets();

        // Depositor approves and deposits
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, depositor);
        vm.stopPrank();

        // Verify remoteAssets increased (funds were bridged)
        assertEq(
            strategy.remoteAssets(),
            remoteAssetsBefore + depositAmount,
            "Remote assets should increase by deposit amount"
        );

        // Verify no USDC left in strategy (all bridged via vbToken)
        assertEq(
            IERC20(USDC).balanceOf(address(strategy)),
            usdcBefore,
            "Strategy should have no USDC after bridge"
        );
    }

    function test_deposit_onlyDepositorCanDeposit() public useEthFork {
        // User (not depositor) should have 0 available deposit limit
        assertEq(
            strategy.availableDepositLimit(user),
            0,
            "User should not be able to deposit"
        );
        assertEq(
            strategy.availableDepositLimit(depositor),
            type(uint256).max,
            "Depositor should have max limit"
        );
    }

    function test_deposit_nonDepositorReverts() public useEthFork {
        uint256 depositAmount = 10_000e6;

        airdropUSDC(user, depositAmount);

        vm.startPrank(user);
        IERC20(USDC).approve(address(strategy), depositAmount);
        vm.expectRevert(); // ERC4626: deposit more than max
        strategy.deposit(depositAmount, user);
        vm.stopPrank();
    }

    function test_deposit_totalAssetsUpdates() public useEthFork {
        uint256 depositAmount = 50_000e6;

        uint256 totalAssetsBefore = strategy.totalAssets();

        airdropUSDC(depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, depositor);
        vm.stopPrank();

        // Total assets should increase by deposit amount
        assertEq(
            strategy.totalAssets(),
            totalAssetsBefore + depositAmount,
            "Total assets should increase"
        );
    }

    function test_deposit_multipleDeposits() public useEthFork {
        uint256 firstDeposit = 10_000e6;
        uint256 secondDeposit = 25_000e6;

        // First deposit
        airdropUSDC(depositor, firstDeposit);
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(strategy), firstDeposit);
        strategy.deposit(firstDeposit, depositor);
        vm.stopPrank();

        assertEq(strategy.remoteAssets(), firstDeposit, "After first deposit");

        // Second deposit
        airdropUSDC(depositor, secondDeposit);
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(strategy), secondDeposit);
        strategy.deposit(secondDeposit, depositor);
        vm.stopPrank();

        assertEq(
            strategy.remoteAssets(),
            firstDeposit + secondDeposit,
            "After second deposit"
        );
    }

    function test_deposit_sharesIssuedCorrectly() public useEthFork {
        uint256 depositAmount = 100_000e6;

        airdropUSDC(depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(strategy), depositAmount);
        uint256 shares = strategy.deposit(depositAmount, depositor);
        vm.stopPrank();

        // First deposit should mint 1:1 shares
        assertEq(shares, depositAmount, "Shares should equal deposit");
        assertEq(
            strategy.balanceOf(depositor),
            shares,
            "Depositor should have shares"
        );
    }

    function test_fuzz_deposit(uint256 _amount) public useEthFork {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        airdropUSDC(depositor, _amount);

        vm.startPrank(depositor);
        IERC20(USDC).approve(address(strategy), _amount);
        strategy.deposit(_amount, depositor);
        vm.stopPrank();

        assertEq(
            strategy.remoteAssets(),
            _amount,
            "Remote assets should match deposit"
        );
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA STRATEGY VB TOKEN REDEMPTION TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaStrategyVbTokenRedemptionTest
/// @notice Tests for vbToken redemption functionality
contract KatanaStrategyVbTokenRedemptionTest is KatanaSetup {
    function setUp() public override {
        super.setUp();
        vm.selectFork(ethFork);
    }

    function test_redeemVaultTokens_convertsToUnderlying() public useEthFork {
        uint256 vbAmount = 10_000e6;

        // Get vbToken into strategy
        getVbTokenIntoStrategy(vbAmount);

        // Verify strategy has vbToken
        uint256 vbBalance = vbToken.balanceOf(address(strategy));
        assertGt(vbBalance, 0, "Strategy should have vbToken");

        uint256 usdcBefore = IERC20(USDC).balanceOf(address(strategy));

        // Keeper redeems vbToken
        vm.prank(keeper);
        strategy.redeemVaultTokens();

        // Verify USDC received
        uint256 usdcAfter = IERC20(USDC).balanceOf(address(strategy));
        assertGt(
            usdcAfter,
            usdcBefore,
            "Should have more USDC after redemption"
        );

        // Verify no vbToken left
        assertEq(
            vbToken.balanceOf(address(strategy)),
            0,
            "Should have no vbToken after redemption"
        );
    }

    function test_redeemVaultTokens_onlyKeepers() public useEthFork {
        // Non-keeper cannot call redeemVaultTokens
        vm.prank(user);
        vm.expectRevert("!keeper");
        strategy.redeemVaultTokens();
    }

    function test_redeemVaultTokens_managementCanCall() public useEthFork {
        // Management should also be able to call
        vm.prank(management);
        strategy.redeemVaultTokens(); // Should not revert
    }

    function test_redeemVaultTokens_noOpWhenNoBalance() public useEthFork {
        // Should not revert when there's no vbToken to redeem
        uint256 usdcBefore = IERC20(USDC).balanceOf(address(strategy));

        vm.prank(keeper);
        strategy.redeemVaultTokens();

        uint256 usdcAfter = IERC20(USDC).balanceOf(address(strategy));
        assertEq(usdcAfter, usdcBefore, "No change when no vbToken");
    }

    function test_harvestAndReport_automaticallyRedeems() public useEthFork {
        mintAndDepositIntoStrategy(strategy, depositor, 10_000e6);

        // Get vbToken into strategy
        uint256 vbAmount = 1_000e6;
        getVbTokenIntoStrategy(vbAmount);

        uint256 vbBalanceBefore = vbToken.balanceOf(address(strategy));
        assertGt(vbBalanceBefore, 0, "Should have vbToken before report");

        // Simulate some remote assets being reported
        simulateBridgeMessage(10_000e6);

        // Trigger report which calls _harvestAndReport
        vm.prank(keeper);
        strategy.report();

        // vbToken should be redeemed during report
        assertEq(
            vbToken.balanceOf(address(strategy)),
            0,
            "vbToken should be redeemed during report"
        );
    }

    function test_redeemVaultTokens_largeAmount() public useEthFork {
        uint256 vbAmount = 500_000e6; // 500k USDC

        getVbTokenIntoStrategy(vbAmount);

        uint256 vbBalance = vbToken.balanceOf(address(strategy));
        assertGt(vbBalance, 0, "Should have vbToken");

        vm.prank(keeper);
        strategy.redeemVaultTokens();

        assertEq(
            vbToken.balanceOf(address(strategy)),
            0,
            "All vbToken should be redeemed"
        );
        assertGt(
            IERC20(USDC).balanceOf(address(strategy)),
            0,
            "Should have USDC"
        );
    }

    function test_fuzz_vbTokenRedemption(uint256 _amount) public useEthFork {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        getVbTokenIntoStrategy(_amount);

        uint256 vbBalance = vbToken.balanceOf(address(strategy));
        assertGt(vbBalance, 0, "Should have vbToken");

        vm.prank(keeper);
        strategy.redeemVaultTokens();

        assertEq(vbToken.balanceOf(address(strategy)), 0, "No vbToken left");
        assertGt(
            IERC20(USDC).balanceOf(address(strategy)),
            0,
            "Should have USDC"
        );
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA STRATEGY MESSAGE RECEPTION TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaStrategyMessageTest
/// @notice Tests for onMessageReceived and remoteAssets updates
contract KatanaStrategyMessageTest is KatanaSetup {
    function setUp() public override {
        super.setUp();
        vm.selectFork(ethFork);
    }

    function test_onMessageReceived_success() public useEthFork {
        uint256 reportedAssets = 15_000e6;

        bytes memory data = abi.encode(reportedAssets);

        vm.prank(UNIFIED_BRIDGE);
        strategy.onMessageReceived(
            address(remoteStrategy),
            KATANA_NETWORK_ID,
            data
        );

        assertEq(
            strategy.remoteAssets(),
            reportedAssets,
            "Remote assets not updated"
        );
    }

    function test_onMessageReceived_invalidBridge_reverts() public useEthFork {
        bytes memory data = abi.encode(uint256(10_000e6));

        vm.prank(user);
        vm.expectRevert("InvalidBridge");
        strategy.onMessageReceived(
            address(remoteStrategy),
            KATANA_NETWORK_ID,
            data
        );
    }

    function test_onMessageReceived_invalidNetwork_reverts() public useEthFork {
        bytes memory data = abi.encode(uint256(10_000e6));

        vm.prank(UNIFIED_BRIDGE);
        vm.expectRevert("InvalidNetwork");
        strategy.onMessageReceived(
            address(remoteStrategy),
            ETHEREUM_NETWORK_ID, // Wrong network
            data
        );
    }

    function test_onMessageReceived_invalidSender_reverts() public useEthFork {
        bytes memory data = abi.encode(uint256(10_000e6));

        vm.prank(UNIFIED_BRIDGE);
        vm.expectRevert("InvalidSender");
        strategy.onMessageReceived(
            address(0xDEAD), // Wrong sender
            KATANA_NETWORK_ID,
            data
        );
    }

    function test_onMessageReceived_emptyMessage_reverts() public useEthFork {
        bytes memory emptyData = "";

        vm.prank(UNIFIED_BRIDGE);
        vm.expectRevert("EmptyMessage");
        strategy.onMessageReceived(
            address(remoteStrategy),
            KATANA_NETWORK_ID,
            emptyData
        );
    }

    function test_onMessageReceived_profitReport() public useEthFork {
        // Set initial state
        uint256 initialAssets = 10_000e6;
        simulateBridgeMessage(initialAssets);
        assertEq(strategy.remoteAssets(), initialAssets);

        // Profit report
        uint256 profitAmount = 500e6;
        uint256 newTotal = initialAssets + profitAmount;
        simulateBridgeMessage(newTotal);

        assertEq(strategy.remoteAssets(), newTotal, "Should reflect profit");
    }

    function test_onMessageReceived_lossReport() public useEthFork {
        // Set initial state
        uint256 initialAssets = 10_000e6;
        simulateBridgeMessage(initialAssets);

        // Loss report
        uint256 lossAmount = 500e6;
        uint256 newTotal = initialAssets - lossAmount;
        simulateBridgeMessage(newTotal);

        assertEq(strategy.remoteAssets(), newTotal, "Should reflect loss");
    }

    function test_onMessageReceived_zeroReport() public useEthFork {
        // Set initial state
        uint256 initialAssets = 10_000e6;
        simulateBridgeMessage(initialAssets);

        // Report zero (complete loss)
        simulateBridgeMessage(0);

        assertEq(
            strategy.remoteAssets(),
            0,
            "Should be zero after complete loss"
        );
    }

    function test_fuzz_onMessageReceived(
        uint256 _reportedAssets
    ) public useEthFork {
        _reportedAssets = bound(_reportedAssets, 1, 1_000_000_000e6);

        bytes memory data = abi.encode(_reportedAssets);

        vm.prank(UNIFIED_BRIDGE);
        strategy.onMessageReceived(
            address(remoteStrategy),
            KATANA_NETWORK_ID,
            data
        );

        assertEq(strategy.remoteAssets(), _reportedAssets);
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA STRATEGY WITHDRAWAL FLOW TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaStrategyWithdrawalTest
/// @notice Tests for withdrawal flow including vbToken redemption
contract KatanaStrategyWithdrawalTest is KatanaSetup {
    function setUp() public override {
        super.setUp();
        vm.selectFork(ethFork);
    }

    function test_availableWithdrawLimit_noLocalBalance() public useEthFork {
        // Initially no local balance
        assertEq(
            strategy.availableWithdrawLimit(depositor),
            0,
            "No funds available initially"
        );
    }

    function test_availableWithdrawLimit_withLocalBalance() public useEthFork {
        uint256 localAmount = 50_000e6;

        // Airdrop USDC directly to strategy (simulating redeemed vbToken)
        airdropUSDC(address(strategy), localAmount);

        assertEq(
            strategy.availableWithdrawLimit(depositor),
            localAmount,
            "Should equal local balance"
        );
    }

    function test_withdrawalFlow_afterVbTokenRedemption() public useEthFork {
        uint256 depositAmount = 10_000e6;

        // 1. Depositor deposits (funds go to remote)
        airdropUSDC(depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, depositor);
        vm.stopPrank();

        // At this point, user has shares but no withdrawable balance
        uint256 withdrawLimit = strategy.availableWithdrawLimit(depositor);
        assertEq(withdrawLimit, 0, "No funds available yet");

        // 2. Simulate vbToken arriving from bridge claim
        getVbTokenIntoStrategy(depositAmount);

        // 3. Keeper redeems vbToken to USDC
        vm.prank(keeper);
        strategy.redeemVaultTokens();

        // 4. Now USDC is available for withdrawal
        uint256 strategyBalance = IERC20(USDC).balanceOf(address(strategy));
        assertGt(strategyBalance, 0, "Strategy should have USDC");

        withdrawLimit = strategy.availableWithdrawLimit(depositor);
        assertEq(withdrawLimit, strategyBalance, "Should be able to withdraw");

        // 5. Depositor can withdraw
        uint256 shares = strategy.balanceOf(depositor);
        vm.prank(depositor);
        strategy.redeem(shares, depositor, depositor);

        // Verify depositor received funds
        assertGt(
            IERC20(USDC).balanceOf(depositor),
            0,
            "Depositor should have USDC"
        );
    }

    function test_partialWithdrawal() public useEthFork {
        uint256 depositAmount = 100_000e6;

        // Deposit
        airdropUSDC(depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, depositor);
        vm.stopPrank();

        // Get vbToken and redeem (simulating partial return)
        uint256 partialReturn = 50_000e6;
        getVbTokenIntoStrategy(partialReturn);
        vm.prank(keeper);
        strategy.redeemVaultTokens();

        // Only partial withdrawal should be available
        uint256 withdrawLimit = strategy.availableWithdrawLimit(depositor);
        assertGt(withdrawLimit, 0, "Some funds available");
        assertLt(withdrawLimit, depositAmount, "Not all funds available");
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA STRATEGY RESCUE TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaStrategyRescueTest
/// @notice Tests for rescue functionality
contract KatanaStrategyRescueTest is KatanaSetup {
    MockERC20 public rescueToken;

    function setUp() public override {
        super.setUp();
        vm.selectFork(ethFork);
        rescueToken = new MockERC20("Rescue Token", "RESCUE", 18);
    }

    function test_rescue_success() public useEthFork {
        uint256 rescueAmount = 1000e18;

        deal(address(rescueToken), address(strategy), rescueAmount);

        vm.prank(management);
        strategy.rescue(address(rescueToken), user, rescueAmount);

        assertEq(rescueToken.balanceOf(user), rescueAmount);
        assertEq(rescueToken.balanceOf(address(strategy)), 0);
    }

    function test_rescue_asset_reverts() public useEthFork {
        uint256 rescueAmount = 1000e6;

        airdropUSDC(address(strategy), rescueAmount);

        vm.prank(management);
        vm.expectRevert("InvalidToken");
        strategy.rescue(address(asset), user, rescueAmount);
    }

    function test_rescue_partialAmount() public useEthFork {
        uint256 totalAmount = 1000e18;
        uint256 rescueAmount = 500e18;

        deal(address(rescueToken), address(strategy), totalAmount);

        vm.prank(management);
        strategy.rescue(address(rescueToken), user, rescueAmount);

        assertEq(rescueToken.balanceOf(user), rescueAmount);
        assertEq(
            rescueToken.balanceOf(address(strategy)),
            totalAmount - rescueAmount
        );
    }

    function test_rescue_nonManagement_reverts() public useEthFork {
        uint256 rescueAmount = 1000e18;

        deal(address(rescueToken), address(strategy), rescueAmount);

        vm.prank(user);
        vm.expectRevert("!management");
        strategy.rescue(address(rescueToken), user, rescueAmount);

        vm.prank(keeper);
        vm.expectRevert("!management");
        strategy.rescue(address(rescueToken), user, rescueAmount);
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA REMOTE STRATEGY CONSTRUCTOR TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaRemoteStrategyConstructorTest
/// @notice Tests for KatanaRemoteStrategy constructor
contract KatanaRemoteStrategyConstructorTest is KatanaSetup {
    function setUp() public override {
        // Only create forks
        string memory ethRpc = vm.envString("ETH_RPC_URL");
        string memory katRpc = vm.envString("KAT_RPC_URL");

        require(bytes(ethRpc).length > 0, "ETH_RPC_URL required");
        require(bytes(katRpc).length > 0, "KAT_RPC_URL required");

        ethFork = vm.createFork(ethRpc);
        katFork = vm.createFork(katRpc);

        vm.selectFork(katFork);

        // Deploy mock token on Katana
        katanaUsdc = address(new MockERC20("USDC", "USDC", 6));
    }

    function test_remote_constructor_success() public useKatFork {
        MockVault vault = new MockVault(katanaUsdc);
        address originCounterpart = address(0xBEEF);

        KatanaRemoteStrategy remote = new KatanaRemoteStrategy(
            katanaUsdc,
            governance,
            UNIFIED_BRIDGE,
            ETHEREUM_NETWORK_ID,
            originCounterpart,
            address(vault)
        );

        assertEq(address(remote.asset()), katanaUsdc, "Asset mismatch");
        assertEq(
            address(remote.LXLY_BRIDGE()),
            UNIFIED_BRIDGE,
            "Bridge mismatch"
        );
        assertEq(
            remote.REMOTE_ID(),
            bytes32(uint256(ETHEREUM_NETWORK_ID)),
            "Remote ID mismatch"
        );
        assertEq(
            remote.REMOTE_COUNTERPART(),
            originCounterpart,
            "Counterpart mismatch"
        );
        assertEq(address(remote.vault()), address(vault), "Vault mismatch");
        assertEq(remote.governance(), governance, "Governance mismatch");
    }

    function test_remote_constructor_zeroAsset_reverts() public useKatFork {
        MockVault vault = new MockVault(katanaUsdc);

        vm.expectRevert("ZeroAddress");
        new KatanaRemoteStrategy(
            address(0),
            governance,
            UNIFIED_BRIDGE,
            ETHEREUM_NETWORK_ID,
            address(0xBEEF),
            address(vault)
        );
    }

    function test_remote_constructor_zeroCounterpart_reverts()
        public
        useKatFork
    {
        MockVault vault = new MockVault(katanaUsdc);

        vm.expectRevert("ZeroAddress");
        new KatanaRemoteStrategy(
            katanaUsdc,
            governance,
            UNIFIED_BRIDGE,
            ETHEREUM_NETWORK_ID,
            address(0),
            address(vault)
        );
    }

    function test_remote_constructor_wrongVault_reverts() public useKatFork {
        address wrongAsset = address(new MockERC20("Wrong", "WRONG", 18));
        MockVault wrongVault = new MockVault(wrongAsset);

        vm.expectRevert("wrong vault");
        new KatanaRemoteStrategy(
            katanaUsdc,
            governance,
            UNIFIED_BRIDGE,
            ETHEREUM_NETWORK_ID,
            address(0xBEEF),
            address(wrongVault)
        );
    }

    function test_remote_constructor_vaultApprovalSet() public useKatFork {
        MockVault vault = new MockVault(katanaUsdc);

        KatanaRemoteStrategy remote = new KatanaRemoteStrategy(
            katanaUsdc,
            governance,
            UNIFIED_BRIDGE,
            ETHEREUM_NETWORK_ID,
            address(0xBEEF),
            address(vault)
        );

        uint256 allowance = IERC20(katanaUsdc).allowance(
            address(remote),
            address(vault)
        );
        assertEq(allowance, type(uint256).max, "Vault approval not set");
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA REMOTE STRATEGY VAULT TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaRemoteStrategyVaultTest
/// @notice Tests for remote strategy vault interactions
contract KatanaRemoteStrategyVaultTest is KatanaSetup {
    function setUp() public override {
        super.setUp();
        vm.selectFork(katFork);
    }

    function test_remote_pushFunds_depositsToVault() public useKatFork {
        uint256 depositAmount = 10_000e6;

        airdropUSDC(address(remoteStrategy), depositAmount);

        vm.prank(keeper);
        remoteStrategy.pushFunds(depositAmount);

        assertApproxEqAbs(
            remoteStrategy.valueOfDeployedAssets(),
            depositAmount,
            10,
            "Funds should be in vault"
        );

        assertEq(
            IERC20(katanaUsdc).balanceOf(address(remoteStrategy)),
            0,
            "No loose balance"
        );
    }

    function test_remote_pullFunds_withdrawsFromVault() public useKatFork {
        uint256 depositAmount = 10_000e6;
        uint256 pullAmount = 5_000e6;

        airdropUSDC(address(remoteStrategy), depositAmount);
        vm.prank(keeper);
        remoteStrategy.pushFunds(depositAmount);

        vm.prank(keeper);
        remoteStrategy.pullFunds(pullAmount);

        assertApproxEqAbs(
            remoteStrategy.valueOfDeployedAssets(),
            depositAmount - pullAmount,
            100,
            "Vault should have remaining"
        );

        assertApproxEqAbs(
            IERC20(katanaUsdc).balanceOf(address(remoteStrategy)),
            pullAmount,
            100,
            "Should have loose balance"
        );
    }

    function test_remote_totalAssets() public useKatFork {
        uint256 vaultAmount = 8_000e6;
        uint256 looseAmount = 2_000e6;

        airdropUSDC(address(remoteStrategy), vaultAmount);
        vm.prank(keeper);
        remoteStrategy.pushFunds(vaultAmount);

        airdropUSDC(address(remoteStrategy), looseAmount);

        uint256 total = remoteStrategy.totalAssets();
        assertApproxEqAbs(
            total,
            vaultAmount + looseAmount,
            10,
            "Should include vault + loose"
        );
    }

    function test_remote_pushFunds_onlyKeepers() public useKatFork {
        airdropUSDC(address(remoteStrategy), 1_000e6);

        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.pushFunds(1_000e6);
    }

    function test_remote_pullFunds_onlyKeepers() public useKatFork {
        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.pullFunds(1_000e6);
    }

    function test_remote_pushFunds_revertsWhenShutdown() public useKatFork {
        airdropUSDC(address(remoteStrategy), 1_000e6);

        vm.prank(governance);
        remoteStrategy.setIsShutdown(true);

        vm.prank(keeper);
        vm.expectRevert("Shutdown");
        remoteStrategy.pushFunds(1_000e6);
    }

    function test_remote_pullFunds_worksWhenShutdown() public useKatFork {
        uint256 depositAmount = 10_000e6;

        airdropUSDC(address(remoteStrategy), depositAmount);
        vm.prank(keeper);
        remoteStrategy.pushFunds(depositAmount);

        vm.prank(governance);
        remoteStrategy.setIsShutdown(true);

        // Pull funds should still work when shutdown
        vm.prank(keeper);
        remoteStrategy.pullFunds(5_000e6);

        assertGt(
            IERC20(katanaUsdc).balanceOf(address(remoteStrategy)),
            0,
            "Should have loose balance after pull"
        );
    }

    function test_fuzz_remote_pushFunds(uint256 _amount) public useKatFork {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        airdropUSDC(address(remoteStrategy), _amount);
        vm.prank(keeper);
        remoteStrategy.pushFunds(_amount);

        assertApproxEqAbs(
            remoteStrategy.valueOfDeployedAssets(),
            _amount,
            100,
            "Vault should have funds"
        );
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA REMOTE STRATEGY MESSAGE TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaRemoteStrategyMessageTest
/// @notice Tests for remote strategy message handling
contract KatanaRemoteStrategyMessageTest is KatanaSetup {
    function setUp() public override {
        super.setUp();
        vm.selectFork(katFork);
    }

    function test_remote_onMessageReceived_reverts() public useKatFork {
        bytes memory data = abi.encode(uint256(10_000e6));

        // onMessageReceived should always revert on remote strategy
        vm.prank(UNIFIED_BRIDGE);
        vm.expectRevert("NotSupported");
        remoteStrategy.onMessageReceived(
            address(strategy),
            ETHEREUM_NETWORK_ID,
            data
        );
    }

    function test_remote_onMessageReceived_revertsFromAnyone()
        public
        useKatFork
    {
        bytes memory data = abi.encode(uint256(10_000e6));

        vm.prank(user);
        vm.expectRevert("NotSupported");
        remoteStrategy.onMessageReceived(
            address(strategy),
            ETHEREUM_NETWORK_ID,
            data
        );

        vm.prank(governance);
        vm.expectRevert("NotSupported");
        remoteStrategy.onMessageReceived(
            address(strategy),
            ETHEREUM_NETWORK_ID,
            data
        );
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA REMOTE STRATEGY REPORT TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaRemoteStrategyReportTest
/// @notice Tests for remote strategy report functionality
contract KatanaRemoteStrategyReportTest is KatanaSetup {
    function setUp() public override {
        super.setUp();
        vm.selectFork(katFork);
    }

    function test_remote_report_success() public useKatFork {
        uint256 depositAmount = 50_000e6;

        airdropUSDC(address(remoteStrategy), depositAmount);

        skip(1);

        // Report should push funds and send message
        vm.prank(keeper);
        uint256 totalAssets = remoteStrategy.report();

        assertEq(totalAssets, depositAmount, "Total assets should match");
        assertEq(
            IERC20(katanaUsdc).balanceOf(address(remoteStrategy)),
            0,
            "All funds should be in vault after report"
        );
    }

    function test_remote_report_onlyKeepers() public useKatFork {
        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.report();
    }

    function test_remote_report_updatesLastReport() public useKatFork {
        uint256 lastReportBefore = remoteStrategy.lastReport();

        // Advance time
        vm.warp(block.timestamp + 1 days);

        vm.prank(keeper);
        remoteStrategy.report();

        assertGt(
            remoteStrategy.lastReport(),
            lastReportBefore,
            "Last report should be updated"
        );
    }

    function test_remote_report_notReadyIfSameBlock() public useKatFork {
        skip(1);

        // First report
        vm.prank(keeper);
        remoteStrategy.report();

        // Second report in same block should fail
        vm.prank(keeper);
        vm.expectRevert("NotReady");
        remoteStrategy.report();
    }

    function test_remote_report_pushesIdleFunds() public useKatFork {
        uint256 amount = 10_000e6;
        airdropUSDC(address(remoteStrategy), amount);

        skip(1);

        vm.prank(keeper);
        remoteStrategy.report();

        // All idle funds should be pushed to vault
        assertEq(
            IERC20(katanaUsdc).balanceOf(address(remoteStrategy)),
            0,
            "No idle funds after report"
        );
        assertApproxEqAbs(
            remoteStrategy.valueOfDeployedAssets(),
            amount,
            10,
            "All funds in vault"
        );
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA REMOTE STRATEGY KEEPER TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaRemoteStrategyKeeperTest
/// @notice Tests for keeper management
contract KatanaRemoteStrategyKeeperTest is KatanaSetup {
    function setUp() public override {
        super.setUp();
        vm.selectFork(katFork);
    }

    function test_remote_setKeeper() public useKatFork {
        address newKeeper = address(0xBEEF);

        vm.prank(governance);
        remoteStrategy.setKeeper(newKeeper, true);
        assertTrue(remoteStrategy.keepers(newKeeper));

        vm.prank(governance);
        remoteStrategy.setKeeper(newKeeper, false);
        assertFalse(remoteStrategy.keepers(newKeeper));
    }

    function test_remote_setKeeper_onlyGovernance() public useKatFork {
        vm.prank(user);
        vm.expectRevert("!governance");
        remoteStrategy.setKeeper(address(0xBEEF), true);

        vm.prank(keeper);
        vm.expectRevert("!governance");
        remoteStrategy.setKeeper(address(0xBEEF), true);
    }

    function test_remote_governanceIsKeeper() public useKatFork {
        // Governance should be able to call keeper functions
        airdropUSDC(address(remoteStrategy), 1_000e6);

        vm.prank(governance);
        remoteStrategy.pushFunds(1_000e6); // Should succeed
    }

    function test_remote_onlyKeepersFunctions() public useKatFork {
        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.report();

        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.pushFunds(1_000e6);

        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.pullFunds(1_000e6);

        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.processWithdrawal(1_000e6);

        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.tend();
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA REMOTE STRATEGY PROCESS WITHDRAWAL TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaRemoteStrategyProcessWithdrawalTest
/// @notice Tests for processWithdrawal functionality
contract KatanaRemoteStrategyProcessWithdrawalTest is KatanaSetup {
    function setUp() public override {
        super.setUp();
        vm.selectFork(katFork);
    }

    function test_remote_processWithdrawal_fromVault() public useKatFork {
        uint256 depositAmount = 100_000e6;
        uint256 withdrawAmount = 40_000e6;

        // Fund and deposit to vault
        airdropUSDC(address(remoteStrategy), depositAmount);
        vm.prank(keeper);
        remoteStrategy.pushFunds(depositAmount);

        uint256 vaultValueBefore = remoteStrategy.valueOfDeployedAssets();

        // Process withdrawal
        vm.prank(keeper);
        remoteStrategy.processWithdrawal(withdrawAmount);

        // Vault value should decrease
        assertLt(
            remoteStrategy.valueOfDeployedAssets(),
            vaultValueBefore,
            "Vault value should decrease"
        );
    }

    function test_remote_processWithdrawal_zeroAmount() public useKatFork {
        // Zero amount should be no-op
        vm.prank(keeper);
        remoteStrategy.processWithdrawal(0);
    }

    function test_remote_processWithdrawal_onlyKeepers() public useKatFork {
        vm.prank(user);
        vm.expectRevert("NotKeeper");
        remoteStrategy.processWithdrawal(1_000e6);
    }

    function test_remote_processWithdrawal_cappedToAvailable()
        public
        useKatFork
    {
        uint256 depositAmount = 50_000e6;

        airdropUSDC(address(remoteStrategy), depositAmount);
        vm.prank(keeper);
        remoteStrategy.pushFunds(depositAmount);

        // Request more than available
        vm.prank(keeper);
        remoteStrategy.processWithdrawal(100_000e6);

        // Should process max available (vault becomes empty)
        assertLe(
            remoteStrategy.valueOfDeployedAssets(),
            100,
            "Vault should be nearly empty"
        );
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA REMOTE STRATEGY RESCUE TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaRemoteStrategyRescueTest
/// @notice Tests for remote strategy rescue functionality
contract KatanaRemoteStrategyRescueTest is KatanaSetup {
    MockERC20 public rescueToken;

    function setUp() public override {
        super.setUp();
        vm.selectFork(katFork);
        rescueToken = new MockERC20("Rescue Token", "RESCUE", 18);
    }

    function test_remote_rescue_success() public useKatFork {
        uint256 rescueAmount = 1000e18;

        deal(address(rescueToken), address(remoteStrategy), rescueAmount);

        vm.prank(governance);
        remoteStrategy.rescue(address(rescueToken), user, rescueAmount);

        assertEq(rescueToken.balanceOf(user), rescueAmount);
        assertEq(rescueToken.balanceOf(address(remoteStrategy)), 0);
    }

    function test_remote_rescue_asset_reverts() public useKatFork {
        uint256 rescueAmount = 1000e6;

        airdropUSDC(address(remoteStrategy), rescueAmount);

        vm.prank(governance);
        vm.expectRevert("InvalidToken");
        remoteStrategy.rescue(katanaUsdc, user, rescueAmount);
    }

    function test_remote_rescue_vault_reverts() public useKatFork {
        uint256 depositAmount = 1000e6;

        airdropUSDC(address(remoteStrategy), depositAmount);
        vm.prank(keeper);
        remoteStrategy.pushFunds(depositAmount);

        uint256 vaultBalance = remoteVault.balanceOf(address(remoteStrategy));
        assertGt(vaultBalance, 0, "Should have vault shares");

        vm.prank(governance);
        vm.expectRevert("InvalidToken");
        remoteStrategy.rescue(address(remoteVault), user, vaultBalance);
    }

    function test_remote_rescue_onlyGovernance() public useKatFork {
        uint256 rescueAmount = 1000e18;

        deal(address(rescueToken), address(remoteStrategy), rescueAmount);

        vm.prank(user);
        vm.expectRevert("!governance");
        remoteStrategy.rescue(address(rescueToken), user, rescueAmount);

        vm.prank(keeper);
        vm.expectRevert("!governance");
        remoteStrategy.rescue(address(rescueToken), user, rescueAmount);

        vm.prank(management);
        vm.expectRevert("!governance");
        remoteStrategy.rescue(address(rescueToken), user, rescueAmount);
    }
}

/*//////////////////////////////////////////////////////////////
        KATANA REMOTE STRATEGY GOVERNANCE TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaRemoteStrategyGovernanceTest
/// @notice Tests for governance-only functions
contract KatanaRemoteStrategyGovernanceTest is KatanaSetup {
    function setUp() public override {
        super.setUp();
        vm.selectFork(katFork);
    }

    function test_remote_setIsShutdown() public useKatFork {
        assertFalse(remoteStrategy.isShutdown());

        vm.prank(governance);
        remoteStrategy.setIsShutdown(true);
        assertTrue(remoteStrategy.isShutdown());

        vm.prank(governance);
        remoteStrategy.setIsShutdown(false);
        assertFalse(remoteStrategy.isShutdown());
    }

    function test_remote_setIsShutdown_onlyGovernance() public useKatFork {
        vm.prank(user);
        vm.expectRevert("!governance");
        remoteStrategy.setIsShutdown(true);
    }

    function test_remote_setProfitMaxUnlockTime() public useKatFork {
        uint256 newTime = 14 days;

        vm.prank(governance);
        remoteStrategy.setProfitMaxUnlockTime(newTime);

        assertEq(remoteStrategy.profitMaxUnlockTime(), newTime);
    }

    function test_remote_setAmountToTend() public useKatFork {
        uint256 newAmount = 10_000e6;

        vm.prank(governance);
        remoteStrategy.setAmountToTend(newAmount);

        assertEq(remoteStrategy.amountToTend(), newAmount);
    }
}

/*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS
//////////////////////////////////////////////////////////////*/

/// @title KatanaIntegrationTest
/// @notice Full integration tests across both chains
contract KatanaIntegrationTest is KatanaSetup {
    function setUp() public override {
        super.setUp();
        vm.selectFork(ethFork);
    }

    function test_integration_fullDepositFlow() public {
        vm.selectFork(ethFork);

        uint256 depositAmount = 50_000e6;

        // 1. Depositor deposits USDC
        airdropUSDC(depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, depositor);
        vm.stopPrank();

        // 2. Verify remoteAssets updated
        assertEq(
            strategy.remoteAssets(),
            depositAmount,
            "Remote assets should match deposit"
        );

        // 3. Verify depositor has shares
        assertGt(
            strategy.balanceOf(depositor),
            0,
            "Depositor should have shares"
        );

        // 4. Verify no USDC left in strategy
        assertEq(
            IERC20(USDC).balanceOf(address(strategy)),
            0,
            "No USDC should remain"
        );
    }

    function test_integration_fullWithdrawalFlow() public {
        vm.selectFork(ethFork);

        uint256 depositAmount = 50_000e6;

        // 1. Initial deposit
        airdropUSDC(depositor, depositAmount);
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(strategy), depositAmount);
        strategy.deposit(depositAmount, depositor);
        vm.stopPrank();

        // 2. No funds available yet
        assertEq(
            strategy.availableWithdrawLimit(depositor),
            0,
            "No funds available"
        );

        // 3. Simulate vbToken arriving from Katana bridge claim
        getVbTokenIntoStrategy(depositAmount);

        // 4. Keeper redeems vbToken
        vm.prank(keeper);
        strategy.redeemVaultTokens();

        // 5. USDC now available
        uint256 availableBalance = IERC20(USDC).balanceOf(address(strategy));
        assertGt(availableBalance, 0, "USDC should be available");
        assertEq(
            strategy.availableWithdrawLimit(depositor),
            availableBalance,
            "Withdraw limit should match balance"
        );

        // 6. Depositor withdraws
        uint256 shares = strategy.balanceOf(depositor);
        vm.prank(depositor);
        strategy.redeem(shares, depositor, depositor);

        // 7. Verify depositor received USDC
        assertGt(
            IERC20(USDC).balanceOf(depositor),
            0,
            "Depositor should have USDC"
        );
    }

    function test_integration_profitReporting() public {
        vm.selectFork(ethFork);

        // 1. Set initial remote assets
        uint256 initialAssets = 100_000e6;

        mintAndDepositIntoStrategy(strategy, depositor, initialAssets);

        assertEq(strategy.remoteAssets(), initialAssets);

        // 2. Remote reports profit
        uint256 profit = 5_000e6;
        simulateBridgeMessage(initialAssets + profit);
        assertEq(
            strategy.remoteAssets(),
            initialAssets + profit,
            "Should reflect profit"
        );

        // 3. Report on strategy should include profit
        uint256 totalAssets = strategy.totalAssets();
        assertEq(
            totalAssets,
            initialAssets,
            "Total assets should be the initial assets"
        );

        vm.prank(keeper);
        strategy.report();

        assertEq(
            strategy.totalAssets(),
            initialAssets + profit,
            "Total assets should include profit"
        );
    }

    function test_integration_lossReporting() public {
        vm.selectFork(ethFork);

        // 1. Set initial remote assets
        uint256 initialAssets = 100_000e6;
        simulateBridgeMessage(initialAssets);

        // 2. Remote reports loss
        uint256 loss = 5_000e6;
        simulateBridgeMessage(initialAssets - loss);

        assertEq(
            strategy.remoteAssets(),
            initialAssets - loss,
            "Should reflect loss"
        );
    }

    function test_integration_remoteVaultOperations() public {
        vm.selectFork(katFork);

        uint256 depositAmount = 100_000e6;

        // 1. Fund remote strategy
        airdropUSDC(address(remoteStrategy), depositAmount);

        // 2. Push to vault
        vm.prank(keeper);
        remoteStrategy.pushFunds(depositAmount);

        assertApproxEqAbs(
            remoteStrategy.valueOfDeployedAssets(),
            depositAmount,
            10,
            "Funds in vault"
        );

        // 3. Simulate profit
        MockVault(address(remoteVault)).addProfit(5_000e6);

        uint256 newValue = remoteStrategy.valueOfDeployedAssets();
        assertApproxEqAbs(
            newValue,
            depositAmount + 5_000e6,
            100,
            "Should reflect profit"
        );

        // 4. Total assets includes profit
        assertApproxEqAbs(
            remoteStrategy.totalAssets(),
            depositAmount + 5_000e6,
            100,
            "Total assets with profit"
        );
    }

    function test_integration_remoteVaultLoss() public {
        vm.selectFork(katFork);

        uint256 depositAmount = 100_000e6;

        airdropUSDC(address(remoteStrategy), depositAmount);
        vm.prank(keeper);
        remoteStrategy.pushFunds(depositAmount);

        // Simulate loss
        MockVault(address(remoteVault)).simulateLoss(10_000e6);

        uint256 newValue = remoteStrategy.valueOfDeployedAssets();
        assertApproxEqAbs(
            newValue,
            depositAmount - 10_000e6,
            100,
            "Should reflect loss"
        );
    }

    function test_integration_completeReportCycle() public {
        // Test complete report cycle on Katana
        vm.selectFork(katFork);

        uint256 amount = 75_000e6;
        airdropUSDC(address(remoteStrategy), amount);

        skip(1);
        // Report should:
        // 1. Push idle funds to vault
        // 2. Calculate total assets
        // 3. Send message to origin
        vm.prank(keeper);
        uint256 reportedAssets = remoteStrategy.report();

        assertEq(reportedAssets, amount, "Reported assets should match");
        assertEq(
            IERC20(katanaUsdc).balanceOf(address(remoteStrategy)),
            0,
            "All funds pushed to vault"
        );
        assertApproxEqAbs(
            remoteStrategy.valueOfDeployedAssets(),
            amount,
            10,
            "Vault should have funds"
        );
    }

    function test_fuzz_integration_depositAndMessage(
        uint256 _depositAmount,
        uint256 _reportedAssets
    ) public {
        vm.selectFork(ethFork);

        _depositAmount = bound(_depositAmount, minFuzzAmount, maxFuzzAmount);
        _reportedAssets = bound(_reportedAssets, 1, 1_000_000_000e6);

        // Deposit
        airdropUSDC(depositor, _depositAmount);
        vm.startPrank(depositor);
        IERC20(USDC).approve(address(strategy), _depositAmount);
        strategy.deposit(_depositAmount, depositor);
        vm.stopPrank();

        assertEq(strategy.remoteAssets(), _depositAmount);

        // Message updates remote assets
        simulateBridgeMessage(_reportedAssets);
        assertEq(strategy.remoteAssets(), _reportedAssets);
    }
}
