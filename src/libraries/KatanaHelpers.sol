// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/// @title KatanaHelpers
/// @notice Helper library for Katana/Agglayer LxLy bridge integration
library KatanaHelpers {
    // LxLy Network IDs for different chains
    uint32 public constant ETHEREUM_NETWORK_ID = 0;
    uint32 public constant KATANA_NETWORK_ID = 20;

    // Unified Bridge address (same on all chains)
    address public constant UNIFIED_BRIDGE =
        0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;

    // Bridge & Call contract on Ethereum
    address public constant BRIDGE_AND_CALL =
        0x64B20Eb25AEd030FD510EF93B9135278B152f6a6;

    // VaultBridgeToken addresses on Ethereum (Layer X)
    // These are the vbToken contracts that wrap underlying assets
    // TODO: Update with actual deployed addresses
    address public constant VB_USDC =
        address(0xBEefb9f61CC44895d8AEc381373555a64191A9c4); // vbUSDC on Ethereum
    address public constant VB_WETH =
        address(0x31A5684983EeE865d943A696AAC155363bA024f9); // vbWETH on Ethereum
    address public constant VB_USDT =
        address(0xc54b4E08C1Dcc199fdd35c6b5Ab589ffD3428a8d); // vbUSDT on Ethereum
    address public constant VB_USDS = address(0); // vbUSDS on Ethereum
    address public constant VB_WBTC =
        address(0x812B2C6Ab3f4471c0E43D4BB61098a9211017427); // vbWBTC on Ethereum

    // Underlying asset addresses on Ethereum
    address public constant ETHEREUM_USDC =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant ETHEREUM_WETH =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant ETHEREUM_USDT =
        0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant ETHEREUM_WBTC =
        0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    /// @notice Get the vbToken address for a given underlying asset on Ethereum
    /// @param underlying The underlying asset address
    /// @return The vbToken address
    function getVbToken(address underlying) internal pure returns (address) {
        if (underlying == ETHEREUM_USDC) return VB_USDC;
        if (underlying == ETHEREUM_WETH) return VB_WETH;
        if (underlying == ETHEREUM_USDT) return VB_USDT;
        if (underlying == ETHEREUM_WBTC) return VB_WBTC;
        revert("Unsupported asset");
    }

    /// @notice Check if a network ID is valid for this bridge
    /// @param networkId The network ID to check
    /// @return True if the network ID is supported
    function isValidNetwork(uint32 networkId) internal pure returns (bool) {
        return
            networkId == ETHEREUM_NETWORK_ID || networkId == KATANA_NETWORK_ID;
    }
}
