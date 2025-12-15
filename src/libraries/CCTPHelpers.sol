// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

library CCTPHelpers {
    // CCTP Domain IDs for different chains
    uint32 public constant ETHEREUM_DOMAIN = 0;
    uint32 public constant AVALANCHE_DOMAIN = 1;
    uint32 public constant OPTIMISM_DOMAIN = 2;
    uint32 public constant ARBITRUM_DOMAIN = 3;
    uint32 public constant BASE_DOMAIN = 6;
    uint32 public constant POLYGON_DOMAIN = 7;
    uint32 public constant HYPEREVM_DOMAIN = 19;

    // Known CCTP contract addresses (mainnet)
    address public constant TOKEN_MESSENGER =
        0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address public constant MESSAGE_TRANSMITTER =
        0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;
    address public constant TOKEN_MINTER =
        0xfd78EE919681417d192449715b2594ab58f5D002;

    address public constant ETHEREUM_USDC =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant ARBITRUM_USDC =
        0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant OPTIMISM_USDC =
        0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address public constant BASE_USDC =
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant POLYGON_USDC =
        0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address public constant AVALANCHE_USDC =
        0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address public constant HYPEREVM_USDC =
        0xb88339CB7199b77E23DB6E890353E22632Ba630f;

    function getUSDC(uint32 domain) internal pure returns (address) {
        if (domain == ETHEREUM_DOMAIN) return ETHEREUM_USDC;
        if (domain == ARBITRUM_DOMAIN) return ARBITRUM_USDC;
        if (domain == OPTIMISM_DOMAIN) return OPTIMISM_USDC;
        if (domain == BASE_DOMAIN) return BASE_USDC;
        if (domain == POLYGON_DOMAIN) return POLYGON_USDC;
        if (domain == AVALANCHE_DOMAIN) return AVALANCHE_USDC;
        if (domain == HYPEREVM_DOMAIN) return HYPEREVM_USDC;
        revert("Unsupported domain");
    }

    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function bytes32ToAddress(bytes32 _buf) internal pure returns (address) {
        return address(uint160(uint256(_buf)));
    }
}
