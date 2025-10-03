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

    // Known CCTP contract addresses (mainnet)
    address public constant ETHEREUM_TOKEN_MESSENGER =
        0xBd3fa81B58Ba92a82136038B25aDec7066af3155;
    address public constant ETHEREUM_MESSAGE_TRANSMITTER =
        0x0a992d191DEeC32aFe36203Ad87D7d289a738F81;
    address public constant ETHEREUM_USDC =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address public constant ARBITRUM_TOKEN_MESSENGER =
        0x19330d10D9Cc8751218eaf51E8885D058642E08A;
    address public constant ARBITRUM_MESSAGE_TRANSMITTER =
        0xC30362313FBBA5cf9163F0bb16a0e01f01A896ca;
    address public constant ARBITRUM_USDC =
        0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    address public constant OPTIMISM_TOKEN_MESSENGER =
        0x2B4069517957735bE00ceE0fadAE88a26365528f;
    address public constant OPTIMISM_MESSAGE_TRANSMITTER =
        0x4D41f22c5a0e5c74090899E5a8Fb597a8842b3e8;
    address public constant OPTIMISM_USDC =
        0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;

    address public constant BASE_TOKEN_MESSENGER =
        0x1682Ae6375C4E4A97e4B583BC394c861A46D8962;
    address public constant BASE_MESSAGE_TRANSMITTER =
        0xAD09780d193884d503182aD4588450C416D6F9D4;
    address public constant BASE_USDC =
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    address public constant POLYGON_TOKEN_MESSENGER =
        0x9daF8c91AEFAE50b9c0E69629D3F6Ca40cA3B3FE;
    address public constant POLYGON_MESSAGE_TRANSMITTER =
        0xF3be9355363857F3e001be68856A2f96b4C39Ba9;
    address public constant POLYGON_USDC =
        0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

    address public constant AVALANCHE_TOKEN_MESSENGER =
        0x6B25532e1060CE10cc3B0A99e5683b91BFDe6982;
    address public constant AVALANCHE_MESSAGE_TRANSMITTER =
        0x8186359aF5F57FbB40c6b14A588d2A59C0C29880;
    address public constant AVALANCHE_USDC =
        0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;

    function getTokenMessenger(uint32 domain) internal pure returns (address) {
        if (domain == ETHEREUM_DOMAIN) return ETHEREUM_TOKEN_MESSENGER;
        if (domain == ARBITRUM_DOMAIN) return ARBITRUM_TOKEN_MESSENGER;
        if (domain == OPTIMISM_DOMAIN) return OPTIMISM_TOKEN_MESSENGER;
        if (domain == BASE_DOMAIN) return BASE_TOKEN_MESSENGER;
        if (domain == POLYGON_DOMAIN) return POLYGON_TOKEN_MESSENGER;
        if (domain == AVALANCHE_DOMAIN) return AVALANCHE_TOKEN_MESSENGER;
        revert("Unsupported domain");
    }

    function getMessageTransmitter(
        uint32 domain
    ) internal pure returns (address) {
        if (domain == ETHEREUM_DOMAIN) return ETHEREUM_MESSAGE_TRANSMITTER;
        if (domain == ARBITRUM_DOMAIN) return ARBITRUM_MESSAGE_TRANSMITTER;
        if (domain == OPTIMISM_DOMAIN) return OPTIMISM_MESSAGE_TRANSMITTER;
        if (domain == BASE_DOMAIN) return BASE_MESSAGE_TRANSMITTER;
        if (domain == POLYGON_DOMAIN) return POLYGON_MESSAGE_TRANSMITTER;
        if (domain == AVALANCHE_DOMAIN) return AVALANCHE_MESSAGE_TRANSMITTER;
        revert("Unsupported domain");
    }

    function getUSDC(uint32 domain) internal pure returns (address) {
        if (domain == ETHEREUM_DOMAIN) return ETHEREUM_USDC;
        if (domain == ARBITRUM_DOMAIN) return ARBITRUM_USDC;
        if (domain == OPTIMISM_DOMAIN) return OPTIMISM_USDC;
        if (domain == BASE_DOMAIN) return BASE_USDC;
        if (domain == POLYGON_DOMAIN) return POLYGON_USDC;
        if (domain == AVALANCHE_DOMAIN) return AVALANCHE_USDC;
        revert("Unsupported domain");
    }

    function getDomainName(
        uint32 domain
    ) internal pure returns (string memory) {
        if (domain == ETHEREUM_DOMAIN) return "Ethereum";
        if (domain == ARBITRUM_DOMAIN) return "Arbitrum";
        if (domain == OPTIMISM_DOMAIN) return "Optimism";
        if (domain == BASE_DOMAIN) return "Base";
        if (domain == POLYGON_DOMAIN) return "Polygon";
        if (domain == AVALANCHE_DOMAIN) return "Avalanche";
        return "Unknown";
    }

    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function bytes32ToAddress(bytes32 _buf) internal pure returns (address) {
        return address(uint160(uint256(_buf)));
    }

    // Parse CCTP message to extract key fields
    struct ParsedMessage {
        uint32 version;
        uint32 sourceDomain;
        uint32 destinationDomain;
        uint64 nonce;
        bytes32 sender;
        bytes32 recipient;
        bytes32 destinationCaller;
        bytes messageBody;
    }

    function parseMessage(
        bytes calldata message
    ) internal pure returns (ParsedMessage memory parsed) {
        require(message.length >= 116, "Message too short");

        uint256 offset = 0;

        // Version (4 bytes)
        parsed.version = uint32(bytes4(message[offset:offset + 4]));
        offset += 4;

        // Source domain (4 bytes)
        parsed.sourceDomain = uint32(bytes4(message[offset:offset + 4]));
        offset += 4;

        // Destination domain (4 bytes)
        parsed.destinationDomain = uint32(bytes4(message[offset:offset + 4]));
        offset += 4;

        // Nonce (8 bytes)
        parsed.nonce = uint64(bytes8(message[offset:offset + 8]));
        offset += 8;

        // Sender (32 bytes)
        parsed.sender = bytes32(message[offset:offset + 32]);
        offset += 32;

        // Recipient (32 bytes)
        parsed.recipient = bytes32(message[offset:offset + 32]);
        offset += 32;

        // Destination caller (32 bytes)
        parsed.destinationCaller = bytes32(message[offset:offset + 32]);
        offset += 32;

        // Message body (remaining bytes)
        if (message.length > offset) {
            parsed.messageBody = message[offset:];
        }

        return parsed;
    }

    // Parse burn message body
    struct BurnMessage {
        uint32 version;
        bytes32 burnToken;
        bytes32 mintRecipient;
        uint256 amount;
        bytes32 messageSender;
    }

    function parseBurnMessage(
        bytes memory messageBody
    ) internal pure returns (BurnMessage memory burnMessage) {
        require(messageBody.length >= 132, "Burn message too short");

        uint256 offset = 0;

        // Version (4 bytes)
        bytes4 versionBytes;
        assembly {
            versionBytes := mload(add(add(messageBody, 0x20), offset))
        }
        burnMessage.version = uint32(versionBytes);
        offset += 4;

        // Burn token (32 bytes)
        assembly {
            mstore(burnMessage, mload(add(add(messageBody, 0x20), offset)))
        }
        offset += 32;

        // Mint recipient (32 bytes)
        assembly {
            mstore(
                add(burnMessage, 0x20),
                mload(add(add(messageBody, 0x20), offset))
            )
        }
        offset += 32;

        // Amount (32 bytes)
        assembly {
            mstore(
                add(burnMessage, 0x40),
                mload(add(add(messageBody, 0x20), offset))
            )
        }
        offset += 32;

        // Message sender (32 bytes)
        assembly {
            mstore(
                add(burnMessage, 0x60),
                mload(add(add(messageBody, 0x20), offset))
            )
        }

        return burnMessage;
    }
}
