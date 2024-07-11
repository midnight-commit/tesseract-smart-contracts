// (c) 2023, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.18;

import {IERC20TokenSource} from "./IERC20TokenSource.sol";
import {TokenSource} from "./TokenSource.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {SafeERC20TransferFrom} from "@teleporter/SafeERC20TransferFrom.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.1/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts@4.8.1/token/ERC20/utils/SafeERC20.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/**
 * @dev Implementation of the {TokenSource} abstract contract.
 *
 * This contracts implements {TokenSource} and uses a specified ERC20 token as the currency.
 */
contract ERC20TokenSource is IERC20TokenSource, TokenSource {
    address public immutable erc20ContractAddress;

    constructor(
        address teleporterRegistryAddress,
        address teleporterManager,
        bytes32 destinationBlockchainID_,
        address nativeTokenDestinationAddress_,
        address erc20ContractAddress_
    )
        TokenSource(
            teleporterRegistryAddress,
            teleporterManager,
            destinationBlockchainID_,
            nativeTokenDestinationAddress_
        )
    {
        require(
            erc20ContractAddress_ != address(0), "ERC20TokenSource: zero ERC20 contract address"
        );
        erc20ContractAddress = erc20ContractAddress_;
    }

    /**
     * @dev See {IERC20TokenSource-transferToDestination}.
     */
    function transferToDestination(
        address recipient,
        uint256 totalAmount,
        uint256 feeAmount,
        address[] calldata allowedRelayerAddresses
    ) external nonReentrant {
        // The recipient cannot be the zero address.
        require(recipient != address(0), "ERC20TokenSource: zero recipient address");
        require(totalAmount > 0, "ERC20TokenSource: zero transfer amount");

        // Lock tokens in this contract. Supports "fee/burn on transfer" ERC20 token
        // implementations by only bridging the actual balance increase reflected by the call
        // to transferFrom.
        uint256 adjustedAmount =
            SafeERC20TransferFrom.safeTransferFrom(IERC20(erc20ContractAddress), totalAmount);

        // Ensure that the adjusted amount is greater than the fee to be paid.
        require(adjustedAmount > feeAmount, "ERC20TokenSource: insufficient adjusted amount");

        uint256 transferAmount = adjustedAmount - feeAmount;
        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: destinationBlockchainID,
                destinationAddress: nativeTokenDestinationAddress,
                feeInfo: TeleporterFeeInfo({feeTokenAddress: erc20ContractAddress, amount: feeAmount}),
                requiredGasLimit: MINT_NATIVE_TOKENS_REQUIRED_GAS,
                allowedRelayerAddresses: allowedRelayerAddresses,
                message: abi.encode(recipient, transferAmount)
            })
        );

        emit TransferToDestination({
            sender: msg.sender,
            recipient: recipient,
            amount: transferAmount,
            teleporterMessageID: messageID
        });
    }

    /**
     * @dev See {TokenSource-_unlockTokens}
     */
    function _unlockTokens(address recipient, uint256 amount) internal override {
        require(recipient != address(0), "ERC20TokenSource: zero recipient address");

        // Transfer to recipient
        emit UnlockTokens(recipient, amount);
        SafeERC20.safeTransfer(IERC20(erc20ContractAddress), recipient, amount);
    }
}
