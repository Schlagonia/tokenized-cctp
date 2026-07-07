// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/// @title OFTOptions
/// @notice Builds LayerZero V2 type-3 executor options for OFT sends without
///         the OptionsBuilder dependency. Layout per option:
///         workerId(1)=executor | size(2)=optionType+data | optionType(1) | data
library OFTOptions {
    /// @notice lzReceive (deliver tokens) + lzCompose (run the report) options.
    function composeOptions(
        uint128 _lzReceiveGas,
        uint128 _lzComposeGas
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                uint16(3), // TYPE_3
                uint8(1),
                uint16(17),
                uint8(1),
                _lzReceiveGas, // lzReceive: gas(16)
                uint8(1),
                uint16(19),
                uint8(3),
                uint16(0),
                _lzComposeGas // lzCompose: index(2)+gas(16)
            );
    }
}
