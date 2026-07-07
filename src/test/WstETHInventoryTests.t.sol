// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {WstETHKatanaInventoryStrategy} from "../WstETHKatanaInventoryStrategy.sol";
import {KatanaRemoteInventory} from "../KatanaRemoteInventory.sol";
import {KatanaHelpers} from "../libraries/KatanaHelpers.sol";
import {WstETHOracle} from "../periphery/WstETHOracle.sol";
import {IKatanaInventoryStrategy} from "../interfaces/IKatanaInventoryStrategy.sol";
import {IVaultBridgeToken} from "../interfaces/lxly/IVaultBridgeToken.sol";
import {IwstETH} from "../interfaces/IStethInterfaces.sol";
import {MockExchange, MockForwarder} from "./utils/KatanaInventorySetup.sol";

interface IWstETHInventoryStrategy is IKatanaInventoryStrategy {
    function initiateCooldown(uint256 _amount) external returns (uint256);

    function claimCooldown(uint256 _claimId) external payable returns (uint256);
}

contract MockMorphoOracle {
    uint256 public price;

    constructor(uint256 _price) {
        price = _price;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }
}

/// @notice Mock Lido withdrawal queue used via vm.etch for claim tests.
///         Sends its full ETH balance to the claimer.
contract MockLidoQueue {
    function claimWithdrawal(uint256) external {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "!send");
    }
}

