// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OFTStrategyFactory} from "../oft/OFTStrategyFactory.sol";
import {OFTRemoteStrategyFactory} from "../oft/OFTRemoteStrategyFactory.sol";
import {OFTOptions} from "../libraries/OFTOptions.sol";
import {IOFTStrategy, IOFTRemoteStrategy} from "../interfaces/IOFTStrategy.sol";

/// @notice Dual-fork (Ethereum + Robinhood) round-trip for the USDG OFT
///         strategy. The origin OFT send and the remote spUSDG vault are
///         exercised for REAL on their respective forks; the LayerZero
///         token/message transport between forks is simulated (as the CCTP /
///         Katana suites do), since executing it needs off-chain DVN wiring.
///         Run with: HOOD_RPC_URL=<url> forge test --match-contract OFTTest
contract OFTTest is Test {
    IOFTStrategy public origin;
    IOFTRemoteStrategy public remote;

    uint256 public ethFork;
    uint256 public hoodFork;

    // Mainnet
    address public constant USDG = 0xe343167631d89B6Ffc58B88d6b7fB0228795491D;
    address public constant USDG_OFT =
        0x147BdE4F997f0d4C7544ED0C55eAcf1E5E6bf9c4;
    address public constant ETH_ENDPOINT =
        0x1a44076050125825900e736c501f859c50fE728c;
    uint32 public constant ETHEREUM_EID = 30101;

    // Robinhood
    address public constant RUSDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address public constant RUSDG_OFT =
        0x0d54755f5106BfdB43f7a35f5D49a23F940628d1;
    address public constant HOOD_ENDPOINT =
        0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    address public constant VAULT = 0xde770c84FE66E063336b31737cFE9790f18c4087;
    uint32 public constant ROBINHOOD_EID = 30416;

    address public management = address(1);
    address public governance = address(7);
    address public keeper = address(4);
    address public depositor = address(6);

    function setUp() public {
        ethFork = vm.createFork(vm.envString("ETH_RPC_URL"));
        hoodFork = vm.createFork(vm.envString("HOOD_RPC_URL"));

        // Remote factory on Robinhood (generic: token/OFT/endpoint per call).
        vm.selectFork(hoodFork);
        OFTRemoteStrategyFactory remoteFactory = new OFTRemoteStrategyFactory(
            governance,
            80_000,
            100_000
        );
        address rf = address(remoteFactory);
        bytes memory rfCode = rf.code;

        // Origin factory on Ethereum. Place the remote factory's code at the
        // same address so the origin can precompute the remote counterpart
        // (in production the remote factory is deployed there via CreateX).
        vm.selectFork(ethFork);
        vm.etch(rf, rfCode);
        OFTStrategyFactory originFactory = new OFTStrategyFactory(
            management,
            address(3),
            keeper,
            management,
            rf
        );
        origin = IOFTStrategy(
            originFactory.newStrategy(
                "USDG Robinhood OFT Strategy",
                USDG,
                USDG_OFT,
                ETH_ENDPOINT,
                ETHEREUM_EID,
                ROBINHOOD_EID,
                4663,
                VAULT
            )
        );
        vm.startPrank(management);
        origin.acceptManagement();
        origin.setLossLimitRatio(100); // tolerate small ERC4626 rounding
        origin.setAllowed(depositor, true); // allowed mapping gates deposits
        vm.stopPrank();
        vm.deal(address(origin), 10 ether);

        // Deploy the remote to the precomputed address, linked to the origin.
        vm.selectFork(hoodFork);
        remote = IOFTRemoteStrategy(
            remoteFactory.deployRemoteStrategy(
                RUSDG,
                RUSDG_OFT,
                HOOD_ENDPOINT,
                VAULT,
                ETHEREUM_EID,
                address(origin)
            )
        );
        vm.prank(governance);
        remote.setKeeper(keeper);
        vm.deal(address(remote), 10 ether);

        vm.label(address(origin), "OFTStrategy");
        vm.label(address(remote), "OFTRemoteStrategy");
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _dealUSDG(address _token, address _to, uint256 _amount) internal {
        for (uint256 slot = 0; slot < 200; slot++) {
            bytes32 key = keccak256(abi.encode(_to, slot));
            bytes32 prev = vm.load(_token, key);
            vm.store(_token, key, bytes32(_amount));
            if (IERC20(_token).balanceOf(_to) == _amount) return;
            vm.store(_token, key, prev);
        }
        revert("slot not found");
    }

    /// @dev Simulate the OFT delivering `_amount` USDG to the remote.
    function _arriveOnRobinhood(uint256 _amount) internal {
        vm.selectFork(hoodFork);
        uint256 bal = IERC20(RUSDG).balanceOf(address(remote));
        _dealUSDG(RUSDG, address(remote), bal + _amount);
    }

    /// @dev Simulate the OFT delivering `_amount` USDG home to the origin.
    function _arriveOnEthereum(uint256 _amount) internal {
        vm.selectFork(ethFork);
        uint256 bal = IERC20(USDG).balanceOf(address(origin));
        _dealUSDG(USDG, address(origin), bal + _amount);
    }

    /// @dev Simulate a report compose arriving at the origin from the remote,
    ///      delivered by the endpoint after the USDG OFT credits the origin.
    function _reportHome(uint256 _totalAssets) internal {
        vm.selectFork(ethFork);
        bytes memory payload = abi.encode(
            _totalAssets,
            origin.lastRemoteAssetsReport() + 1
        );
        // OFT compose framing: nonce(8)|srcEid(4)|amountLD(32)|from(32)|payload
        bytes memory message = abi.encodePacked(
            uint64(1),
            ROBINHOOD_EID,
            uint256(0),
            bytes32(uint256(uint160(address(remote)))),
            payload
        );
        address oft = origin.OFT();
        vm.prank(ETH_ENDPOINT);
        origin.lzCompose(oft, bytes32(0), message, address(0), "");
    }

    function _deposit(uint256 _amount) internal {
        vm.selectFork(ethFork);
        _dealUSDG(USDG, depositor, _amount);
        vm.startPrank(depositor);
        IERC20(USDG).approve(address(origin), _amount);
        origin.deposit(_amount, depositor);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            ROUND TRIP
    //////////////////////////////////////////////////////////////*/

    function test_e2e_roundTrip() public {
        uint256 amount = 100_000e6;

        // 1. Deposit on mainnet -> REAL OFT send burns USDG, credits remote.
        _deposit(amount);
        assertEq(IERC20(USDG).balanceOf(address(origin)), 0, "!burned");
        assertEq(origin.remoteAssets(), amount, "!credited");
        assertEq(origin.totalAssets(), amount, "!total");

        // 2. USDG arrives on Robinhood; keeper deploys into the REAL vault.
        _arriveOnRobinhood(amount);
        vm.selectFork(hoodFork);
        vm.prank(keeper);
        remote.pushFunds(amount);
        uint256 remoteTotal = remote.totalAssets();
        assertApproxEqRel(remoteTotal, amount, 0.001e18, "!deployed");

        // 3. Remote reports home; origin harvests, PPS reflects remote value.
        _reportHome(remoteTotal);
        assertEq(origin.remoteAssets(), remoteTotal);

        vm.selectFork(ethFork);
        vm.prank(keeper);
        origin.report();
        assertApproxEqRel(origin.totalAssets(), amount, 0.01e18, "!harvest");

        // 4. Withdraw leg: remote redeems from the vault (real) ...
        vm.selectFork(hoodFork);
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
        assertGt(IERC20(USDG).balanceOf(depositor), 0, "!withdrawn");
    }

    function test_deposit_onlyDepositor() public {
        vm.selectFork(ethFork);
        assertEq(origin.availableDepositLimit(depositor), type(uint256).max);
        assertEq(origin.availableDepositLimit(address(10)), 0);
    }

    /// @notice The factory computes and sets lzOptions at construction: the
    ///         remote carries compose options; the origin rides the OFT's
    ///         enforced options (empty).
    function test_factory_wiredOptions() public {
        vm.selectFork(ethFork);
        assertEq(origin.lzOptions(), "");

        vm.selectFork(hoodFork);
        assertEq(
            remote.lzOptions(),
            OFTOptions.composeOptions(80_000, 100_000)
        );
        assertEq(remote.keeper(), keeper);
    }
}
