// (c) 2023, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.18;

import {Address} from "@openzeppelin/contracts@4.8.1/utils/Address.sol";
import {INativeTokenSource} from "./INativeTokenSource.sol";
import {TokenSource} from "./TokenSource.sol";
import {TeleporterFeeInfo, TeleporterMessageInput} from "@teleporter/ITeleporterMessenger.sol";
import {SafeERC20TransferFrom} from "@teleporter/SafeERC20TransferFrom.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.1/token/ERC20/IERC20.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/**
 * @dev Implementation of the {TokenSource} abstract contract.
 *
 * This contracts implements {TokenSource} and uses native tokens as the currency.
 */
contract NativeTokenSource is INativeTokenSource, TokenSource {
    constructor(
        address teleporterRegistryAddress,
        address teleporterManager,
        bytes32 destinationBlockchainID_,
        address nativeTokenDestinationAddress_
    )
        TokenSource(
            teleporterRegistryAddress,
            teleporterManager,
            destinationBlockchainID_,
            nativeTokenDestinationAddress_
        )
    {}

    /**
     * @dev See {INativeTokenSource-transferToDestination}.
     */
    function transferToDestination(
        address recipient,
        TeleporterFeeInfo calldata feeInfo,
        address[] calldata allowedRelayerAddresses
    ) external payable nonReentrant {
        // The recipient cannot be the zero address.
        require(recipient != address(0), "NativeTokenSource: zero recipient address");
        uint256 value = msg.value;
        require(value > 0, "NativeTokenSource: zero transfer value");

        // Lock tokens in this bridge instance. Supports "fee/burn on transfer" ERC20 token
        // implementations by only bridging the actual balance increase reflected by the call
        // to transferFrom.
        uint256 adjustedFeeAmount;
        if (feeInfo.amount > 0) {
            adjustedFeeAmount = SafeERC20TransferFrom.safeTransferFrom(
                IERC20(feeInfo.feeTokenAddress), feeInfo.amount
            );
        }

        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: destinationBlockchainID,
                destinationAddress: nativeTokenDestinationAddress,
                feeInfo: feeInfo,
                requiredGasLimit: MINT_NATIVE_TOKENS_REQUIRED_GAS,
                allowedRelayerAddresses: allowedRelayerAddresses,
                message: abi.encode(recipient, value)
            })
        );

        emit TransferToDestination({
            sender: msg.sender,
            recipient: recipient,
            teleporterMessageID: messageID,
            amount: value
        });
    }

    /**
     * @dev See {TokenSource-_unlockTokens}
     */
    function _unlockTokens(address recipient, uint256 amount) internal override {
        require(recipient != address(0), "NativeTokenSource: zero recipient address");
        require(address(this).balance >= amount, "NativeTokenSource: insufficient collateral");

        // Transfer to recipient
        emit UnlockTokens(recipient, amount);
        Address.sendValue(payable(recipient), amount);
    }
}