/// @notice Tests for the wstETH/WETH inventory pair on Katana. The diff vs
///         the stcUSD pair: wstETH bridges via LxLy (no OFT) and mainnet
///         redemption goes through the Lido withdrawal queue with pending
///         redemption accounting (LST looper pattern).
contract WstETHInventoryTests is Test {
    IWstETHInventoryStrategy public strategy;
    KatanaRemoteInventory public remoteInventory;
    MockExchange public exchange;
    MockForwarder public forwarder;
    WstETHOracle public wstEthOracle;
    MockMorphoOracle public katOracle;

    ERC20 public asset; // WETH
    ERC20 public collateral; // wstETH

    uint256 public ethFork;
    uint256 public katFork;

    // Ethereum
    address public constant WETH = KatanaHelpers.ETHEREUM_WETH;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant VB_WETH = KatanaHelpers.VB_WETH;
    address public constant WITHDRAWAL_QUEUE =
        0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
    address public constant UNIFIED_BRIDGE = KatanaHelpers.UNIFIED_BRIDGE;

    // Katana (LxLy-wrapped representations)
    address public constant KATANA_WETH =
        0xEE7D8BCFb72bC1880D0Cf19822eB0A2e6577aB62;
    address public constant KATANA_WSTETH =
        0x7Fb4D0f51544F24F385a421Db6e7D4fC71Ad8e5C;

    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public depositor = address(6);
    address public governance = address(7);
    address public looper = address(11);

    uint256 public MAX_BPS = 10_000;
    uint256 public discount = 50;

    /// @notice wstETH -> WETH price, 1e36 scaled (read from Lido on setup)
    uint256 public price;

    modifier useEthFork() {
        vm.selectFork(ethFork);
        _;
    }

    modifier useKatFork() {
        vm.selectFork(katFork);
        _;
    }

    function setUp() public {
        ethFork = vm.createFork(vm.envString("ETH_RPC_URL"));
        katFork = vm.createFork(vm.envString("KAT_RPC_URL"));

        // Read the live wstETH rate on Ethereum for the Katana mock oracle
        vm.selectFork(ethFork);
        asset = ERC20(WETH);
        collateral = ERC20(WSTETH);
        price = IwstETH(WSTETH).getStETHByWstETH(1e18) * 1e18;

        // --- Katana side ---
        vm.selectFork(katFork);

        katOracle = new MockMorphoOracle(price);

        remoteInventory = new KatanaRemoteInventory(
            KATANA_WETH,
            KATANA_WSTETH,
            address(katOracle),
            discount,
            governance,
            address(0), // no OFT: wstETH bridges home via LxLy
            address(0xDEAD)
        );

        forwarder = new MockForwarder();

        vm.startPrank(governance);
        remoteInventory.setKeeper(keeper);
        remoteInventory.setAllowedForwarder(address(forwarder), true);
        remoteInventory.setAllowed(looper, true);
        vm.stopPrank();

        // --- Ethereum side ---
        vm.selectFork(ethFork);

        wstEthOracle = new WstETHOracle();

        exchange = new MockExchange(WETH, WSTETH, address(wstEthOracle));
        deal(WETH, address(exchange), 100_000e18);
        deal(WSTETH, address(exchange), 100_000e18);

        strategy = IWstETHInventoryStrategy(
            address(
                new WstETHKatanaInventoryStrategy(
                    "Katana wstETH Inventory",
                    address(wstEthOracle),
                    address(exchange),
                    address(remoteInventory)
                )
            )
        );

        address currentManagement = strategy.management();

        vm.prank(currentManagement);
        strategy.setPendingManagement(management);

        vm.startPrank(management);
        strategy.acceptManagement();
        strategy.setKeeper(keeper);
        strategy.setAllowed(depositor, true);
        strategy.setLossLimitRatio(100);
        vm.stopPrank();

        vm.label(address(strategy), "WstETHKatanaInventoryStrategy");
        vm.label(address(remoteInventory), "KatanaRemoteInventory");
        vm.label(WSTETH, "wstETH");
        vm.label(WETH, "WETH");
        vm.label(WITHDRAWAL_QUEUE, "LidoQueue");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function depositWeth(uint256 _amount) internal {
        deal(WETH, depositor, _amount);
        vm.startPrank(depositor);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, depositor);
        vm.stopPrank();
    }

    function oracleValue(
        uint256 _collateralAmount
    ) internal view returns (uint256) {
        return Math.mulDiv(_collateralAmount, price, 1e36);
    }

    function simulateReportHome(uint256 _totalAssets) internal {
        vm.selectFork(ethFork);
        bytes memory data = abi.encode(
            _totalAssets,
            strategy.lastRemoteAssetsReport() + 1
        );
        vm.prank(UNIFIED_BRIDGE);
        strategy.onMessageReceived(
            address(remoteInventory),
            KatanaHelpers.KATANA_NETWORK_ID,
            data
        );
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/

    function test_setup() public useEthFork {
        assertEq(strategy.asset(), WETH);
        assertEq(strategy.collateral(), WSTETH);
        assertEq(address(strategy.VB_TOKEN()), VB_WETH);
        assertEq(address(strategy.COLLATERAL_OFT()), address(0));
        assertEq(strategy.REMOTE_COUNTERPART(), address(remoteInventory));
        assertEq(strategy.pendingRedemptions(), 0);
        assertTrue(strategy.allowed(depositor));

        vm.selectFork(katFork);
        assertEq(address(remoteInventory.COLLATERAL_OFT()), address(0));
        assertEq(address(remoteInventory.asset()), KATANA_WETH);
        assertEq(address(remoteInventory.collateral()), KATANA_WSTETH);
    }

    /*//////////////////////////////////////////////////////////////
                        LXLY COLLATERAL BRIDGING
    //////////////////////////////////////////////////////////////*/

    function test_bridgeCollateral_viaLxLy() public useEthFork {
        uint256 amount = 100e18;
        depositWeth(amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);

        uint256 collateralBalance = strategy.balanceOfCollateral();
        assertGt(collateralBalance, 0);

        vm.prank(keeper);
        strategy.bridgeCollateral(collateralBalance);

        // Native token escrowed in the bridge -- nothing left behind
        assertEq(strategy.balanceOfCollateral(), 0);
        // Credited at oracle value with no dust truncation (LxLy, not OFT)
        assertApproxEqAbs(
            strategy.remoteAssets(),
            oracleValue(collateralBalance),
            2
        );
        assertEq(strategy.lastRemoteAssetsReport(), block.timestamp);
    }

    function test_remote_bridgeCollateralHome_viaLxLy() public useKatFork {
        deal(KATANA_WSTETH, address(remoteInventory), 100e18);

        skip(1);
        vm.prank(keeper);
        remoteInventory.bridgeCollateral(40e18);

        // Wrapper burned by the LxLy bridge
        assertEq(
            ERC20(KATANA_WSTETH).balanceOf(address(remoteInventory)),
            60e18
        );
    }

    function test_bridgeAsset_viaVbEth() public useEthFork {
        uint256 amount = 100e18;
        depositWeth(amount);

        vm.prank(keeper);
        strategy.bridgeAsset(amount);

        assertEq(strategy.balanceOfAsset(), 0);
        assertEq(strategy.remoteAssets(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                        LIDO REDEMPTION QUEUE
    //////////////////////////////////////////////////////////////*/

    function test_initiateCooldown() public useEthFork {
        uint256 amount = 100e18;
        depositWeth(amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);

        uint256 collateralBalance = strategy.balanceOfCollateral();
        uint256 expectedSteth = IwstETH(WSTETH).getStETHByWstETH(
            collateralBalance
        );

        vm.prank(management);
        uint256 nftId = strategy.initiateCooldown(type(uint256).max);

        assertGt(nftId, 0, "!nftId");
        assertEq(strategy.balanceOfCollateral(), 0);
        // Pending tracked in asset (stETH ~ ETH) terms
        assertApproxEqAbs(
            strategy.pendingRedemptions(),
            expectedSteth,
            2,
            "!pending"
        );

        // Value is preserved in the live estimate
        assertApproxEqAbs(
            strategy.balanceOfAsset() + strategy.pendingRedemptions(),
            amount,
            1e15, // small wstETH rate vs 1:1 stETH rounding
            "!value"
        );
    }

    function test_initiateCooldown_onlyManagement() public useEthFork {
        vm.prank(keeper);
        vm.expectRevert(bytes("!management"));
        strategy.initiateCooldown(1e18);
    }

    function test_report_blockedWhilePending() public useEthFork {
        uint256 amount = 100e18;
        depositWeth(amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);

        vm.prank(management);
        strategy.initiateCooldown(type(uint256).max);

        vm.prank(keeper);
        vm.expectRevert(bytes("pending"));
        strategy.report();
    }

    function test_claimCooldown() public useEthFork {
        uint256 amount = 100e18;
        depositWeth(amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);

        vm.prank(management);
        uint256 nftId = strategy.initiateCooldown(type(uint256).max);

        uint256 pending = strategy.pendingRedemptions();
        assertGt(pending, 0);

        // Etch a mock queue that pays out the pending ETH on claim
        MockLidoQueue mock = new MockLidoQueue();
        vm.etch(WITHDRAWAL_QUEUE, address(mock).code);
        vm.deal(WITHDRAWAL_QUEUE, pending);

        vm.prank(keeper);
        uint256 assets = strategy.claimCooldown(nftId);

        assertEq(assets, pending, "!assets");
        assertEq(strategy.pendingRedemptions(), 0, "!cleared");
        assertApproxEqAbs(strategy.balanceOfAsset(), amount, 1e15, "!weth");

        // Reports work again after the claim
        vm.prank(keeper);
        strategy.report();
        assertApproxEqAbs(strategy.totalAssets(), amount, 1e15);
    }

    function test_claimCooldown_onlyKeepers() public useEthFork {
        vm.prank(user);
        vm.expectRevert(bytes("!keeper"));
        strategy.claimCooldown(1);
    }

    function test_zeroPendingRedemptions_escapeHatch() public useEthFork {
        uint256 amount = 100e18;
        depositWeth(amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);

        vm.prank(management);
        strategy.initiateCooldown(type(uint256).max);

        vm.prank(management);
        strategy.zeroPendingRedemptions();
        assertEq(strategy.pendingRedemptions(), 0);
    }

    function test_rescue_blocksSteth() public useEthFork {
        vm.startPrank(management);

        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(WETH, management, 1);

        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(WSTETH, management, 1);

        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(STETH, management, 1);

        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(VB_WETH, management, 1);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            E2E FLOW
    //////////////////////////////////////////////////////////////*/

    /// @notice Full redemption cycle: fund inventory with WETH, looper
    ///         levers down selling wstETH, collateral comes home via LxLy
    ///         and is redeemed through the Lido queue.
    function test_e2e_redemptionCycle() public {
        // NOTE: kept small -- the sovereign bridge can only burn as much
        // wrapped wstETH as was actually bridged in on the live fork.
        uint256 amount = 40e18;

        // 1. Treasury deposits WETH; keeper bridges it out as inventory
        vm.selectFork(ethFork);
        depositWeth(amount);

        vm.prank(keeper);
        strategy.bridgeAsset(amount);
        assertEq(strategy.remoteAssets(), amount);

        // 2. WETH arrives at the remote inventory
        vm.selectFork(katFork);
        deal(KATANA_WETH, address(remoteInventory), amount);

        // 3. Looper levers down: sells wstETH for WETH at the discount
        uint256 swapIn = 20e18;
        deal(KATANA_WSTETH, looper, swapIn);

        vm.prank(looper);
        ERC20(KATANA_WSTETH).approve(address(forwarder), swapIn);

        vm.prank(looper);
        uint256 out = forwarder.exchange(
            address(remoteInventory),
            KATANA_WSTETH,
            KATANA_WETH,
            swapIn,
            0
        );
        assertGt(out, 0);

        // 4. Keeper bridges the accumulated wstETH home (auto-reports)
        skip(1);
        uint256 remoteCollateral = remoteInventory.balanceOfCollateral();
        vm.prank(keeper);
        remoteInventory.bridgeCollateral(remoteCollateral);
        uint256 remoteTotal = remoteInventory.totalAssets();

        // 5. wstETH arrives on mainnet + fresh report
        vm.selectFork(ethFork);
        deal(WSTETH, address(strategy), remoteCollateral);
        simulateReportHome(remoteTotal);

        // 6. Redeem through the Lido queue
        vm.prank(management);
        uint256 nftId = strategy.initiateCooldown(type(uint256).max);

        uint256 pending = strategy.pendingRedemptions();

        MockLidoQueue mock = new MockLidoQueue();
        vm.etch(WITHDRAWAL_QUEUE, address(mock).code);
        vm.deal(WITHDRAWAL_QUEUE, pending);

        vm.prank(keeper);
        strategy.claimCooldown(nftId);

        // 7. Report books the discount spread as profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // 8. Treasury withdraws local WETH
        uint256 withdrawable = strategy.availableWithdrawLimit(depositor);
        assertGt(withdrawable, 0);

        vm.prank(depositor);
        strategy.withdraw(withdrawable, depositor, depositor);
        assertEq(asset.balanceOf(depositor), withdrawable);
    }

    /// @notice Lever-up supply cycle: mint wstETH, bridge via LxLy, looper
    ///         buys it with WETH.
    function test_e2e_leverUpCycle() public {
        uint256 amount = 100e18;

        vm.selectFork(ethFork);
        depositWeth(amount);

        // 1. Convert WETH -> wstETH and bridge to Katana
        vm.prank(keeper);
        strategy.convertToCollateral(amount);

        uint256 collateralBalance = strategy.balanceOfCollateral();
        vm.prank(keeper);
        strategy.bridgeCollateral(collateralBalance);

        // 2. wstETH arrives at the remote inventory
        vm.selectFork(katFork);
        deal(KATANA_WSTETH, address(remoteInventory), collateralBalance);

        // 3. Looper levers up: buys wstETH with WETH
        uint256 swapIn = 50e18;
        deal(KATANA_WETH, looper, swapIn);

        vm.prank(looper);
        ERC20(KATANA_WETH).approve(address(forwarder), swapIn);

        vm.prank(looper);
        forwarder.exchange(
            address(remoteInventory),
            KATANA_WETH,
            KATANA_WSTETH,
            swapIn,
            0
        );

        // 4. Remote reports home
        skip(1);
        vm.prank(keeper);
        (uint256 remoteTotal, ) = remoteInventory.report();

        simulateReportHome(remoteTotal);

        // 5. Origin report books the discount spread within health bounds
        vm.selectFork(ethFork);
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");
    }
}
