// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {WeETHKatanaInventoryStrategy} from "../WeETHKatanaInventoryStrategy.sol";
import {KatanaRemoteInventory} from "../KatanaRemoteInventory.sol";
import {KatanaHelpers} from "../libraries/KatanaHelpers.sol";
import {WeETHOracle} from "../periphery/WeETHOracle.sol";
import {IKatanaInventoryStrategy} from "../interfaces/IKatanaInventoryStrategy.sol";
import {IWeETH} from "../interfaces/IEtherFiInterfaces.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockExchange} from "./utils/KatanaInventorySetup.sol";

interface IWeETHInventoryStrategy is IKatanaInventoryStrategy {
    function initiateCooldown(uint256 _amount) external returns (uint256);

    function claimCooldown(uint256 _claimId) external payable returns (uint256);
}

interface IEtherFiDeposit {
    function deposit() external payable returns (uint256);
}

/// @notice Mock EtherFi withdraw-request NFT: pays out its ETH balance on claim.
/// @dev Etched over the real NFT only for the claim step; the request itself
///      (and weETH.unwrap, which depends on the real liquidity pool) uses the
///      real EtherFi contracts.
contract MockWithdrawRequestNFT {
    function claimWithdraw(uint256) external {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "!send");
    }
}

/// @notice Tests for the weETH/WETH inventory pair on Katana, focused on the
///         new generic async-redemption add-on wired to EtherFi. The pair
///         bridges weETH via LayerZero OFT (vs wstETH via LxLy) and redeems
///         through the EtherFi withdrawal flow.
contract WeETHInventoryTests is Test {
    IWeETHInventoryStrategy public strategy;
    MockExchange public exchange;
    WeETHOracle public weEthOracle;

    ERC20 public asset; // WETH
    ERC20 public collateral; // weETH

    uint256 public ethFork;

    address public constant WETH = KatanaHelpers.ETHEREUM_WETH;
    address public constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address public constant EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    address public constant LIQUIDITY_POOL =
        0x308861A430be4cce5502d0A12724771Fc6DaF216;
    address public constant WITHDRAW_REQUEST_NFT =
        0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c;
    address public constant VB_WETH = KatanaHelpers.VB_WETH;
    // Katana-side LxLy-wrapped tokens (weETH bridges via the canonical bridge)
    address public constant KATANA_WETH =
        0xEE7D8BCFb72bC1880D0Cf19822eB0A2e6577aB62;
    address public constant KATANA_WEETH =
        0x9893989433e7a383Cb313953e4c2365107dc19a7;

    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public depositor = address(6);

    uint256 public MAX_BPS = 10_000;

    function setUp() public {
        ethFork = vm.createFork(vm.envString("ETH_RPC_URL"));
        vm.selectFork(ethFork);

        asset = ERC20(WETH);
        collateral = ERC20(WEETH);

        weEthOracle = new WeETHOracle();

        exchange = new MockExchange(WETH, WEETH, address(weEthOracle));
        deal(WETH, address(exchange), 10_000e18);
        // Fund the exchange with genuinely-backed weETH (minted via EtherFi)
        // so unwrap() works on the fork.
        _fundExchangeWithWeETH(300 ether);

        strategy = IWeETHInventoryStrategy(
            address(
                new WeETHKatanaInventoryStrategy(
                    "Katana weETH Inventory",
                    address(weEthOracle),
                    address(exchange),
                    address(0xDEAD) // remote counterpart placeholder
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

        vm.label(address(strategy), "WeETHKatanaInventoryStrategy");
        vm.label(WEETH, "weETH");
        vm.label(WETH, "WETH");
        vm.label(EETH, "eETH");
    }

    /// @dev Mint real weETH through EtherFi (deposit ETH -> eETH -> wrap) and
    ///      seed the mock exchange with it so conversions yield backed weETH.
    function _fundExchangeWithWeETH(uint256 _ethAmount) internal {
        vm.deal(address(this), _ethAmount);
        IEtherFiDeposit(LIQUIDITY_POOL).deposit{value: _ethAmount}();
        uint256 eethBal = IERC20(EETH).balanceOf(address(this));
        IERC20(EETH).approve(WEETH, eethBal);
        uint256 weethGot = IWeETH(WEETH).wrap(eethBal);
        IERC20(WEETH).transfer(address(exchange), weethGot);
    }

    function depositWeth(uint256 _amount) internal {
        deal(WETH, depositor, _amount);
        vm.startPrank(depositor);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, depositor);
        vm.stopPrank();
    }

    /// @dev Etch a mock over the withdraw NFT so the (admin-finalized) claim
    ///      settles deterministically. Call only AFTER the real request has
    ///      been created, so the real weETH.unwrap / LP.requestWithdraw path
    ///      is exercised first.
    function _mockClaim(uint256 _payout) internal {
        MockWithdrawRequestNFT nft = new MockWithdrawRequestNFT();
        vm.etch(WITHDRAW_REQUEST_NFT, address(nft).code);
        vm.deal(WITHDRAW_REQUEST_NFT, _payout);
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/

    function test_setup() public {
        assertEq(strategy.asset(), WETH);
        assertEq(strategy.collateral(), WEETH);
        assertEq(address(strategy.VB_TOKEN()), VB_WETH);
        // weETH on Katana is the LxLy-wrapped token, so no OFT is configured
        assertEq(address(strategy.COLLATERAL_OFT()), address(0));
        assertEq(strategy.pendingRedemptions(), 0);
        assertTrue(strategy.allowed(depositor));
    }

    function test_bridgeCollateral_viaLxLy() public {
        uint256 amount = 100e18;
        depositWeth(amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);
        uint256 collateralBalance = strategy.balanceOfCollateral();

        vm.prank(keeper);
        strategy.bridgeCollateral(collateralBalance);

        // Native token escrowed by the LxLy bridge, credited at oracle value
        assertEq(strategy.balanceOfCollateral(), 0);
        assertApproxEqAbs(
            strategy.remoteAssets(),
            strategy.collateralToAsset(collateralBalance),
            2
        );
    }

    function test_remoteInventory_constructsWithLxLy() public {
        // The Katana remote pairs LxLy-wrapped WETH + weETH with no OFT
        KatanaRemoteInventory remote = new KatanaRemoteInventory(
            KATANA_WETH,
            KATANA_WEETH,
            address(weEthOracle), // any valid 1e36 oracle for construction
            50,
            address(this),
            address(0), // no OFT: weETH bridges home via LxLy
            address(strategy)
        );
        assertEq(address(remote.collateral()), KATANA_WEETH);
        assertEq(address(remote.COLLATERAL_OFT()), address(0));
    }

    function test_oracle_matchesLiveRate() public {
        uint256 rate = IWeETH(WEETH).getEETHByWeETH(1e18);
        assertEq(weEthOracle.price(), rate * 1e18);
        assertGt(rate, 1e18, "weETH should be worth > 1 ETH");
    }

    /*//////////////////////////////////////////////////////////////
                            CONVERSIONS
    //////////////////////////////////////////////////////////////*/

    function test_convertToCollateral() public {
        uint256 amount = 100e18;
        depositWeth(amount);

        vm.prank(keeper);
        uint256 out = strategy.convertToCollateral(amount);

        assertGt(out, 0);
        assertEq(strategy.balanceOfCollateral(), out);
        // weETH is worth > 1 ETH, so we get fewer weETH than WETH in
        assertLt(out, amount);
        // Value preserved at oracle
        assertApproxEqAbs(strategy.collateralToAsset(out), amount, 1e12);
    }

    /*//////////////////////////////////////////////////////////////
                        ETHERFI REDEMPTION
    //////////////////////////////////////////////////////////////*/

    function test_initiateCooldown() public {
        uint256 amount = 100e18;
        depositWeth(amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);
        uint256 collateralBalance = strategy.balanceOfCollateral();

        uint256 expectedEeth = IWeETH(WEETH).getEETHByWeETH(collateralBalance);

        vm.prank(management);
        uint256 id = strategy.initiateCooldown(type(uint256).max);

        assertGt(id, 0);
        assertEq(strategy.balanceOfCollateral(), 0);
        // Pending tracked in asset (eETH ~ ETH) terms
        assertApproxEqAbs(
            strategy.pendingRedemptions(),
            expectedEeth,
            1e12,
            "!pending"
        );
        // Value preserved across the unwrap
        assertApproxEqAbs(
            strategy.balanceOfAsset() + strategy.pendingRedemptions(),
            amount,
            1e15,
            "!value"
        );
    }

    function test_initiateCooldown_onlyManagement() public {
        vm.prank(keeper);
        vm.expectRevert(bytes("!management"));
        strategy.initiateCooldown(1e18);
    }

    function test_report_blockedWhilePending() public {
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

    function test_claimCooldown() public {
        uint256 amount = 100e18;
        depositWeth(amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);

        vm.prank(management);
        uint256 id = strategy.initiateCooldown(type(uint256).max);

        uint256 pending = strategy.pendingRedemptions();
        assertGt(pending, 0);

        // Simulate EtherFi finalizing the request and paying ETH on claim
        _mockClaim(pending);

        vm.prank(keeper);
        uint256 assets = strategy.claimCooldown(id);

        assertEq(assets, pending, "!assets");
        assertEq(strategy.pendingRedemptions(), 0, "!cleared");
        assertApproxEqAbs(strategy.balanceOfAsset(), amount, 1e15, "!weth");

        // Reports work again after the claim
        vm.prank(keeper);
        strategy.report();
        assertApproxEqAbs(strategy.totalAssets(), amount, 1e15);
    }

    function test_claimCooldown_onlyKeepers() public {
        vm.prank(user);
        vm.expectRevert(bytes("!keeper"));
        strategy.claimCooldown(1);
    }

    function test_zeroPendingRedemptions_escapeHatch() public {
        uint256 amount = 100e18;
        depositWeth(amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);

        vm.prank(management);
        strategy.initiateCooldown(type(uint256).max);
        assertGt(strategy.pendingRedemptions(), 0);

        vm.prank(management);
        strategy.zeroPendingRedemptions();
        assertEq(strategy.pendingRedemptions(), 0);
    }

    function test_rescue_blocksEeth() public {
        vm.startPrank(management);

        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(WETH, management, 1);

        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(WEETH, management, 1);

        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(EETH, management, 1);

        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(VB_WETH, management, 1);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        FULL ORIGIN REDEMPTION CYCLE
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit -> convert to weETH -> EtherFi redeem -> claim ->
    ///         report books the value back -> treasury withdraws. (Bridge legs
    ///         are covered by the stcUSD/wstETH corridor tests; the weETH OFT
    ///         to Katana is not live yet.)
    function test_e2e_originRedemptionCycle() public {
        uint256 amount = 50e18;
        depositWeth(amount);

        vm.prank(keeper);
        strategy.convertToCollateral(amount);

        vm.prank(management);
        uint256 id = strategy.initiateCooldown(type(uint256).max);

        uint256 pending = strategy.pendingRedemptions();
        _mockClaim(pending);

        vm.prank(keeper);
        strategy.claimCooldown(id);

        vm.prank(keeper);
        strategy.report();

        // Value round-tripped back into loose WETH, fully withdrawable
        assertApproxEqAbs(
            strategy.availableWithdrawLimit(depositor),
            amount,
            1e15
        );

        uint256 shares = strategy.balanceOf(depositor);
        vm.prank(depositor);
        strategy.redeem(shares, depositor, depositor);
        assertApproxEqAbs(asset.balanceOf(depositor), amount, 1e15);
    }
}
