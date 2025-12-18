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
    // Source: https://docs.katana.network/katana/technical-reference/contract-addresses/
    address public constant VB_USDC =
        0x53E82ABbb12638F09d9e624578ccB666217a765e; // vbUSDC on Ethereum
    address public constant VB_WETH =
        0x2DC70fb75b88d2eB4715bc06E1595E6D97c34DFF; // vbWETH on Ethereum (wraps native ETH)
    address public constant VB_USDT =
        0x6d4f9f9f8f0155509ecd6Ac6c544fF27999845CC; // vbUSDT on Ethereum
    address public constant VB_USDS =
        0x3DD459dE96F9C28e3a343b831cbDC2B93c8C4855; // vbUSDS on Ethereum
    address public constant VB_WBTC =
        0x2C24B57e2CCd1f273045Af6A5f632504C432374F; // vbWBTC on Ethereum

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
    /// @dev Note: vbETH wraps native ETH, not WETH. Use address(0) for ETH.
    function getVbToken(address underlying) internal pure returns (address) {
        if (underlying == ETHEREUM_USDC) return VB_USDC;
        if (underlying == ETHEREUM_USDT) return VB_USDT;
        if (underlying == ETHEREUM_WBTC) return VB_WBTC;
        if (underlying == address(0)) return VB_WETH; // Native ETH
        if (underlying == ETHEREUM_WETH) return VB_WETH; // Native ETH
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
