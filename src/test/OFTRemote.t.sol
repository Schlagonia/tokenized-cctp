// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test, Vm} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {OFTRemoteStrategy} from "../oft/OFTRemoteStrategy.sol";
import {OFTOptions} from "../libraries/OFTOptions.sol";
import {IOFTRemoteStrategy} from "../interfaces/IOFTStrategy.sol";

/// @notice Robinhood-fork tests for the remote OFT strategy: exercises the
///         REAL spUSDG ERC4626 vault and checks whether a fresh OApp can send
///         a report over the real LayerZero endpoint. Run with:
///           HOOD_RPC_URL=<url> forge test --match-contract OFTRemoteTest
contract OFTRemoteTest is Test {
    IOFTRemoteStrategy public remote;

    // Robinhood
    address public constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168; // token (vault asset)
    address public constant USDG_OFT =
        0x0d54755f5106BfdB43f7a35f5D49a23F940628d1; // OFT adapter
    address public constant LZ_ENDPOINT =
        0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    address public constant VAULT = 0xde770c84FE66E063336b31737cFE9790f18c4087; // spUSDG
    uint32 public constant ETHEREUM_EID = 30101;

    address public originCounterpart = address(0xB0B);
    address public governance = address(7);
    address public keeper = address(4);
    address public user = address(10);

    function setUp() public {
        vm.createSelectFork(vm.envString("HOOD_RPC_URL"));

        remote = IOFTRemoteStrategy(
            address(
                new OFTRemoteStrategy(
                    USDG,
                    governance,
                    USDG_OFT,
                    LZ_ENDPOINT,
                    ETHEREUM_EID,
                    originCounterpart,
                    VAULT,
                    OFTOptions.composeOptions(80_000, 100_000)
                )
            )
        );

        vm.prank(governance);
        remote.setKeeper(keeper);

        vm.deal(address(remote), 10 ether);

        vm.label(USDG, "USDG");
        vm.label(VAULT, "spUSDG");
        vm.label(LZ_ENDPOINT, "LZ_ENDPOINT");
    }

    /// @dev Robinhood USDG is a proxy; find its balance slot and write it.
    function _dealUSDG(address _to, uint256 _amount) internal {
        for (uint256 slot = 0; slot < 200; slot++) {
            bytes32 key = keccak256(abi.encode(_to, slot));
            bytes32 prev = vm.load(USDG, key);
            vm.store(USDG, key, bytes32(_amount));
            if (IERC20(USDG).balanceOf(_to) == _amount) return;
            vm.store(USDG, key, prev);
        }
        revert("USDG slot not found");
    }

    function test_setup() public {
        assertEq(remote.vault(), VAULT);
        assertEq(remote.OFT(), USDG_OFT);
        assertEq(remote.REMOTE_EID(), ETHEREUM_EID);
        assertEq(remote.governance(), governance);
        assertEq(remote.keeper(), keeper);
        assertEq(IERC4626(VAULT).asset(), USDG);
    }

    /// @notice Reports are not converted, so a token that doesn't use the
    ///         OFT's shared decimals is rejected.
    function test_constructor_revertsOnConversionRate() public {
        // 5 shared decimals with a rate of 10 still passes the asset check.
        vm.mockCall(
            USDG_OFT,
            abi.encodeWithSignature("sharedDecimals()"),
            abi.encode(uint8(5))
        );
        vm.mockCall(
            USDG_OFT,
            abi.encodeWithSignature("decimalConversionRate()"),
            abi.encode(uint256(10))
        );

        vm.expectRevert("!decimals");
        new OFTRemoteStrategy(
            USDG,
            governance,
            USDG_OFT,
            LZ_ENDPOINT,
            ETHEREUM_EID,
            originCounterpart,
            VAULT,
            OFTOptions.composeOptions(80_000, 100_000)
        );
    }

    function test_setLzOptions_onlyGovernance() public {
        bytes memory newOptions = OFTOptions.composeOptions(90_000, 120_000);

        vm.prank(user);
        vm.expectRevert("!governance");
        remote.setLzOptions(newOptions);

        vm.prank(governance);
        remote.setLzOptions(newOptions);
        assertEq(remote.lzOptions(), newOptions);
    }

    /// @notice Bridged USDG deposits into the REAL spUSDG vault.
    function test_pushFunds_realVault() public {
        uint256 amount = 100_000e6;
        _dealUSDG(address(remote), amount);

        vm.prank(keeper);
        remote.pushFunds(amount);

        assertEq(remote.balanceOfAsset(), 0, "!idle");
        // Value is now held as vault shares, worth ~the deposit
        assertApproxEqRel(
            remote.valueOfDeployedAssets(),
            amount,
            0.001e18,
            "!deployed"
        );
        assertApproxEqRel(remote.totalAssets(), amount, 0.001e18, "!total");
    }

    /// @notice Withdraw path redeems from the REAL vault back to idle USDG.
    /// @dev Uses pullFunds (vault redeem only) to isolate the vault leg from
    ///      the LayerZero bridge/report, which needs off-chain DVN wiring.
    function test_pullFunds_realVault() public {
        uint256 amount = 100_000e6;
        _dealUSDG(address(remote), amount);

        vm.prank(keeper);
        remote.pushFunds(amount);
        assertEq(remote.balanceOfAsset(), 0);

        vm.prank(keeper);
        remote.pullFunds(40_000e6);

        // Redeemed from the real vault back to idle USDG
        assertApproxEqRel(remote.balanceOfAsset(), 40_000e6, 0.001e18);
    }

    /// @notice A report deploys what is idle and rides the REAL,
    ///         already-configured USDG OFT on a 1-unit transfer.
    function test_report_viaOft() public {
        uint256 amount = 50_000e6;
        _dealUSDG(address(remote), amount);

        uint256 ethBefore = address(remote).balance;

        skip(1);
        vm.prank(keeper);
        (uint256 ta, ) = remote.report();

        // All but the unit went into the vault; the unit went home
        assertApproxEqRel(ta, amount, 0.001e18, "!reported");
        assertEq(ta, remote.totalAssets(), "!total");
        assertEq(remote.balanceOfAsset(), 0, "!unitSent");
        // A small LayerZero fee was paid from the reserve
        assertLt(address(remote).balance, ethBefore, "!fee");
    }

    /// @notice With nothing loose the report withdraws 1,000 units, and the
    ///         next reports live off them.
    function test_report_withNothingLoose() public {
        uint256 amount = 50_000e6;
        _dealUSDG(address(remote), amount);

        vm.prank(keeper);
        remote.pushFunds(amount);

        for (uint256 i = 0; i < 3; i++) {
            skip(1);
            vm.prank(keeper);
            remote.report();
        }

        // 1,000 units withdrawn once, 1 sent per report
        assertApproxEqAbs(remote.balanceOfAsset(), 997, 2, "!loose");
    }

    /// @notice Full remote withdraw: redeem from the REAL vault and bridge
    ///         USDG home with the report on the same OFT transfer.
    function test_processWithdrawal_viaOft() public {
        uint256 amount = 100_000e6;
        _dealUSDG(address(remote), amount);

        vm.prank(keeper);
        remote.pushFunds(amount);

        skip(1);
        vm.recordLogs();
        vm.prank(keeper);
        remote.processWithdrawal(40_000e6);

        // Redeemed from the vault and bridged home (burned by the adapter)
        assertLe(remote.balanceOfAsset(), 1e6, "!bridgedHome");

        // One send, carrying the report
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 oftSent = keccak256("OFTSent(uint256,bool,uint256)");
        uint256 sends;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(remote)) continue;
            if (logs[i].topics[0] != oftSent) continue;
            (, bool report, ) = abi.decode(
                logs[i].data,
                (uint256, bool, uint256)
            );
            assertTrue(report, "!report");
            sends++;
        }
        assertEq(sends, 1, "!oneSend");
    }

    function test_report_onlyKeepers() public {
        skip(1); // pass isReady so the keeper check is reached
        vm.prank(user);
        vm.expectRevert(bytes("!keeper"));
        remote.report();
    }
}
