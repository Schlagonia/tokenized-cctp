// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OFTStrategy} from "../oft/OFTStrategy.sol";
import {IOFTStrategy} from "../interfaces/IOFTStrategy.sol";

/// @notice Mainnet-only tests for the USDG -> Robinhood OFT strategy: verifies
///         the outbound OFT bridge against the REAL USDG adapter and endpoint,
///         and the report-receive path with a pranked endpoint. The full
///         dual-fork round-trip lives in OFT.t.sol (needs HOOD_RPC_URL).
contract OFTMainnetTest is Test {
    IOFTStrategy public strategy;

    // Mainnet
    address public constant USDG = 0xe343167631d89B6Ffc58B88d6b7fB0228795491D;
    address public constant USDG_OFT =
        0x147BdE4F997f0d4C7544ED0C55eAcf1E5E6bf9c4;
    address public constant LZ_ENDPOINT =
        0x1a44076050125825900e736c501f859c50fE728c;
    uint32 public constant ROBINHOOD_EID = 30416;
    uint32 public constant ETHEREUM_EID = 30101;

    // A stand-in for the remote strategy on Robinhood
    address public remoteCounterpart = address(0xB0B);

    address public management = address(1);
    address public keeper = address(4);
    address public depositor = address(6);
    address public user = address(10);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        strategy = IOFTStrategy(
            address(
                new OFTStrategy(
                    USDG,
                    "USDG Robinhood OFT Strategy",
                    USDG_OFT,
                    LZ_ENDPOINT,
                    ROBINHOOD_EID,
                    4663, // Robinhood chain id
                    remoteCounterpart,
                    depositor,
                    "" // origin token sends ride the OFT enforced options
                )
            )
        );

        address currentManagement = strategy.management();
        vm.prank(currentManagement);
        strategy.setPendingManagement(management);
        vm.prank(management);
        strategy.acceptManagement();
        vm.prank(management);
        strategy.setKeeper(keeper);

        // ETH reserve for LayerZero fees
        vm.deal(address(strategy), 10 ether);

        vm.label(USDG, "USDG");
        vm.label(USDG_OFT, "USDG_OFT");
        vm.label(LZ_ENDPOINT, "LZ_ENDPOINT");
    }

    /// @dev USDG is a Paxos-style proxy whose balance slot `deal` can't find;
    ///      locate the mapping slot by probing and write it directly.
    function _dealUSDG(address _to, uint256 _amount) internal {
        for (uint256 slot = 0; slot < 200; slot++) {
            bytes32 key = keccak256(abi.encode(_to, slot));
            bytes32 prev = vm.load(USDG, key);
            vm.store(USDG, key, bytes32(_amount));
            if (IERC20(USDG).balanceOf(_to) == _amount) return;
            vm.store(USDG, key, prev);
        }
        revert("USDG balance slot not found");
    }

    function _deposit(uint256 _amount) internal {
        _dealUSDG(depositor, _amount);
        vm.startPrank(depositor);
        IERC20(USDG).approve(address(strategy), _amount);
        strategy.deposit(_amount, depositor);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function test_setup() public {
        assertEq(strategy.asset(), USDG);
        assertEq(strategy.OFT(), USDG_OFT);
        assertEq(strategy.ENDPOINT(), LZ_ENDPOINT);
        assertEq(strategy.REMOTE_EID(), ROBINHOOD_EID);
        assertEq(strategy.REMOTE_COUNTERPART(), remoteCounterpart);
        assertEq(uint256(strategy.REMOTE_ID()), uint256(ROBINHOOD_EID));
    }

    /*//////////////////////////////////////////////////////////////
                        OUTBOUND OFT BRIDGE (REAL)
    //////////////////////////////////////////////////////////////*/

    /// @notice Depositing bridges USDG to Robinhood through the real OFT
    ///         adapter: USDG is burned, remoteAssets credited, ETH fee paid.
    function test_deposit_bridgesViaOFT() public {
        uint256 amount = 10_000e6;

        uint256 ethBefore = address(strategy).balance;

        _deposit(amount);

        // USDG left the strategy (burned by the mint/burn adapter)
        assertEq(IERC20(USDG).balanceOf(address(strategy)), 0, "!burned");

        // Optimistic remote credit + watermark bump
        assertEq(strategy.remoteAssets(), amount, "!remoteAssets");
        assertEq(strategy.totalAssets(), amount, "!totalAssets");
        assertEq(strategy.lastRemoteAssetsReport(), block.timestamp);

        // A LayerZero native fee was paid from the reserve
        assertLt(address(strategy).balance, ethBefore, "!fee");
    }

    function test_deposit_revertsWithoutEthReserve() public {
        vm.prank(management);
        strategy.rescueETH(management, address(strategy).balance);

        _dealUSDG(depositor, 1_000e6);
        vm.startPrank(depositor);
        IERC20(USDG).approve(address(strategy), 1_000e6);
        vm.expectRevert(bytes("!fee"));
        strategy.deposit(1_000e6, depositor);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REPORT RECEIVE (COMPOSE)
    //////////////////////////////////////////////////////////////*/

    /// @dev Build the OFT compose message the endpoint delivers to lzCompose:
    ///      nonce(8) | srcEid(4) | amountLD(32) | composeFrom(32) | payload.
    function _composeMsg(
        uint32 _srcEid,
        address _composeFrom,
        bytes memory _payload
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint64(1),
                _srcEid,
                uint256(0),
                bytes32(uint256(uint160(_composeFrom))),
                _payload
            );
    }

    function test_lzCompose_updatesRemoteAssets() public {
        _deposit(10_000e6);

        // Remote reports a profit
        uint256 reported = 10_100e6;
        bytes memory message = _composeMsg(
            ROBINHOOD_EID,
            remoteCounterpart,
            abi.encode(reported, block.timestamp + 1)
        );

        vm.prank(LZ_ENDPOINT);
        strategy.lzCompose(USDG_OFT, bytes32(0), message, address(0), "");

        assertEq(strategy.remoteAssets(), reported);
    }

    function test_lzCompose_onlyEndpoint() public {
        bytes memory message = _composeMsg(
            ROBINHOOD_EID,
            remoteCounterpart,
            abi.encode(uint256(1e6), block.timestamp + 1)
        );

        vm.expectRevert(bytes("!endpoint"));
        strategy.lzCompose(USDG_OFT, bytes32(0), message, address(0), "");
    }

    function test_lzCompose_wrongOft() public {
        bytes memory message = _composeMsg(
            ROBINHOOD_EID,
            remoteCounterpart,
            abi.encode(uint256(1e6), block.timestamp + 1)
        );

        vm.prank(LZ_ENDPOINT);
        vm.expectRevert(bytes("!oft"));
        strategy.lzCompose(address(0xBAD), bytes32(0), message, address(0), "");
    }

    function test_lzCompose_wrongSrcEid() public {
        bytes memory message = _composeMsg(
            30111, // wrong
            remoteCounterpart,
            abi.encode(uint256(1e6), block.timestamp + 1)
        );

        vm.prank(LZ_ENDPOINT);
        vm.expectRevert(bytes("!srcEid"));
        strategy.lzCompose(USDG_OFT, bytes32(0), message, address(0), "");
    }

    function test_lzCompose_wrongSender() public {
        bytes memory message = _composeMsg(
            ROBINHOOD_EID,
            user, // wrong composeFrom
            abi.encode(uint256(1e6), block.timestamp + 1)
        );

        vm.prank(LZ_ENDPOINT);
        vm.expectRevert(bytes("!sender"));
        strategy.lzCompose(USDG_OFT, bytes32(0), message, address(0), "");
    }

    /*//////////////////////////////////////////////////////////////
                            ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function test_rescueETH_onlyManagement() public {
        address recipient = address(0xE7E7);

        vm.prank(user);
        vm.expectRevert("!management");
        strategy.rescueETH(recipient, 1 ether);

        vm.prank(management);
        strategy.rescueETH(recipient, 1 ether);
        assertEq(recipient.balance, 1 ether);
    }

    function test_rescue_blocksAsset() public {
        vm.prank(management);
        vm.expectRevert(bytes("InvalidToken"));
        strategy.rescue(USDG, management, 1);
    }
}
