// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

library CREATE {
    // Minimal RLP for (sender, nonce) where nonce fits in <= 7 bytes (covers practical ranges)
    function predict(
        address deployer,
        uint256 nonce
    ) internal pure returns (address) {
        bytes memory rlpNonce;

        if (nonce == 0) {
            rlpNonce = hex"80"; // RLP empty
        } else if (nonce <= 0x7f) {
            rlpNonce = abi.encodePacked(uint8(nonce));
        } else if (nonce <= 0xff) {
            rlpNonce = abi.encodePacked(bytes1(0x81), uint8(nonce));
        } else if (nonce <= 0xffff) {
            rlpNonce = abi.encodePacked(bytes1(0x82), bytes2(uint16(nonce)));
        } else if (nonce <= 0xffffff) {
            rlpNonce = abi.encodePacked(bytes1(0x83), bytes3(uint24(nonce)));
        } else if (nonce <= 0xffffffff) {
            rlpNonce = abi.encodePacked(bytes1(0x84), bytes4(uint32(nonce)));
        } else if (nonce <= 0xffffffffff) {
            rlpNonce = abi.encodePacked(bytes1(0x85), bytes5(uint40(nonce)));
        } else if (nonce <= 0xffffffffffff) {
            rlpNonce = abi.encodePacked(bytes1(0x86), bytes6(uint48(nonce)));
        } else if (nonce <= 0xffffffffffffff) {
            rlpNonce = abi.encodePacked(bytes1(0x87), bytes7(uint56(nonce)));
        } else {
            revert("nonce too large");
        }

        // RLP(address) = 0x94 + 20 bytes
        bytes memory rlpAddr = abi.encodePacked(bytes1(0x94), deployer);

        // RLP list prefix = 0xc0 + payload_len, here < 56 so single byte
        uint256 payloadLen = 21 + rlpNonce.length;
        bytes1 listPrefix = bytes1(uint8(0xc0 + payloadLen));

        bytes32 h = keccak256(abi.encodePacked(listPrefix, rlpAddr, rlpNonce));
        return address(uint160(uint(h)));
    }
}
