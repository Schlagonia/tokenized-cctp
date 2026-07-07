// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {CCIPRemoteStrategy} from "../ccip/CCIPRemoteStrategy.sol";
import {ICCIPRemoteStrategy} from "../interfaces/ICCIPStrategy.sol";
import {Client} from "../interfaces/ccip/ICCIP.sol";
import {MockVault} from "./utils/MockVault.sol";

/// @notice Arbitrum-fork tests for the remote CCIP strategy: exercises the
///         vault deposit/redeem and a REAL data-only CCIP report send over the
///         Arbitrum router. Run with:
///           ARB_RPC_URL=<url> forge test --match-contract CCIPRemoteTest
contract CCIPRemoteTest is Test {
    ICCIPRemoteStrategy public remote;
    MockVault public vault;

    // Arbitrum
    address public constant SYRUP = 0x41CA7586cC1311807B4605fBB748a3B8862b42b5; // syrupUSDC on Arbitrum
    address public constant ROUTER = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;
    uint64 public constant ETH_SELECTOR = 5009297550715157269;
    uint256 public constant GAS_LIMIT = 200_000;

    address public originCounterpart = address(0xB0B);
    address public governance = address(7);
    address public keeper = address(4);
    address public user = address(10);

    function setUp() public {
        vm.createSelectFork(vm.envString("ARB_RPC_URL"));

        vault = new MockVault(SYRUP);

        remote = ICCIPRemoteStrategy(
            address(
                new CCIPRemoteStrategy(
                    SYRUP,
                    governance,
                    ROUTER,
                    ETH_SELECTOR,
                    originCounterpart,
                    address(vault),
                    GAS_LIMIT
                )
            )
        );

        vm.prank(governance);
        remote.setKeeper(keeper);

        vm.deal(address(remote), 10 ether);

        vm.label(SYRUP, "syrupUSDC");
        vm.label(ROUTER, "CCIP_ROUTER");
    }

    function _dealSyrup(address _to, uint256 _amount) internal {
        for (uint256 slot = 0; slot < 200; slot++) {
            bytes32 key = keccak256(abi.encode(_to, slot));
            bytes32 prev = vm.load(SYRUP, key);
            vm.store(SYRUP, key, bytes32(_amount));
            if (IERC20(SYRUP).balanceOf(_to) == _amount) return;
            vm.store(SYRUP, key, prev);
        }
        revert("syrup slot not found");
    }

    function test_setup() public {
        assertEq(remote.vault(), address(vault));
        assertEq(remote.ROUTER(), ROUTER);
        assertEq(remote.REMOTE_CHAIN_SELECTOR(), ETH_SELECTOR);
        assertEq(remote.governance(), governance);
        assertEq(remote.keeper(), keeper);
        assertEq(IERC4626(address(vault)).asset(), SYRUP);
    }

    /// @notice Bridged syrupUSDC deposits into the vault.
    function test_pushFunds() public {
        uint256 amount = 100_000e6;
        _dealSyrup(address(remote), amount);

        vm.prank(keeper);
        remote.pushFunds(amount);

        assertEq(remote.balanceOfAsset(), 0, "!idle");
        assertApproxEqRel(
            remote.valueOfDeployedAssets(),
            amount,
            0.001e18,
            "!deployed"
        );
        assertApproxEqRel(remote.totalAssets(), amount, 0.001e18, "!total");
    }

    /// @notice Withdraw path redeems from the vault back to idle.
    function test_pullFunds() public {
        uint256 amount = 100_000e6;
        _dealSyrup(address(remote), amount);

        vm.prank(keeper);
        remote.pushFunds(amount);

        vm.prank(keeper);
        remote.pullFunds(40_000e6);

        assertApproxEqRel(remote.balanceOfAsset(), 40_000e6, 0.001e18);
    }

    /// @notice A report is a REAL data-only CCIP send over the Arbitrum router.
    function test_report_viaCCIP() public {
        uint256 amount = 50_000e6;
        _dealSyrup(address(remote), amount);

        vm.prank(keeper);
        remote.pushFunds(amount);

        uint256 ethBefore = address(remote).balance;

        skip(1);
        vm.prank(keeper);
        (uint256 ta, ) = remote.report();

        assertApproxEqRel(ta, amount, 0.001e18, "!reported");
        assertEq(remote.balanceOfAsset(), 0, "!noTokenMoved");
        assertLt(address(remote).balance, ethBefore, "!fee");
    }

    function test_report_onlyKeepers() public {
        skip(1);
        vm.prank(user);
        vm.expectRevert(bytes("!keeper"));
        remote.report();
    }

    /// @notice The remote never ingests reports; a data-carrying message from
    ///         the origin reverts NotSupported.
    function test_ccipReceive_reportNotSupported() public {
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0),
            sourceChainSelector: ETH_SELECTOR,
            sender: abi.encode(originCounterpart),
            data: abi.encode(uint256(1e6), block.timestamp),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(ROUTER);
        vm.expectRevert(bytes("NotSupported"));
        remote.ccipReceive(message);
    }
}
