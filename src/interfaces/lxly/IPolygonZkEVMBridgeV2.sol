// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/// @title IPolygonZkEVMBridgeV2
/// @notice Interface for the Polygon zkEVM Unified Bridge (LxLy)
interface IPolygonZkEVMBridgeV2 {
    /// @notice Bridge assets to another network
    /// @param destinationNetwork Network identifier where the asset should be sent
    /// @param destinationAddress Address that will receive the bridged asset
    /// @param amount Amount of tokens to bridge
    /// @param token Token address to bridge (address(0) for native token)
    /// @param forceUpdateGlobalExitRoot Force update of global exit root
    /// @param permitData Optional permit data for token approval
    function bridgeAsset(
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        address token,
        bool forceUpdateGlobalExitRoot,
        bytes calldata permitData
    ) external payable;

    /// @notice Bridge a message to another network
    /// @param destinationNetwork Network identifier where the message should be sent
    /// @param destinationAddress Address that will receive the message
    /// @param forceUpdateGlobalExitRoot Force update of global exit root
    /// @param metadata Message data to bridge
    function bridgeMessage(
        uint32 destinationNetwork,
        address destinationAddress,
        bool forceUpdateGlobalExitRoot,
        bytes calldata metadata
    ) external payable;

    /// @notice Bridge a message with ETH value to another network
    /// @param destinationNetwork Network identifier where the message should be sent
    /// @param destinationAddress Address that will receive the message
    /// @param amountWETH Amount of WETH to include with the message
    /// @param forceUpdateGlobalExitRoot Force update of global exit root
    /// @param metadata Message data to bridge
    function bridgeMessageWETH(
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amountWETH,
        bool forceUpdateGlobalExitRoot,
        bytes calldata metadata
    ) external;

    /// @notice Claim bridged assets using Merkle proofs
    /// @param smtProofLocalExitRoot Merkle proof against network exit root
    /// @param smtProofRollupExitRoot Merkle proof against rollup exit root
    /// @param globalIndex Encoded index specifying origin network and leaf position
    /// @param mainnetExitRoot Exit root hash from mainnet
    /// @param rollupExitRoot Exit root hash from rollup
    /// @param originNetwork Source network identifier
    /// @param originTokenAddress Token address on origin network
    /// @param destinationNetwork Target network identifier
    /// @param destinationAddress Recipient address
    /// @param amount Amount to claim
    /// @param metadata Token metadata for wrapped token creation
    function claimAsset(
        bytes32[32] calldata smtProofLocalExitRoot,
        bytes32[32] calldata smtProofRollupExitRoot,
        uint256 globalIndex,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        uint32 originNetwork,
        address originTokenAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata metadata
    ) external;

    /// @notice Claim bridged message using Merkle proofs
    /// @param smtProofLocalExitRoot Merkle proof against network exit root
    /// @param smtProofRollupExitRoot Merkle proof against rollup exit root
    /// @param globalIndex Encoded index specifying origin network and leaf position
    /// @param mainnetExitRoot Exit root hash from mainnet
    /// @param rollupExitRoot Exit root hash from rollup
    /// @param originNetwork Source network identifier
    /// @param originAddress Sender address on origin network
    /// @param destinationNetwork Target network identifier
    /// @param destinationAddress Recipient address
    /// @param amount ETH amount included with message
    /// @param metadata Message data
    function claimMessage(
        bytes32[32] calldata smtProofLocalExitRoot,
        bytes32[32] calldata smtProofRollupExitRoot,
        uint256 globalIndex,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        uint32 originNetwork,
        address originAddress,
        uint32 destinationNetwork,
        address destinationAddress,
        uint256 amount,
        bytes calldata metadata
    ) external;

    /// @notice Get the network ID of this bridge instance
    /// @return Network identifier
    function networkID() external view returns (uint32);

    /// @notice Get the wrapped token address for a given origin token
    /// @param originNetwork Origin network identifier
    /// @param originTokenAddress Token address on origin network
    /// @return Wrapped token address on this network
    function getTokenWrappedAddress(
        uint32 originNetwork,
        address originTokenAddress
    ) external view returns (address);
}
