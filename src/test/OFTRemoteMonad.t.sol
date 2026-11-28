// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {Test, Vm} from "forge-std/Test.sol";

import {OFTRemoteStrategy} from "../oft/OFTRemoteStrategy.sol";
import {OFTOptions} from "../libraries/OFTOptions.sol";
import {IOFT, SendParam, MessagingFee} from "../interfaces/layerzero/IOFT.sol";
import {IOFTRemoteStrategy} from "../interfaces/IOFTStrategy.sol";
import {MockVault} from "./utils/KatanaSetup.sol";

interface IVaultFactory {
    function deploy_new_vault(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _roleManager,
        uint256 _profitMaxUnlockTime
    ) external returns (address);
}

interface IVault {
    function set_role(address _account, uint256 _role) external;

    function set_deposit_limit(uint256 _depositLimit) external;

    function add_strategy(address _strategy) external;

    function update_max_debt_for_strategy(
        address _strategy,
        uint256 _maxDebt
    ) external;

    function set_auto_allocate(bool _autoAllocate) external;
}

interface IMintable {
    function mint(address _to, uint256 _amount) external returns (bool);
}

/// @notice Monad-fork tests for the remote OFT strategy with Agora's AUSD,
///         whose bridge rejects 0-amount sends. AUSD, its OFT adapter and the
///         LayerZero endpoint are REAL, and so is the yVault (3.0.4, from the
///         real factory). forge needs a network family to fork Monad:
///           MONAD_RPC_URL=<url> forge test --network ethereum \
///             --match-contract OFTRemoteMonadTest
contract OFTRemoteMonadTest is Test {
    IOFTRemoteStrategy public remote;
    IVault public vault;
    MockVault public strategy;

    // Monad
    address public constant AUSD = 0x00000000eFE302BEAA2b3e6e1b18d08D69a9012a;
    address public constant AUSD_OFT =
        0x9CaB7Ede13dc56652E44D2404E969C212f22689b; // Agora mint/burn adapter
    address public constant LZ_ENDPOINT =
        0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    address public constant VAULT_FACTORY =
        0x770D0d1Fb036483Ed4AbB6d53c1C88fb277D812F; // yVault 3.0.4
    uint32 public constant ETHEREUM_EID = 30101;

    address public originCounterpart = address(0xB0B);
    address public governance = address(7);
    address public keeper = address(4);

    function setUp() public {
        vm.createSelectFork(vm.envString("MONAD_RPC_URL"));

        // A yVault that auto allocates to a strategy, like the one the remote
        // will deposit into.
        vault = IVault(
            IVaultFactory(VAULT_FACTORY).deploy_new_vault(
                AUSD,
                "AUSD yVault",
                "yvAUSD",
                address(this),
                1 days
            )
        );
        strategy = new MockVault(AUSD);
        vault.set_role(address(this), 16_383); // all roles
        vault.set_deposit_limit(type(uint256).max);
        vault.add_strategy(address(strategy));
        vault.update_max_debt_for_strategy(
            address(strategy),
            type(uint256).max
        );
        vault.set_auto_allocate(true);

        remote = IOFTRemoteStrategy(
            address(
                new OFTRemoteStrategy(
                    AUSD,
                    governance,
                    AUSD_OFT,
                    LZ_ENDPOINT,
                    ETHEREUM_EID,
                    originCounterpart,
                    address(vault),
                    OFTOptions.composeOptions(250_000, 150_000)
                )
            )
        );

        vm.prank(governance);
        remote.setKeeper(keeper);

        // A message home costs a few hundred MON
        vm.deal(address(remote), 10_000 ether);
    }

    /// @dev AUSD arrives the way the bridge delivers it: minted by the adapter.
    function _arrive(uint256 _amount) internal {
        vm.prank(AUSD_OFT);
        IMintable(AUSD).mint(address(remote), _amount);
    }

    /// @dev Counts the OFT sends the remote made since `vm.recordLogs()`.
    ///      Each must carry a report.
    function _sends() internal returns (uint256 sends) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 oftSent = keccak256("OFTSent(uint256,bool,uint256)");
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
    }

    function test_setup() public {
        assertEq(remote.vault(), address(vault));
        assertEq(remote.OFT(), AUSD_OFT);
        assertEq(remote.ENDPOINT(), LZ_ENDPOINT);
        assertEq(remote.REMOTE_EID(), ETHEREUM_EID);
        assertEq(remote.keeper(), keeper);
    }

    /// @notice Why a report carries a unit: Agora rejects 0-amount sends.
    function test_zeroAmountSend_reverts() public {
        SendParam memory param = SendParam({
            dstEid: ETHEREUM_EID,
            to: bytes32(uint256(uint160(originCounterpart))),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: OFTOptions.composeOptions(250_000, 150_000),
            composeMsg: "report",
            oftCmd: ""
        });
        MessagingFee memory fee = IOFT(AUSD_OFT).quoteSend(param, false);
        vm.deal(address(this), fee.nativeFee);

        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        IOFT(AUSD_OFT).send{value: fee.nativeFee}(param, fee, address(this));
    }

    /// @notice One report deploys what arrived and goes home on 1 unit.
    function test_report_afterArrival() public {
        uint256 amount = 10_000e6;
        _arrive(amount);

        skip(1);
        vm.recordLogs();
        vm.prank(keeper);
        (uint256 ta, ) = remote.report();

        assertEq(ta, amount - 1, "!reported");
        assertEq(remote.totalAssets(), ta, "!total");
        assertEq(remote.valueOfDeployedAssets(), ta, "!deployed");
        assertEq(remote.balanceOfAsset(), 0, "!unitSent");
        assertEq(_sends(), 1, "!oneSend");
    }

    /// @notice With nothing loose the report withdraws 1,000 units, and the
    ///         next reports live off them.
    function test_report_withNothingLoose() public {
        _arrive(10_000e6);
        vm.prank(keeper);
        remote.pushFunds(10_000e6);

        for (uint256 i = 0; i < 3; i++) {
            skip(1);
            vm.prank(keeper);
            remote.report();
        }

        // 1,000 units withdrawn once, 1 sent per report
        assertEq(remote.balanceOfAsset(), 997, "!loose");
        assertEq(remote.totalAssets(), 10_000e6 - 3, "!total");
    }

    /// @notice While its strategy sits 1 wei under its debt, a yVault charges
    ///         2 units of loss on a withdrawal, so 1 unit can't be withdrawn.
    ///         The report still goes out.
    function test_report_withUnrealisedLoss() public {
        _arrive(10_000e6);
        vm.prank(keeper);
        remote.pushFunds(10_000e6);

        strategy.simulateLoss(1);

        vm.prank(keeper);
        vm.expectRevert();
        remote.pullFunds(1);

        skip(1);
        vm.recordLogs();
        vm.prank(keeper);
        remote.report();

        assertEq(_sends(), 1, "!oneSend");
        assertGt(remote.balanceOfAsset(), 990, "!loose");
    }

    /// @notice A withdrawal goes home as one message that carries the report.
    function test_processWithdrawal() public {
        _arrive(10_000e6);
        vm.prank(keeper);
        remote.pushFunds(10_000e6);

        skip(1);
        vm.recordLogs();
        vm.prank(keeper);
        remote.processWithdrawal(4_000e6);

        assertEq(_sends(), 1, "!oneSend");
        assertEq(remote.balanceOfAsset(), 0, "!bridgedHome");
        assertEq(remote.totalAssets(), 6_000e6, "!left");
    }
}
