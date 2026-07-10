// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CCIPStrategyFactory} from "../ccip/CCIPStrategyFactory.sol";
import {CCIPRemoteStrategyFactory} from "../ccip/CCIPRemoteStrategyFactory.sol";
import {ICCIPStrategy, ICCIPRemoteStrategy} from "../interfaces/ICCIPStrategy.sol";
import {Client} from "../interfaces/ccip/ICCIP.sol";
import {MockVault} from "./utils/MockVault.sol";

/// @notice Dual-fork (Ethereum + Arbitrum) round-trip for the syrupUSDC CCIP
///         strategy, deployed through the factory pair. The origin CCIP send
///         and the remote vault + report send are exercised for REAL on their
///         forks; cross-fork token/message transport is simulated (as the
///         CCTP / Katana / OFT suites do).
///         Run with: ARB_RPC_URL and ETH_RPC_URL set.
contract CCIPTest is Test {
    ICCIPStrategy public origin;
    ICCIPRemoteStrategy public remote;
    MockVault public vault;

    uint256 public ethFork;
    uint256 public arbFork;

    // Ethereum
    address public constant SYRUP_ETH =
        0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;
    address public constant ETH_ROUTER =
        0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    uint64 public constant ETH_SELECTOR = 5009297550715157269;

    // Arbitrum
    address public constant SYRUP_ARB =
        0x41CA7586cC1311807B4605fBB748a3B8862b42b5;
    address public constant ARB_ROUTER =
        0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;
    uint64 public constant ARB_SELECTOR = 4949039107694359620;

    uint256 public constant GAS_LIMIT = 200_000;

    address public management = address(1);
    address public governance = address(7);
    address public keeper = address(4);
    address public depositor = address(6);

    function setUp() public {
        ethFork = vm.createFork(vm.envString("ETH_RPC_URL"));
        arbFork = vm.createFork(vm.envString("ARB_RPC_URL"));

        // Remote vault + factory on Arbitrum.
        vm.selectFork(arbFork);
        vault = new MockVault(SYRUP_ARB);
        CCIPRemoteStrategyFactory remoteFactory = new CCIPRemoteStrategyFactory(
            governance,
            GAS_LIMIT
        );
        address rf = address(remoteFactory);
        bytes memory rfCode = rf.code;

        // Origin factory on Ethereum. Place the remote factory's code at the
        // same address so the origin can precompute the remote counterpart
        // (in production the remote factory is deployed there via CreateX).
        vm.selectFork(ethFork);
        vm.etch(rf, rfCode);
        CCIPStrategyFactory originFactory = new CCIPStrategyFactory(
            management,
            address(3),
            keeper,
            management,
            rf,
            GAS_LIMIT
        );
        origin = ICCIPStrategy(
            originFactory.newStrategy(
                "syrupUSDC Arbitrum CCIP Strategy",
                SYRUP_ETH,
                ETH_ROUTER,
                ETH_SELECTOR,
                ARB_SELECTOR,
                42161,
                address(vault)
            )
        );
        vm.startPrank(management);
        origin.acceptManagement();
        origin.setLossLimitRatio(100);
        // Deposits are gated by the BaseHealthCheck allowed mapping.
        origin.setAllowed(depositor, true);
        vm.stopPrank();
        vm.deal(address(origin), 10 ether);

        // Deploy the remote to the precomputed address, linked to the origin.
        vm.selectFork(arbFork);
        remote = ICCIPRemoteStrategy(
            remoteFactory.deployRemoteStrategy(
                SYRUP_ARB,
                ARB_ROUTER,
                address(vault),
                ETH_SELECTOR,
                address(origin)
            )
        );
        vm.prank(governance);
        remote.setKeeper(keeper);
        vm.deal(address(remote), 10 ether);

        vm.label(address(origin), "CCIPStrategy");
        vm.label(address(remote), "CCIPRemoteStrategy");
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _dealSyrup(address _token, address _to, uint256 _amount) internal {
        for (uint256 slot = 0; slot < 200; slot++) {
            bytes32 key = keccak256(abi.encode(_to, slot));
            bytes32 prev = vm.load(_token, key);
            vm.store(_token, key, bytes32(_amount));
            if (IERC20(_token).balanceOf(_to) == _amount) return;
            vm.store(_token, key, prev);
        }
        revert("slot not found");
    }

    function _arriveOnArbitrum(uint256 _amount) internal {
        vm.selectFork(arbFork);
        uint256 bal = IERC20(SYRUP_ARB).balanceOf(address(remote));
        _dealSyrup(SYRUP_ARB, address(remote), bal + _amount);
    }

    function _arriveOnEthereum(uint256 _amount) internal {
        vm.selectFork(ethFork);
        uint256 bal = IERC20(SYRUP_ETH).balanceOf(address(origin));
        _dealSyrup(SYRUP_ETH, address(origin), bal + _amount);
    }

    /// @dev Simulate a report arriving at the origin from the remote via CCIP.
    function _reportHome(uint256 _totalAssets) internal {
        vm.selectFork(ethFork);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0),
            sourceChainSelector: ARB_SELECTOR,
            sender: abi.encode(address(remote)),
            data: abi.encode(_totalAssets, origin.lastRemoteAssetsReport() + 1),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        vm.prank(ETH_ROUTER);
        origin.ccipReceive(message);
    }

    function _deposit(uint256 _amount) internal {
        vm.selectFork(ethFork);
        _dealSyrup(SYRUP_ETH, depositor, _amount);
        vm.startPrank(depositor);
        IERC20(SYRUP_ETH).approve(address(origin), _amount);
        origin.deposit(_amount, depositor);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            ROUND TRIP
    //////////////////////////////////////////////////////////////*/

    function test_e2e_roundTrip() public {
        uint256 amount = 1_000e6;

        // 1. Deposit on mainnet -> REAL CCIP send bridges syrupUSDC out.
        _deposit(amount);
        assertEq(IERC20(SYRUP_ETH).balanceOf(address(origin)), 0, "!bridged");
        assertEq(origin.remoteAssets(), amount, "!credited");
        assertEq(origin.totalAssets(), amount, "!total");

        // 2. syrupUSDC arrives on Arbitrum; keeper deploys into the vault.
        _arriveOnArbitrum(amount);
        vm.selectFork(arbFork);
        vm.prank(keeper);
        remote.pushFunds(amount);
        uint256 remoteTotal = remote.totalAssets();
        assertApproxEqRel(remoteTotal, amount, 0.001e18, "!deployed");

        // 3. Remote reports home; origin harvests.
        _reportHome(remoteTotal);
        assertEq(origin.remoteAssets(), remoteTotal);

        vm.selectFork(ethFork);
        vm.prank(keeper);
        origin.report();
        assertApproxEqRel(origin.totalAssets(), amount, 0.01e18, "!harvest");

        // 4. Withdraw leg: remote redeems from the vault ...
        vm.selectFork(arbFork);
        uint256 remoteHoldings = remote.totalAssets();
        vm.prank(keeper);
        remote.pullFunds(remoteHoldings);
        uint256 broughtBack = remote.balanceOfAsset();
        assertApproxEqRel(broughtBack, amount, 0.001e18, "!redeemed");

        // ... bridges home (simulated arrival) and reports the drawdown.
        _arriveOnEthereum(broughtBack);
        _reportHome(0);

        // 5. Treasury withdraws the funds now local on mainnet.
        vm.selectFork(ethFork);
        vm.prank(keeper);
        origin.report();

        uint256 withdrawable = origin.availableWithdrawLimit(depositor);
        assertApproxEqRel(withdrawable, amount, 0.01e18, "!withdrawable");

        uint256 shares = origin.balanceOf(depositor);
        vm.prank(depositor);
        origin.redeem(shares, depositor, depositor);
        assertGt(IERC20(SYRUP_ETH).balanceOf(depositor), 0, "!withdrawn");
    }

    function test_deposit_onlyDepositor() public {
        vm.selectFork(ethFork);
        assertEq(origin.availableDepositLimit(depositor), type(uint256).max);
        assertEq(origin.availableDepositLimit(address(10)), 0);
    }

    function test_factory_wiredGasLimit() public {
        vm.selectFork(ethFork);
        assertEq(origin.gasLimit(), GAS_LIMIT);
        vm.selectFork(arbFork);
        assertEq(remote.gasLimit(), GAS_LIMIT);
        assertEq(remote.keeper(), keeper);
    }
}
