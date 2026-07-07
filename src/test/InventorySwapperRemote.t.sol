// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {KatanaInventorySetup} from "./utils/KatanaInventorySetup.sol";
import {IOracle} from "../interfaces/IOracle.sol";

contract MockJunkToken is ERC20 {
    constructor() ERC20("Junk", "JUNK") {
        _mint(msg.sender, 1_000_000e18);
    }
}

/// @notice Unit tests for the inventory swapper side of KatanaRemoteInventory,
///         ported from the looper repo's InventorySwapper tests.
contract InventorySwapperRemoteTest is KatanaInventorySetup {
    uint256 internal price;

    function setUp() public override {
        super.setUp();
        vm.selectFork(katFork);
        price = IOracle(STCUSD_ORACLE_KAT).price();
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP / CONFIG
    //////////////////////////////////////////////////////////////*/

    function test_setup() public useKatFork {
        assertEq(address(remoteInventory.asset()), KATANA_USDC);
        assertEq(address(remoteInventory.collateral()), KATANA_STCUSD);
        assertEq(address(remoteInventory.oracle()), STCUSD_ORACLE_KAT);
        assertEq(remoteInventory.discount(), discount);
        assertEq(remoteInventory.governance(), governance);
        assertEq(remoteInventory.keeper(), keeper);
        assertTrue(remoteInventory.allowedForwarders(address(forwarder)));
        assertTrue(remoteInventory.allowed(looper));
        assertEq(
            uint256(remoteInventory.REMOTE_ID()),
            uint256(ETHEREUM_NETWORK_ID)
        );
        assertEq(remoteInventory.ORIGIN_EID(), 30101);

        address[] memory protected = remoteInventory.protectedTokens();
        assertEq(protected.length, 2);
        assertEq(protected[0], KATANA_USDC);
        assertEq(protected[1], KATANA_STCUSD);
    }

    /*//////////////////////////////////////////////////////////////
                            SWAP MATH
    //////////////////////////////////////////////////////////////*/

    function test_swap_assetToCollateral() public {
        uint256 amountIn = 10_000e6;

        // Fund the inventory with collateral
        simulateArrivalOnKatana(KATANA_STCUSD, 100_000e18);

        uint256 expected = Math.mulDiv(amountIn, 1e36, price);
        expected = (expected * (MAX_BPS - discount)) / MAX_BPS;

        uint256 out = looperSwap(KATANA_USDC, KATANA_STCUSD, amountIn);

        assertEq(out, expected, "!out");
        assertEq(
            ERC20(KATANA_STCUSD).balanceOf(looper),
            expected,
            "!looper coll"
        );
        assertEq(
            ERC20(KATANA_USDC).balanceOf(address(remoteInventory)),
            amountIn,
            "!inventory usdc"
        );
        assertEq(
            ERC20(KATANA_STCUSD).balanceOf(address(remoteInventory)),
            100_000e18 - expected,
            "!inventory coll"
        );
    }

    function test_swap_collateralToAsset() public {
        uint256 amountIn = 10_000e18;

        // Fund the inventory with asset
        simulateArrivalOnKatana(KATANA_USDC, 100_000e6);

        uint256 expected = Math.mulDiv(amountIn, price, 1e36);
        expected = (expected * (MAX_BPS - discount)) / MAX_BPS;

        uint256 out = looperSwap(KATANA_STCUSD, KATANA_USDC, amountIn);

        assertEq(out, expected, "!out");
        assertEq(ERC20(KATANA_USDC).balanceOf(looper), expected);
        assertEq(
            ERC20(KATANA_STCUSD).balanceOf(address(remoteInventory)),
            amountIn
        );
    }

    function test_swap_discountAccruesToInventory() public {
        uint256 amountIn = 10_000e6;
        simulateArrivalOnKatana(KATANA_STCUSD, 100_000e18);

        uint256 valueBefore = ERC20(KATANA_USDC).balanceOf(
            address(remoteInventory)
        ) +
            oracleValue(
                STCUSD_ORACLE_KAT,
                ERC20(KATANA_STCUSD).balanceOf(address(remoteInventory))
            );

        looperSwap(KATANA_USDC, KATANA_STCUSD, amountIn);

        uint256 valueAfter = ERC20(KATANA_USDC).balanceOf(
            address(remoteInventory)
        ) +
            oracleValue(
                STCUSD_ORACLE_KAT,
                ERC20(KATANA_STCUSD).balanceOf(address(remoteInventory))
            );

        // The discount is the inventory's spread
        uint256 expectedSpread = (amountIn * discount) / MAX_BPS;
        assertApproxEqAbs(valueAfter - valueBefore, expectedSpread, 2);
    }

    /*//////////////////////////////////////////////////////////////
                            SWAP REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_swap_notForwarder() public useKatFork {
        vm.expectRevert(bytes("!forwarder"));
        remoteInventory.exchangeWithContext(
            KATANA_USDC,
            KATANA_STCUSD,
            1e6,
            0,
            looper
        );
    }

    function test_swap_contextNotAllowed() public {
        simulateArrivalOnKatana(KATANA_STCUSD, 100_000e18);

        address randomCaller = address(77);
        vm.selectFork(katFork);
        airdrop(ERC20(KATANA_USDC), randomCaller, 1_000e6);

        vm.prank(randomCaller);
        ERC20(KATANA_USDC).approve(address(forwarder), 1_000e6);

        // Forwarder passes msg.sender as context -> not allowed
        vm.prank(randomCaller);
        vm.expectRevert(bytes("!allowed"));
        forwarder.exchange(
            address(remoteInventory),
            KATANA_USDC,
            KATANA_STCUSD,
            1_000e6,
            0
        );
    }

    function test_swap_invalidPair() public {
        vm.selectFork(katFork);
        airdrop(ERC20(KATANA_USDC), looper, 1_000e6);

        vm.prank(looper);
        ERC20(KATANA_USDC).approve(address(forwarder), 1_000e6);

        vm.prank(looper);
        vm.expectRevert(bytes("!pair"));
        forwarder.exchange(
            address(remoteInventory),
            KATANA_USDC,
            KATANA_USDC,
            1_000e6,
            0
        );
    }

    function test_swap_insufficientInventory() public {
        // Inventory has only 1 stcUSD
        simulateArrivalOnKatana(KATANA_STCUSD, 1e18);

        vm.selectFork(katFork);
        airdrop(ERC20(KATANA_USDC), looper, 10_000e6);

        vm.prank(looper);
        ERC20(KATANA_USDC).approve(address(forwarder), 10_000e6);

        vm.prank(looper);
        vm.expectRevert(bytes("!inventory"));
        forwarder.exchange(
            address(remoteInventory),
            KATANA_USDC,
            KATANA_STCUSD,
            10_000e6,
            0
        );
    }

    function test_swap_amountOutMin() public {
        simulateArrivalOnKatana(KATANA_STCUSD, 100_000e18);

        vm.selectFork(katFork);
        airdrop(ERC20(KATANA_USDC), looper, 1_000e6);

        vm.prank(looper);
        ERC20(KATANA_USDC).approve(address(forwarder), 1_000e6);

        vm.prank(looper);
        vm.expectRevert(bytes("!amountOut"));
        forwarder.exchange(
            address(remoteInventory),
            KATANA_USDC,
            KATANA_STCUSD,
            1_000e6,
            type(uint256).max
        );
    }

    function test_swap_zeroAmount() public {
        vm.selectFork(katFork);

        vm.prank(looper);
        uint256 out = forwarder.exchange(
            address(remoteInventory),
            KATANA_USDC,
            KATANA_STCUSD,
            0,
            0
        );

        assertEq(out, 0);
    }

    function test_swap_shutdown() public {
        simulateArrivalOnKatana(KATANA_STCUSD, 100_000e18);

        vm.selectFork(katFork);
        vm.prank(governance);
        remoteInventory.setIsShutdown(true);

        airdrop(ERC20(KATANA_USDC), looper, 1_000e6);

        vm.prank(looper);
        ERC20(KATANA_USDC).approve(address(forwarder), 1_000e6);

        vm.prank(looper);
        vm.expectRevert(bytes("Shutdown"));
        forwarder.exchange(
            address(remoteInventory),
            KATANA_USDC,
            KATANA_STCUSD,
            1_000e6,
            0
        );
    }

    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE SETTERS
    //////////////////////////////////////////////////////////////*/

    function test_setDiscount() public useKatFork {
        vm.prank(governance);
        remoteInventory.setDiscount(100);
        assertEq(remoteInventory.discount(), 100);

        vm.prank(governance);
        vm.expectRevert(bytes("!discount"));
        remoteInventory.setDiscount(MAX_BPS);

        vm.expectRevert(bytes("!governance"));
        remoteInventory.setDiscount(100);
    }

    function test_setAllowed() public useKatFork {
        vm.prank(governance);
        remoteInventory.setAllowed(address(88), true);
        assertTrue(remoteInventory.allowed(address(88)));

        vm.prank(governance);
        remoteInventory.setAllowed(address(88), false);
        assertFalse(remoteInventory.allowed(address(88)));

        vm.prank(governance);
        vm.expectRevert(bytes("ZeroAddress"));
        remoteInventory.setAllowed(address(0), true);

        vm.expectRevert(bytes("!governance"));
        remoteInventory.setAllowed(address(88), true);
    }

    function test_setAllowedForwarder() public useKatFork {
        vm.prank(governance);
        remoteInventory.setAllowedForwarder(address(88), true);
        assertTrue(remoteInventory.allowedForwarders(address(88)));

        vm.prank(governance);
        vm.expectRevert(bytes("ZeroAddress"));
        remoteInventory.setAllowedForwarder(address(0), true);

        vm.expectRevert(bytes("!governance"));
        remoteInventory.setAllowedForwarder(address(88), true);
    }

    function test_setOracle() public useKatFork {
        vm.prank(governance);
        remoteInventory.setOracle(STCUSD_ORACLE_KAT);
        assertEq(address(remoteInventory.oracle()), STCUSD_ORACLE_KAT);

        vm.prank(governance);
        vm.expectRevert(bytes("ZeroAddress"));
        remoteInventory.setOracle(address(0));

        vm.expectRevert(bytes("!governance"));
        remoteInventory.setOracle(STCUSD_ORACLE_KAT);
    }

    /*//////////////////////////////////////////////////////////////
                            RESCUE
    //////////////////////////////////////////////////////////////*/

    function test_rescue_blocksInventoryTokens() public {
        simulateArrivalOnKatana(KATANA_USDC, 1_000e6);
        simulateArrivalOnKatana(KATANA_STCUSD, 1_000e18);

        vm.selectFork(katFork);

        vm.prank(governance);
        vm.expectRevert(bytes("InvalidToken"));
        remoteInventory.rescue(KATANA_USDC, governance, 1_000e6);

        vm.prank(governance);
        vm.expectRevert(bytes("InvalidToken"));
        remoteInventory.rescue(KATANA_STCUSD, governance, 1_000e18);
    }

    function test_rescue_allowsOtherTokens() public useKatFork {
        MockJunkToken junk = new MockJunkToken();
        junk.transfer(address(remoteInventory), 100e18);

        vm.prank(governance);
        remoteInventory.rescue(address(junk), governance, 100e18);

        assertEq(junk.balanceOf(governance), 100e18);

        vm.expectRevert(bytes("!governance"));
        remoteInventory.rescue(address(junk), governance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        REPORT / BRIDGE OPS
    //////////////////////////////////////////////////////////////*/

    function test_report_valuesBothTokens() public {
        simulateArrivalOnKatana(KATANA_USDC, 10_000e6);
        simulateArrivalOnKatana(KATANA_STCUSD, 10_000e18);

        vm.selectFork(katFork);

        uint256 expected = 10_000e6 + oracleValue(STCUSD_ORACLE_KAT, 10_000e18);

        assertEq(remoteInventory.totalAssets(), expected);

        skip(1);
        vm.prank(keeper);
        (uint256 reported, ) = remoteInventory.report();

        assertEq(reported, expected);
    }

    function test_report_notReadyTwiceSameBlock() public useKatFork {
        skip(1);
        vm.prank(keeper);
        remoteInventory.report();

        vm.prank(keeper);
        vm.expectRevert(bytes("NotReady"));
        remoteInventory.report();
    }

    function test_report_onlyKeepers() public useKatFork {
        skip(1);
        vm.expectRevert(bytes("!keeper"));
        remoteInventory.report();
    }

    function test_processWithdrawal_bridgesAssetHome() public {
        simulateArrivalOnKatana(KATANA_USDC, 10_000e6);

        vm.selectFork(katFork);
        skip(1);

        vm.prank(keeper);
        remoteInventory.processWithdrawal(4_000e6);

        // Bridged tokens are burned by the LxLy bridge
        assertEq(
            ERC20(KATANA_USDC).balanceOf(address(remoteInventory)),
            6_000e6
        );
    }

    function test_bridgeCollateral_sendsOFTHome() public {
        simulateArrivalOnKatana(KATANA_STCUSD, 10_000e18);

        vm.selectFork(katFork);
        skip(1);

        uint256 ethBefore = address(remoteInventory).balance;

        vm.prank(keeper);
        remoteInventory.bridgeCollateral(4_000e18);

        // OFT burns the tokens on Katana
        assertEq(
            ERC20(KATANA_STCUSD).balanceOf(address(remoteInventory)),
            6_000e18
        );
        // A native LayerZero fee was paid
        assertLt(address(remoteInventory).balance, ethBefore);
    }

    function test_bridgeCollateral_capsToBalanceAndReverts() public {
        vm.selectFork(katFork);
        skip(1);

        vm.prank(keeper);
        vm.expectRevert(bytes("ZeroAmount"));
        remoteInventory.bridgeCollateral(1e18);

        vm.expectRevert(bytes("!keeper"));
        remoteInventory.bridgeCollateral(1e18);
    }

    function test_bridgeCollateral_notReadyTwiceSameBlock() public {
        simulateArrivalOnKatana(KATANA_STCUSD, 10_000e18);

        vm.selectFork(katFork);
        skip(1);

        vm.prank(keeper);
        remoteInventory.bridgeCollateral(1_000e18);

        vm.prank(keeper);
        vm.expectRevert(bytes("NotReady"));
        remoteInventory.bridgeCollateral(1_000e18);
    }

    function test_onMessageReceived_notSupported() public useKatFork {
        vm.prank(UNIFIED_BRIDGE);
        vm.expectRevert(bytes("NotSupported"));
        remoteInventory.onMessageReceived(address(1), 0, "");
    }
}
