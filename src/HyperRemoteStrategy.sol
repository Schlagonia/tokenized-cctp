// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseRemoteStrategy} from "./bases/BaseRemoteStrategy.sol";
import {BaseHyperCore} from "./bases/BaseHyperCore.sol";
import {BaseCCTP} from "./bases/BaseCCTP.sol";
import {CCTPHelpers} from "./libraries/CCTPHelpers.sol";

/// @notice Interface for CoreDepositWallet to deposit USDC from EVM to Core
interface ICoreDepositWallet {
    function deposit(uint256 amount, uint32 destinationDex) external;
}

/// @title HyperRemoteStrategy
/// @notice Remote strategy on HyperEVM that deposits USDC into HyperCore HLP vault
/// @dev Deposits and withdrawals are 2-step async processes due to Core<->EVM bridge latency
///
/// DEPOSIT FLOW (2 steps):
///   Step 1: pushFunds() - Bridge USDC from EVM to HyperCore spot (async)
///   Step 2: depositToVault() - Deposit from Core spot into HLP vault
///
/// WITHDRAW FLOW (2 steps):
///   Step 1: withdrawFromVault() - Withdraw from HLP vault to Core spot (subject to lockup)
///   Step 2: pullFunds() - Bridge from Core spot to EVM (async)
///
/// Note: HLP vault has a 4-day lockup. Use coreSpotBalance() to check withdrawable amount.
///
contract HyperRemoteStrategy is BaseRemoteStrategy, BaseHyperCore, BaseCCTP {
    using SafeERC20 for ERC20;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event DepositToVault(uint256 amount);
    event WithdrawFromVault(uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice HLP vault address on HyperCore
    address public constant HLP_VAULT =
        0xdfc24b077bc1425AD1DEA75bCB6f8158E10Df303;

    /// @notice Destination DEX for spot balance (type(uint32).max)
    uint32 internal constant SPOT_DEX = type(uint32).max;

    address internal constant USDC_LIQUIDITY_ADDRESS =
        0x6B9E773128f453f5c2C60935Ee2DE2CBc5390A24;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _asset,
        address _governance,
        address _tokenMessenger,
        address _messageTransmitter,
        address _remoteCounterpart
    )
        BaseRemoteStrategy(
            _asset,
            _governance,
            bytes32(uint256(CCTPHelpers.ETHEREUM_DOMAIN)), // Origin is Ethereum
            _remoteCounterpart
        )
        BaseCCTP(_asset, _tokenMessenger, _messageTransmitter)
    {
        // Approve token messenger for CCTP bridging back to origin
        asset.forceApprove(_tokenMessenger, type(uint256).max);
        // Approve CoreDepositWallet for depositing USDC to HyperCore
        asset.forceApprove(CORE_DEPOSIT_WALLET, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT INTERACTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit from HyperCore spot into HLP vault
    /// @dev Call after pushFunds() has settled (funds arrived in Core spot)
    ///      Transfers spot → perps → vault
    /// @param _amount Amount in 6 decimals to deposit to vault
    function depositToVault(uint256 _amount) external onlyKeepers {
        // Transfer from spot to perps if needed
        uint256 perpsBalance = corePerpsBalance();
        if (_amount > perpsBalance) {
            _spotToPerps(_amount - perpsBalance);
        }
        // Deposit from perps into HLP vault
        _vaultDeposit(_amount, HLP_VAULT);

        emit DepositToVault(_amount);
    }

    /// @notice Withdraw from HLP vault to HyperCore perps
    /// @dev Subject to HLP lockup period. Call pullFunds() after to bridge to EVM.
    /// @param _amount Amount in 6 decimals to withdraw
    function withdrawFromVault(uint256 _amount) external onlyKeepers {
        // Withdraw from HLP vault to perps
        // Note: HyperCore enforces lockup - only unlocked funds will arrive in perps
        _vaultWithdraw(_amount, HLP_VAULT);

        _perpsToSpot(_amount);

        emit WithdrawFromVault(_amount);
    }

    /*//////////////////////////////////////////////////////////////
                    BASEREMOTESTRATEGY IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate the value of assets deployed on HyperCore
    /// @dev Includes vault equity, spot balance, and perps balance
    /// @return Value in 6 decimals (EVM USDC decimals)
    function valueOfDeployedAssets() public view override returns (uint256) {
        // Query vault equity via precompile (returns 18 decimals)
        uint256 equity18 = _vaultEquity(HLP_VAULT);
        // Query spot balance via precompile (returns 18 decimals)
        uint256 spot18 = _usdSpotBalance();
        // Query perps balance via precompile (returns 18 decimals)
        uint256 perps18 = _usdPerpsBalance();
        // Convert from 18 decimals to 6 decimals
        return (equity18 + spot18 + perps18) / 1e12;
    }

    /// @notice Deploy USDC from EVM to HyperCore spot (async)
    /// @dev Step 1 of deposit flow. Call depositToVault() after funds arrive.
    /// @param _amount Amount in 6 decimals
    /// @return Amount deposited to Core
    function _pushFunds(uint256 _amount) internal override returns (uint256) {
        // Bridge USDC from EVM to HyperCore spot account
        ICoreDepositWallet(CORE_DEPOSIT_WALLET).deposit(_amount, SPOT_DEX);
        return _amount;
    }

    /// @notice Bridge USDC from HyperCore to EVM (async)
    /// @dev Step 2 of withdraw flow. Call withdrawFromVault() first.
    ///      Transfers perps → spot → EVM
    /// @param _amount Amount in 6 decimals
    /// @return Amount bridged to EVM
    function _pullFunds(uint256 _amount) internal override returns (uint256) {
        // Funds should already be in spot from withdrawFromVault()
        require(_amount <= coreSpotBalance(), "Insufficient spot balance");
        require(
            asset.balanceOf(USDC_LIQUIDITY_ADDRESS) >= _amount,
            "Insufficient liquidity"
        );

        // Initiate async bridge from Core spot to EVM
        _spotSend(USDC_SYSTEM_ADDRESS, USDC_SPOT_INDEX, _amount);
        return _amount;
    }

    /// @notice Bridge assets back to origin chain via CCTP
    /// @param amount Amount in 6 decimals
    /// @return Amount bridged
    function _bridgeAssets(uint256 amount) internal override returns (uint256) {
        // Standard CCTP depositForBurn back to Ethereum
        TOKEN_MESSENGER.depositForBurn(
            amount,
            uint32(uint256(REMOTE_ID)), // Ethereum domain (0)
            _addressToBytes32(REMOTE_COUNTERPART),
            address(asset),
            bytes32(0), // No destination caller restriction
            0, // No max fee for standard transfer
            FINALITY_THRESHOLD_FINALIZED
        );

        return amount;
    }

    /// @notice Send profit/loss message to origin chain via CCTP
    /// @param data Encoded message data (int256 profit/loss)
    function _bridgeMessage(bytes memory data) internal override {
        MESSAGE_TRANSMITTER.sendMessage(
            uint32(uint256(REMOTE_ID)), // Ethereum domain (0)
            _addressToBytes32(REMOTE_COUNTERPART),
            bytes32(0), // No destination caller restriction
            FINALITY_THRESHOLD_FINALIZED,
            data
        );
    }

    /// @notice Handle incoming CCTP message (required by IMessageHandlerV2)
    /// @dev Remote strategies don't process incoming messages in one-way architecture
    function handleReceiveFinalizedMessage(
        uint32, // _sourceDomain
        bytes32, // _sender
        uint32, // _finalityThresholdExecuted
        bytes calldata // _messageBody
    ) external virtual override returns (bool) {
        // Remote strategies don't process incoming messages
        // Only origin strategy receives messages from remote
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                        PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get HyperCore spot balance (USDC available to withdraw to EVM)
    /// @dev This is the amount that can be pulled via pullFunds()
    /// @return Balance in 6 decimals
    function coreSpotBalance() public view returns (uint256) {
        // Query via precompile (returns 18 decimals)
        uint256 balance18 = _usdSpotBalance();
        // Convert to 6 decimals
        return balance18 / 1e12;
    }

    /// @notice Get HyperCore perps balance (withdrawable USDC from perps)
    /// @dev This is the amount available after withdrawFromVault()
    /// @return Balance in 6 decimals
    function corePerpsBalance() public view returns (uint256) {
        // Query via precompile (returns 18 decimals)
        uint256 balance18 = _usdPerpsBalance();
        // Convert to 6 decimals
        return balance18 / 1e12;
    }

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Rescue tokens that are not the strategy asset
    /// @param _token Token to rescue
    /// @param _to Recipient address
    /// @param _amount Amount to rescue
    function rescue(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyGovernance {
        require(_token != address(asset), "Invalid token");
        ERC20(_token).safeTransfer(_to, _amount);
    }
}
