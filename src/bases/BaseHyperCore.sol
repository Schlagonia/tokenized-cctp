// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ICoreWriter} from "../interfaces/hyperliquid/ICoreWriter.sol";

/// @title BaseHyperCore
/// @notice Base contract for interacting with HyperCore L1 from HyperEVM
/// @dev Provides wrappers for precompile interactions including vault operations and balance queries
abstract contract BaseHyperCore {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice L1 Core Writer precompile for sending actions to HyperCore
    ICoreWriter internal constant L1_CORE_WRITER =
        ICoreWriter(0x3333333333333333333333333333333333333333);

    /// @notice Precompile for querying spot balances
    address internal constant SPOT_BALANCE_PRECOMPILE = address(0x0801);

    /// @notice Precompile for querying vault equity
    address internal constant VAULT_EQUITY_PRECOMPILE = address(0x0802);

    /// @notice Precompile for querying withdrawable perps balance
    address internal constant WITHDRAWABLE_PRECOMPILE = address(0x0803);

    /// @notice Precompile for querying spot prices
    address internal constant SPOT_PRICE_PRECOMPILE = address(0x0808);

    /// @notice Version byte for Core Writer actions
    uint8 internal constant CORE_WRITER_VERSION_1 = 1;

    /// @notice Action type for vault deposit/withdraw
    uint24 internal constant CORE_WRITER_ACTION_VAULT_TRANSFER = 2;

    /// @notice Action type for spot send (withdraw from spot)
    uint24 internal constant CORE_WRITER_ACTION_SPOT_SEND = 6;

    /// @notice Action type for USD class transfer (perps <-> spot)
    uint24 internal constant CORE_WRITER_ACTION_USD_CLASS_TRANSFER = 7;

    /// @notice USDC spot token index on HyperCore
    uint64 internal constant USDC_SPOT_INDEX = 0;

    /// @notice USDC system address for bridging (index 0)
    address internal constant USDC_SYSTEM_ADDRESS =
        0x2000000000000000000000000000000000000000;

    /// @notice CoreDepositWallet for depositing USDC from EVM to Core
    address internal constant CORE_DEPOSIT_WALLET =
        0x6B9E773128f453f5c2C60935Ee2DE2CBc5390A24;

    /// @notice Decimals for USDC in perps (6 decimals)
    uint8 internal constant PERP_DECIMALS = 6;

    /// @notice Decimals for USDC in spot (8 decimals)
    uint8 internal constant SPOT_DECIMALS = 8;

    /// @notice Scale factor from 6 decimals to 8 decimals (spot)
    uint256 internal constant PERP_TO_SPOT_SCALE = 100; // 10^(8-6)

    /// @notice Scale factor from 8 decimals to 18 decimals
    uint256 internal constant SPOT_TO_18_SCALE = 1e10; // 10^(18-8)

    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Parameters for vault deposit/withdraw operations
    struct VaultTransferParams {
        address vault;
        bool isDeposit;
        uint64 usd; // Amount in 6 decimals (perp decimals)
    }

    /// @notice Parameters for USD class transfer (perps <-> spot)
    struct UsdClassTransferParams {
        uint64 ntl; // Amount in 6 decimals (perp decimals)
        bool toPerp; // true = spot to perp, false = perp to spot
    }

    /// @notice Parameters for spot send (withdraw from spot)
    struct SpotSendParams {
        address destination;
        uint64 token;
        uint64 _wei; // Amount in spot decimals (8 for USDC)
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit USDC into a HyperCore vault (e.g., HLP)
    /// @param amount Amount in 6 decimals (EVM USDC decimals)
    /// @param vault The vault address on HyperCore
    function _vaultDeposit(uint256 amount, address vault) internal {
        // VaultTransfer uses perps decimals (6), same as EVM USDC - no scaling needed
        VaultTransferParams memory params = VaultTransferParams({
            vault: vault,
            isDeposit: true,
            usd: uint64(amount)
        });

        L1_CORE_WRITER.sendRawAction(
            abi.encodePacked(
                CORE_WRITER_VERSION_1,
                CORE_WRITER_ACTION_VAULT_TRANSFER,
                abi.encode(params)
            )
        );
    }

    /// @notice Withdraw USDC from a HyperCore vault (e.g., HLP)
    /// @param amount Amount in 6 decimals (EVM USDC decimals)
    /// @param vault The vault address on HyperCore
    function _vaultWithdraw(uint256 amount, address vault) internal {
        // VaultTransfer uses perps decimals (6), same as EVM USDC - no scaling needed
        VaultTransferParams memory params = VaultTransferParams({
            vault: vault,
            isDeposit: false,
            usd: uint64(amount)
        });

        L1_CORE_WRITER.sendRawAction(
            abi.encodePacked(
                CORE_WRITER_VERSION_1,
                CORE_WRITER_ACTION_VAULT_TRANSFER,
                abi.encode(params)
            )
        );
    }

    /// @notice Transfer USDC from perps account to spot account on HyperCore
    /// @param amount Amount in 6 decimals (perp decimals)
    function _perpsToSpot(uint256 amount) internal {
        UsdClassTransferParams memory params = UsdClassTransferParams({
            ntl: uint64(amount),
            toPerp: false // perp -> spot
        });

        L1_CORE_WRITER.sendRawAction(
            abi.encodePacked(
                CORE_WRITER_VERSION_1,
                CORE_WRITER_ACTION_USD_CLASS_TRANSFER,
                abi.encode(params)
            )
        );
    }

    /// @notice Transfer USDC from spot account to perps account on HyperCore
    /// @param amount Amount in 6 decimals (perp decimals)
    function _spotToPerps(uint256 amount) internal {
        UsdClassTransferParams memory params = UsdClassTransferParams({
            ntl: uint64(amount),
            toPerp: true // spot -> perp
        });

        L1_CORE_WRITER.sendRawAction(
            abi.encodePacked(
                CORE_WRITER_VERSION_1,
                CORE_WRITER_ACTION_USD_CLASS_TRANSFER,
                abi.encode(params)
            )
        );
    }

    /// @notice Send tokens from HyperCore spot account to an address
    /// @dev Uses SpotSend action
    /// @param destination The recipient address
    /// @param token The token index
    /// @param amount Amount in 6 decimals (EVM USDC decimals)
    function _spotSend(
        address destination,
        uint64 token,
        uint256 amount
    ) internal {
        // Convert from 6 decimals (EVM) to 8 decimals (HyperCore spot)
        uint64 spotAmount = uint64(amount * PERP_TO_SPOT_SCALE);

        SpotSendParams memory params = SpotSendParams({
            destination: destination,
            token: token,
            _wei: spotAmount
        });

        L1_CORE_WRITER.sendRawAction(
            abi.encodePacked(
                CORE_WRITER_VERSION_1,
                CORE_WRITER_ACTION_SPOT_SEND,
                abi.encode(params)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Query vault equity from HyperCore
    /// @param vault The vault address to query
    /// @return equity The vault equity in 18 decimals
    function _vaultEquity(
        address vault
    ) internal view returns (uint256 equity) {
        (bool success, bytes memory result) = VAULT_EQUITY_PRECOMPILE
            .staticcall(abi.encode(address(this), vault));
        require(success, "VaultEquityPrecompileFailed");

        // Result is in 8 decimals (spot), scale to 18
        uint256 rawEquity = abi.decode(result, (uint256));
        equity = rawEquity * SPOT_TO_18_SCALE;
    }

    /// @notice Query USDC spot balance from HyperCore
    /// @return balance The spot balance in 18 decimals
    function _usdSpotBalance() internal view returns (uint256 balance) {
        (bool success, bytes memory result) = SPOT_BALANCE_PRECOMPILE
            .staticcall(abi.encode(address(this), USDC_SPOT_INDEX));
        require(success, "SpotBalancePrecompileFailed");

        // Result is in 8 decimals (spot), scale to 18
        uint256 rawBalance = abi.decode(result, (uint256));
        balance = rawBalance * SPOT_TO_18_SCALE;
    }

    /// @notice Query withdrawable USDC from perps account on HyperCore
    /// @return balance The withdrawable balance in 18 decimals
    function _usdPerpsBalance() internal view returns (uint256 balance) {
        (bool success, bytes memory result) = WITHDRAWABLE_PRECOMPILE
            .staticcall(abi.encode(address(this)));
        require(success, "WithdrawablePrecompileFailed");

        // Result is in 6 decimals (perp), scale to 18
        uint256 rawBalance = abi.decode(result, (uint256));
        balance = rawBalance * 1e12; // 10^(18-6)
    }
}
