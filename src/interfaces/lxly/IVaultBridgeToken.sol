// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/// @title IVaultBridgeToken
/// @notice Interface for the Agglayer VaultBridgeToken (vbToken)
/// @dev VaultBridgeToken is an ERC-20 token and ERC-4626 vault that bridges to other networks
interface IVaultBridgeToken {
    /// @notice Deposit underlying assets and bridge the minted vbToken to another network
    /// @param assets Amount of underlying assets to deposit
    /// @param receiver Address that will receive the bridged vbToken on destination
    /// @param destinationNetworkId Network ID of the destination chain
    /// @param forceUpdateGlobalExitRoot Force update of global exit root
    /// @return shares Amount of vbToken shares minted and bridged
    function depositAndBridge(
        uint256 assets,
        address receiver,
        uint32 destinationNetworkId,
        bool forceUpdateGlobalExitRoot
    ) external returns (uint256 shares);

    /// @notice Deposit underlying assets and bridge with permit
    /// @param assets Amount of underlying assets to deposit
    /// @param receiver Address that will receive the bridged vbToken on destination
    /// @param destinationNetworkId Network ID of the destination chain
    /// @param forceUpdateGlobalExitRoot Force update of global exit root
    /// @param deadline Permit deadline
    /// @param v Permit signature v
    /// @param r Permit signature r
    /// @param s Permit signature s
    /// @return shares Amount of vbToken shares minted and bridged
    function depositWithPermitAndBridge(
        uint256 assets,
        address receiver,
        uint32 destinationNetworkId,
        bool forceUpdateGlobalExitRoot,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares);

    /// @notice Claim bridged vbToken and redeem for underlying assets
    /// @param smtProofLocalExitRoot Merkle proof against network exit root
    /// @param smtProofRollupExitRoot Merkle proof against rollup exit root
    /// @param globalIndex Encoded index specifying origin network and leaf position
    /// @param mainnetExitRoot Exit root hash from mainnet
    /// @param rollupExitRoot Exit root hash from rollup
    /// @param destinationAddress Original destination address
    /// @param amount Amount of vbToken to claim
    /// @param receiver Address to receive the underlying assets
    /// @param metadata Token metadata
    /// @return assets Amount of underlying assets received
    function claimAndRedeem(
        bytes32[32] calldata smtProofLocalExitRoot,
        bytes32[32] calldata smtProofRollupExitRoot,
        uint256 globalIndex,
        bytes32 mainnetExitRoot,
        bytes32 rollupExitRoot,
        address destinationAddress,
        uint256 amount,
        address receiver,
        bytes calldata metadata
    ) external returns (uint256 assets);

    // ERC-4626 standard functions

    /// @notice Get the underlying asset address
    /// @return The address of the underlying asset
    function asset() external view returns (address);

    /// @notice Deposit underlying assets
    /// @param assets Amount of underlying assets to deposit
    /// @param receiver Address to receive the shares
    /// @return shares Amount of shares minted
    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);

    /// @notice Redeem shares for underlying assets
    /// @param shares Amount of shares to redeem
    /// @param receiver Address to receive the assets
    /// @param owner Address that owns the shares
    /// @return assets Amount of underlying assets received
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);

    /// @notice Withdraw underlying assets
    /// @param assets Amount of underlying assets to withdraw
    /// @param receiver Address to receive the assets
    /// @param owner Address that owns the shares
    /// @return shares Amount of shares burned
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    /// @notice Convert shares to assets
    /// @param shares Amount of shares
    /// @return assets Equivalent amount of underlying assets
    function convertToAssets(
        uint256 shares
    ) external view returns (uint256 assets);

    /// @notice Convert assets to shares
    /// @param assets Amount of underlying assets
    /// @return shares Equivalent amount of shares
    function convertToShares(
        uint256 assets
    ) external view returns (uint256 shares);

    /// @notice Get maximum deposit amount
    /// @param receiver Address that would receive shares
    /// @return Maximum amount of assets that can be deposited
    function maxDeposit(address receiver) external view returns (uint256);

    /// @notice Get maximum redeem amount
    /// @param owner Address that owns the shares
    /// @return Maximum amount of shares that can be redeemed
    function maxRedeem(address owner) external view returns (uint256);

    /// @notice Preview deposit amount
    /// @param assets Amount of underlying assets
    /// @return shares Amount of shares that would be minted
    function previewDeposit(
        uint256 assets
    ) external view returns (uint256 shares);

    /// @notice Preview redeem amount
    /// @param shares Amount of shares
    /// @return assets Amount of underlying assets that would be received
    function previewRedeem(
        uint256 shares
    ) external view returns (uint256 assets);

    /// @notice Get total assets in the vault
    /// @return Total amount of underlying assets
    function totalAssets() external view returns (uint256);

    // ERC-20 standard functions

    /// @notice Get balance of an account
    /// @param account Address to query
    /// @return Balance of the account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Get total supply
    /// @return Total token supply
    function totalSupply() external view returns (uint256);

    /// @notice Approve spender
    /// @param spender Address to approve
    /// @param amount Amount to approve
    /// @return success True if successful
    function approve(
        address spender,
        uint256 amount
    ) external returns (bool success);

    /// @notice Transfer tokens
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return success True if successful
    function transfer(
        address to,
        uint256 amount
    ) external returns (bool success);

    /// @notice Transfer tokens from another address
    /// @param from Sender address
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return success True if successful
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool success);

    /// @notice Get allowance
    /// @param owner Token owner
    /// @param spender Approved spender
    /// @return Remaining allowance
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
}
