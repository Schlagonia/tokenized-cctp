// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseOFT} from "../bases/BaseOFT.sol";
import {SendParam, MessagingFee, OFTReceipt, MessagingReceipt} from "../interfaces/layerzero/IOFT.sol";

contract MockOFTERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @notice Mock LayerZero OFT supporting both native (burn) and adapter
///         (lockbox/transferFrom) modes.
contract MockOFT {
    MockOFTERC20 public immutable underlying;

    bool public approvalRequired;
    uint256 public decimalConversionRate = 1e12;
    uint256 public nativeFee = 0.001 ether;

    /// @dev Simulated fee-on-send in bps, applied to amountReceivedLD.
    uint256 public receiveSkimBps;

    uint32 public lastDstEid;
    bytes32 public lastTo;
    uint256 public lastAmountSent;

    constructor(address _token, bool _approvalRequired) {
        underlying = MockOFTERC20(_token);
        approvalRequired = _approvalRequired;
    }

    function token() external view returns (address) {
        return address(underlying);
    }

    function setNativeFee(uint256 _fee) external {
        nativeFee = _fee;
    }

    function setReceiveSkimBps(uint256 _bps) external {
        receiveSkimBps = _bps;
    }

    function quoteSend(
        SendParam calldata,
        bool
    ) external view returns (MessagingFee memory) {
        return MessagingFee({nativeFee: nativeFee, lzTokenFee: 0});
    }

    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address
    )
        external
        payable
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory receipt)
    {
        require(msg.value >= _fee.nativeFee, "mock !fee");

        // Dust removal exactly like a real OFT
        uint256 sent = _sendParam.amountLD -
            (_sendParam.amountLD % decimalConversionRate);
        require(sent >= _sendParam.minAmountLD, "mock !min");

        if (approvalRequired) {
            underlying.transferFrom(msg.sender, address(this), sent);
        } else {
            underlying.burn(msg.sender, sent);
        }

        lastDstEid = _sendParam.dstEid;
        lastTo = _sendParam.to;
        lastAmountSent = sent;

        receipt = OFTReceipt({
            amountSentLD: sent,
            amountReceivedLD: (sent * (10_000 - receiveSkimBps)) / 10_000
        });
        msgReceipt = MessagingReceipt({guid: bytes32(0), nonce: 1, fee: _fee});
    }
}

contract OFTHarness is BaseOFT {
    function oftSend(
        address _oft,
        uint32 _dstEid,
        address _to,
        uint256 _amountLD
    ) external payable returns (uint256) {
        return _oftSend(_oft, _dstEid, _to, _amountLD);
    }

    function rescueETH(address _to, uint256 _amount) external {
        _rescueETH(_to, _amount);
    }
}

contract OFTBaseTest is Test {
    MockOFTERC20 public token;
    MockOFT public oft;
    MockOFT public adapter;
    OFTHarness public harness;

    address public recipient = address(0xBEEF);
    uint32 public constant DST_EID = 30375;

    function setUp() public {
        token = new MockOFTERC20();
        oft = new MockOFT(address(token), false);
        adapter = new MockOFT(address(token), true);
        harness = new OFTHarness();
    }

    function test_send_burnsAndReturnsReceived() public {
        token.mint(address(harness), 100e18);
        vm.deal(address(harness), 1 ether);

        uint256 received = harness.oftSend(
            address(oft),
            DST_EID,
            recipient,
            100e18
        );

        assertEq(received, 100e18);
        assertEq(token.balanceOf(address(harness)), 0);
        assertEq(oft.lastDstEid(), DST_EID);
        assertEq(oft.lastTo(), bytes32(uint256(uint160(recipient))));
    }

    function test_send_dustTruncation() public {
        uint256 amount = 100e18 + 123_456; // not a multiple of 1e12
        token.mint(address(harness), amount);
        vm.deal(address(harness), 1 ether);

        uint256 received = harness.oftSend(
            address(oft),
            DST_EID,
            recipient,
            amount
        );

        // Dust below the shared-decimal granularity stays local
        assertEq(received, 100e18);
        assertEq(token.balanceOf(address(harness)), 123_456);
    }

    function test_send_adapterApprovalPath() public {
        token.mint(address(harness), 50e18);
        vm.deal(address(harness), 1 ether);

        uint256 received = harness.oftSend(
            address(adapter),
            DST_EID,
            recipient,
            50e18
        );

        assertEq(received, 50e18);
        // Tokens locked in the adapter, not burned
        assertEq(token.balanceOf(address(adapter)), 50e18);
        assertEq(token.balanceOf(address(harness)), 0);
    }

    function test_send_revertsWithoutFee() public {
        token.mint(address(harness), 10e18);
        // No ETH in the harness

        vm.expectRevert(bytes("!fee"));
        harness.oftSend(address(oft), DST_EID, recipient, 10e18);
    }

    function test_send_payableFunding() public {
        token.mint(address(harness), 10e18);

        // Fund the fee within the same call
        uint256 received = harness.oftSend{value: 0.001 ether}(
            address(oft),
            DST_EID,
            recipient,
            10e18
        );

        assertEq(received, 10e18);
    }

    function test_send_creditsReceivedNotSent() public {
        oft.setReceiveSkimBps(100); // 1% fee-on-send OFT
        token.mint(address(harness), 100e18);
        vm.deal(address(harness), 1 ether);

        uint256 received = harness.oftSend(
            address(oft),
            DST_EID,
            recipient,
            100e18
        );

        // Credited amount must be what arrives, not what was debited
        assertEq(received, 99e18);
        assertEq(oft.lastAmountSent(), 100e18);
    }

    function test_receiveETH() public {
        vm.deal(address(this), 1 ether);
        (bool success, ) = address(harness).call{value: 0.5 ether}("");
        assertTrue(success);
        assertEq(address(harness).balance, 0.5 ether);
    }

    function test_rescueETH() public {
        vm.deal(address(harness), 1 ether);

        harness.rescueETH(recipient, 0.4 ether);

        assertEq(recipient.balance, 0.4 ether);
        assertEq(address(harness).balance, 0.6 ether);
    }
}
