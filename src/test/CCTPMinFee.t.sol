// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CCTPRemoteStrategy} from "../CCTPRemoteStrategy.sol";
import {CCTPHelpers} from "../libraries/CCTPHelpers.sol";
import {ITokenMessenger} from "../interfaces/circle/ITokenMessenger.sol";
import {MockVault} from "./utils/KatanaSetup.sol";

interface IFeeSwitch {
    function minFeeController() external view returns (address);

    function setMinFee(uint256 _minFee) external;
}

/// @notice HyperEVM-fork tests for Circle's minimum fee. HyperEVM's token
///         messenger can charge one; Ethereum's and Base's can't.
///           HYPER_RPC_URL=<url> forge test --network ethereum \
///             --match-contract CCTPMinFeeTest
contract CCTPMinFeeTest is Test {
    CCTPRemoteStrategy public remote;

    address public constant USDC = CCTPHelpers.HYPEREVM_USDC;
    address public constant TOKEN_MESSENGER = CCTPHelpers.TOKEN_MESSENGER;

    address public originCounterpart = address(0xB0B);
    address public governance = address(7);
    address public keeper = address(4);

    uint256 public amount = 10_000e6;

    function setUp() public {
        vm.createSelectFork(vm.envString("HYPER_RPC_URL"));

        remote = new CCTPRemoteStrategy(
            USDC,
            governance,
            TOKEN_MESSENGER,
            CCTPHelpers.MESSAGE_TRANSMITTER,
            CCTPHelpers.ETHEREUM_DOMAIN,
            originCounterpart,
            address(new MockVault(USDC))
        );

        vm.prank(governance);
        remote.setKeeper(keeper);

        deal(USDC, address(remote), amount);
        skip(1); // isReady
    }

    /// @dev In 1/1000 bps.
    function _setMinFee(uint256 _minFee) internal {
        vm.prank(IFeeSwitch(TOKEN_MESSENGER).minFeeController());
        IFeeSwitch(TOKEN_MESSENGER).setMinFee(_minFee);
    }

    /// @dev The remote's burn of `amount`, offering `_maxFee`.
    function _burn(uint256 _maxFee) internal view returns (bytes memory) {
        return
            abi.encodeCall(
                ITokenMessenger.depositForBurn,
                (
                    amount,
                    CCTPHelpers.ETHEREUM_DOMAIN,
                    bytes32(uint256(uint160(originCounterpart))),
                    USDC,
                    bytes32(0),
                    _maxFee,
                    2_000
                )
            );
    }

    /// @notice With a minimum fee set, a burn that offers none reverts.
    function test_zeroMaxFee_reverts() public {
        _setMinFee(1_000); // 1 bp

        vm.prank(address(remote));
        (bool ok, bytes memory err) = TOKEN_MESSENGER.call(_burn(0));

        assertFalse(ok);
        assertEq(
            err,
            abi.encodeWithSignature("Error(string)", "Insufficient max fee")
        );
    }

    /// @notice The remote offers exactly the minimum, so funds still go home.
    function test_processWithdrawal_paysMinFee() public {
        _setMinFee(1_000); // 1 bp

        vm.expectCall(TOKEN_MESSENGER, _burn(1e6));
        vm.prank(keeper);
        remote.processWithdrawal(amount);

        assertEq(IERC20(USDC).balanceOf(address(remote)), 0, "!bridged");
    }

    function test_processWithdrawal_noFee() public {
        _setMinFee(0);

        vm.expectCall(TOKEN_MESSENGER, _burn(0));
        vm.prank(keeper);
        remote.processWithdrawal(amount);

        assertEq(IERC20(USDC).balanceOf(address(remote)), 0, "!bridged");
    }
}
