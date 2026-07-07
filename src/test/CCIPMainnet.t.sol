// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CCIPStrategy} from "../ccip/CCIPStrategy.sol";
import {ICCIPStrategy} from "../interfaces/ICCIPStrategy.sol";
import {Client} from "../interfaces/ccip/ICCIP.sol";

/// @notice Mainnet-only tests for the syrupUSDC -> Arbitrum CCIP strategy:
///         verifies the outbound bridge against the REAL CCIP router + token
///         pool, and the report-receive path with a pranked router.
contract CCIPMainnetTest is Test {
    ICCIPStrategy public strategy;

    address public constant SYRUP = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b; // syrupUSDC (6 dec)
    address public constant ROUTER = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    uint64 public constant ARB_SELECTOR = 4949039107694359620;
    uint64 public constant ETH_SELECTOR = 5009297550715157269;
    uint256 public constant GAS_LIMIT = 200_000;

    address public remoteCounterpart = address(0xB0B);
    address public management = address(1);
    address public keeper = address(4);
    address public depositor = address(6);
    address public user = address(10);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        strategy = ICCIPStrategy(
            address(
                new CCIPStrategy(
                    SYRUP,
                    "syrupUSDC Arbitrum CCIP Strategy",
                    ROUTER,
                    ARB_SELECTOR,
                    42161,
                    remoteCounterpart,
                    depositor,
                    GAS_LIMIT
                )
            )
        );

        address cm = strategy.management();
        vm.prank(cm);
        strategy.setPendingManagement(management);
        vm.prank(management);
        strategy.acceptManagement();
        vm.prank(management);
        strategy.setKeeper(keeper);

        vm.deal(address(strategy), 10 ether);

        vm.label(SYRUP, "syrupUSDC");
        vm.label(ROUTER, "CCIP_ROUTER");
    }

    /// @dev syrupUSDC balance slot may not be `deal`-able; probe and write it.
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

    function _deposit(uint256 _amount) internal {
        _dealSyrup(depositor, _amount);
        vm.startPrank(depositor);
        IERC20(SYRUP).approve(address(strategy), _amount);
        strategy.deposit(_amount, depositor);
        vm.stopPrank();
    }

    function _report(
        uint64 _srcSelector,
        address _sender,
        bytes memory _data
    ) internal view returns (Client.Any2EVMMessage memory) {
        return
            Client.Any2EVMMessage({
                messageId: bytes32(0),
                sourceChainSelector: _srcSelector,
                sender: abi.encode(_sender),
                data: _data,
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            });
    }

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function test_setup() public {
        assertEq(strategy.asset(), SYRUP);
        assertEq(strategy.ROUTER(), ROUTER);
        assertEq(strategy.REMOTE_CHAIN_SELECTOR(), ARB_SELECTOR);
        assertEq(strategy.gasLimit(), GAS_LIMIT);
        assertEq(strategy.REMOTE_COUNTERPART(), remoteCounterpart);
        assertEq(uint256(strategy.REMOTE_ID()), uint256(ARB_SELECTOR));
    }

    /*//////////////////////////////////////////////////////////////
                        OUTBOUND BRIDGE (REAL CCIP)
    //////////////////////////////////////////////////////////////*/

    /// @notice Depositing bridges syrupUSDC to Arbitrum through the REAL CCIP
    ///         router + token pool: tokens leave, remoteAssets credited, fee
    ///         paid.
    function test_deposit_bridgesViaCCIP() public {
        uint256 amount = 1_000e6;

        uint256 ethBefore = address(strategy).balance;

        _deposit(amount);

        // syrupUSDC left the strategy (locked/burned by the CCIP pool)
        assertEq(IERC20(SYRUP).balanceOf(address(strategy)), 0, "!bridged");

        // Optimistic remote credit + watermark bump
        assertEq(strategy.remoteAssets(), amount, "!remoteAssets");
        assertEq(strategy.totalAssets(), amount, "!totalAssets");
        assertEq(strategy.lastRemoteAssetsReport(), block.timestamp);

        // A CCIP native fee was paid from the reserve
        assertLt(address(strategy).balance, ethBefore, "!fee");
    }

    function test_deposit_revertsWithoutEthReserve() public {
        vm.prank(management);
        strategy.rescueETH(management, address(strategy).balance);

        _dealSyrup(depositor, 1_000e6);
        vm.startPrank(depositor);
        IERC20(SYRUP).approve(address(strategy), 1_000e6);
        vm.expectRevert(bytes("!fee"));
        strategy.deposit(1_000e6, depositor);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REPORT RECEIVE
    //////////////////////////////////////////////////////////////*/

    function test_ccipReceive_updatesRemoteAssets() public {
        _deposit(1_000e6);

        uint256 reported = 1_010e6;
        Client.Any2EVMMessage memory message = _report(
            ARB_SELECTOR,
            remoteCounterpart,
            abi.encode(reported, block.timestamp + 1)
        );

        vm.prank(ROUTER);
        strategy.ccipReceive(message);

        assertEq(strategy.remoteAssets(), reported);
    }

    function test_ccipReceive_onlyRouter() public {
        Client.Any2EVMMessage memory message = _report(
            ARB_SELECTOR,
            remoteCounterpart,
            abi.encode(uint256(1e6), block.timestamp + 1)
        );
        vm.expectRevert(bytes("!router"));
        strategy.ccipReceive(message);
    }

    function test_ccipReceive_wrongSrcChain() public {
        Client.Any2EVMMessage memory message = _report(
            123, // wrong selector
            remoteCounterpart,
            abi.encode(uint256(1e6), block.timestamp + 1)
        );
        vm.prank(ROUTER);
        vm.expectRevert(bytes("!srcChain"));
        strategy.ccipReceive(message);
    }

    function test_ccipReceive_wrongSender() public {
        Client.Any2EVMMessage memory message = _report(
            ARB_SELECTOR,
            user, // wrong sender
            abi.encode(uint256(1e6), block.timestamp + 1)
        );
        vm.prank(ROUTER);
        vm.expectRevert(bytes("!sender"));
        strategy.ccipReceive(message);
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
        strategy.rescue(SYRUP, management, 1);
    }

    function test_supportsInterface() public {
        // IAny2EVMMessageReceiver + IERC165
        assertTrue(strategy.supportsInterface(0x85572ffb));
        assertTrue(strategy.supportsInterface(0x01ffc9a7));
        assertFalse(strategy.supportsInterface(0xffffffff));
    }
}
