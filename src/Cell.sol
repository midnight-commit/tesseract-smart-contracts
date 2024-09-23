// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ICell, CellPayload, Instructions, Hop, BridgePath, Action} from "./interfaces/ICell.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20TokenTransferrer} from "@avalanche-interchain-token-transfer/interfaces/IERC20TokenTransferrer.sol";
import {IERC20SendAndCallReceiver} from "@avalanche-interchain-token-transfer/interfaces/IERC20SendAndCallReceiver.sol";
import {
    SendAndCallInput, SendTokensInput
} from "@avalanche-interchain-token-transfer/interfaces/ITokenTransferrer.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {INativeTokenTransferrer} from "@avalanche-interchain-token-transfer/interfaces/INativeTokenTransferrer.sol";
import {INativeSendAndCallReceiver} from
    "@avalanche-interchain-token-transfer/interfaces/INativeSendAndCallReceiver.sol";
import {IWrappedNativeToken} from "@avalanche-interchain-token-transfer/interfaces/IWrappedNativeToken.sol";

/**
 * @title Cell
 * @dev Abstract contract for cross-chain token swaps and transfers
 */
abstract contract Cell is ICell, IERC20SendAndCallReceiver, INativeSendAndCallReceiver {
    using SafeERC20 for IERC20;
    using Address for address payable;

    IWrappedNativeToken wrappedNativeToken;

    constructor(address wrappedNativeTokenAddress) {
        wrappedNativeToken = IWrappedNativeToken(wrappedNativeTokenAddress);
    }

    receive() external payable {
        require(msg.sender == address(wrappedNativeToken), "Not WAVAX");
    }

    /**
     * @notice Initiates a cross-chain swap
     * @param token The address of the token to be swapped/bridged
     * @param amount The amount of tokens to be swapped/bridged
     * @param instructions The instructions for the cross-chain swap
     */
    function initiate(address token, uint256 amount, Instructions calldata instructions)
        external
        override
        nonReentrant
    {
        if (amount == 0) {
            revert InvalidAmount();
        }
        emit Initiated(msg.sender, token, amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        CellPayload memory payload = CellPayload({instructions: instructions, hop: 0});
        _route(token, amount, payload);
    }

    /**
     * @notice Receives tokens from another chain and processes them
     * @param sourceBlockchainID The ID of the source blockchain
     * @param originTokenTransferrerAddress The address of the token transferrer on the origin chain
     * @param originSenderAddress The address of the sender on the origin chain
     * @param token The address of the received token
     * @param amount The amount of tokens received
     * @param payload The payload containing instructions for further processing
     */
    function receiveTokens(
        bytes32 sourceBlockchainID,
        address originTokenTransferrerAddress,
        address originSenderAddress,
        address token,
        uint256 amount,
        bytes calldata payload
    ) external override nonReentrant {
        emit CellReceivedTokens(sourceBlockchainID, originTokenTransferrerAddress, originSenderAddress, token, amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _receiveTokens(token, amount, payload);
    }

    function receiveTokens(
        bytes32 sourceBlockchainID,
        address originTokenTransferrerAddress,
        address originSenderAddress,
        bytes calldata payload
    ) external payable override {
        emit CellReceivedNativeTokens(sourceBlockchainID, originTokenTransferrerAddress, originSenderAddress);
        _receiveTokens(address(0), msg.value, payload);
    }

    function _receiveTokens(address token, uint256 amount, bytes calldata payload) internal {
        CellPayload memory cellPayload = abi.decode(payload, (CellPayload));
        cellPayload.hop++;
        _route(token, amount, cellPayload);
    }

    /**
     * @notice Calculates the route for a token swap
     * @param amountIn The amount of input tokens
     * @param tokenIn The address of the input token
     * @param tokenOut The address of the output token
     * @param extras Additional data for routing
     * @return trade The encoded trade data
     * @return gasEstimate The estimated gas cost for the trade
     */
    function route(uint256 amountIn, address tokenIn, address tokenOut, bytes calldata extras)
        external
        view
        virtual
        returns (bytes memory trade, uint256 gasEstimate);

    /**
     * @notice Performs a token swap
     * @dev IMPORTANT: This function should use proper exception handling to manage errors.
     * Use try/catch blocks to handle exceptions that may occur during the swap process.
     * Indicate success or failure through the success return parameter.
     * If an exception occurs or the swap fails for any reason:
     * 1. Catch the exception and handle it gracefully.
     * 2. Set success to false.
     * 3. Provide appropriate values for tokenOut (e.g., address(0)) and amountOut (e.g., 0).
     * 4. Optionally, emit an event with error details for off-chain tracking.
     * This approach allows the calling function to handle failed swaps gracefully,
     * potentially enabling rollbacks or other recovery mechanisms.
     * @param token The address of the input token
     * @param amount The amount of input tokens
     * @param payload The payload containing swap instructions
     * @return success Whether the swap was successful (true) or failed (false)
     * @return tokenOut The address of the output token (or address(0) if swap failed)
     * @return amountOut The amount of output tokens (or 0 if swap failed)
     */
    function _swap(address token, uint256 amount, CellPayload memory payload)
        internal
        virtual
        returns (bool success, address tokenOut, uint256 amountOut);

    /**
     * @notice Routes the tokens based on the provided payload
     * @param token The address of the token to route
     * @param amount The amount of tokens to route
     * @param payload The payload containing routing instructions
     */
    function _route(address token, uint256 amount, CellPayload memory payload) internal {
        Hop memory hop = payload.instructions.hops[payload.hop];

        // Wrap native input in case of a swap and/or if the next bridge isn't native.
        if (
            token == address(0)
                && (
                    !hop.bridgePath.sourceBridgeIsNative || hop.action == Action.SwapAndTransfer
                        || hop.action == Action.SwapAndHop
                )
        ) {
            wrappedNativeToken.deposit{value: amount}();
            token = address(wrappedNativeToken);
        }

        if (hop.action == Action.SwapAndTransfer || hop.action == Action.SwapAndHop) {
            (bool success, address tokenOut, uint256 amountOut) = _trySwap(token, amount, payload);
            if (!success) return;
            token = tokenOut;
            amount = amountOut;
        }

        if (
            token == address(wrappedNativeToken)
                && (
                    (hop.action == Action.SwapAndTransfer && payload.instructions.payableReceiver)
                        || hop.bridgePath.sourceBridgeIsNative
                )
        ) {
            wrappedNativeToken.withdraw(amount);
        }

        if (hop.action == Action.SwapAndTransfer) {
            _transfer(token, amount, payload);
        } else if (
            hop.action == Action.Hop
                || (hop.action == Action.SwapAndHop && payload.hop == payload.instructions.hops.length - 1)
        ) {
            _send(token, amount, payload);
        } else {
            _sendAndCall(token, amount, payload);
        }
    }

    /**
     * @notice Attempts to perform a swap and handles failures
     * @param token The address of the input token
     * @param amount The amount of input tokens
     * @param payload The payload containing swap instructions
     * @return success Whether the swap was successful
     * @return tokenOut The address of the output token
     * @return amountOut The amount of output tokens
     */
    function _trySwap(address token, uint256 amount, CellPayload memory payload)
        internal
        returns (bool success, address tokenOut, uint256 amountOut)
    {
        (success, tokenOut, amountOut) = _swap(token, amount, payload);
        if (success) return (success, tokenOut, amountOut);

        if (payload.hop == 1) {
            require(payload.instructions.rollbackTeleporterFee < amount, "Invalid rollback fee");
            if (
                token == address(wrappedNativeToken)
                    && payload.instructions.hops[0].bridgePath.destinationBridgeIsNative
            ) {
                wrappedNativeToken.withdraw(amount);
            }
            _rollback(token, amount, payload);
            return (false, address(0), 0);
        } else {
            revert SwapFailed();
        }
    }

    function _transfer(address token, uint256 amount, CellPayload memory payload) internal {
        if (token == address(wrappedNativeToken) && payload.instructions.payableReceiver) {
            payable(payload.instructions.receiver).sendValue(amount);
        } else {
            IERC20(token).safeTransfer(payload.instructions.receiver, amount);
        }
    }

    /**
     * @notice Sends tokens to another chain and calls a contract
     * @param token The address of the token to send
     * @param amount The amount of tokens to send
     * @param payload The payload containing transfer instructions
     */
    function _sendAndCall(address token, uint256 amount, CellPayload memory payload) internal {
        Hop memory hop = payload.instructions.hops[payload.hop];
        SendAndCallInput memory input = SendAndCallInput({
            destinationBlockchainID: hop.bridgePath.destinationBlockchainId,
            destinationTokenTransferrerAddress: hop.bridgePath.bridgeDestinationChain,
            recipientContract: hop.bridgePath.cellDestinationChain,
            recipientPayload: abi.encode(payload),
            requiredGasLimit: hop.requiredGasLimit,
            recipientGasLimit: hop.recipientGasLimit,
            multiHopFallback: hop.bridgePath.multihop ? payload.instructions.receiver : address(0),
            fallbackRecipient: payload.instructions.receiver,
            primaryFeeTokenAddress: token,
            primaryFee: hop.bridgePath.teleporterFee,
            secondaryFee: hop.bridgePath.multihop ? hop.bridgePath.secondaryTeleporterFee : 0
        });
        if (hop.bridgePath.sourceBridgeIsNative) {
            INativeTokenTransferrer(hop.bridgePath.bridgeSourceChain).sendAndCall{value: amount}(input);
        } else {
            IERC20(token).forceApprove(hop.bridgePath.bridgeSourceChain, amount);
            IERC20TokenTransferrer(hop.bridgePath.bridgeSourceChain).sendAndCall(
                input, amount - hop.bridgePath.teleporterFee
            );
        }
    }

    /**
     * @notice Sends tokens to another chain
     * @param token The address of the token to send
     * @param amount The amount of tokens to send
     * @param payload The payload containing transfer instructions
     */
    function _send(address token, uint256 amount, CellPayload memory payload) internal {
        Hop memory hop = payload.instructions.hops[payload.hop];
        SendTokensInput memory input = SendTokensInput({
            destinationBlockchainID: hop.bridgePath.destinationBlockchainId,
            destinationTokenTransferrerAddress: hop.bridgePath.bridgeDestinationChain,
            recipient: payload.instructions.receiver,
            primaryFeeTokenAddress: token,
            primaryFee: hop.bridgePath.teleporterFee,
            secondaryFee: hop.bridgePath.secondaryTeleporterFee,
            requiredGasLimit: hop.gasLimit + GAS_LIMIT_BRIDGE_HOP,
            multiHopFallback: hop.bridgePath.multihop ? payload.instructions.receiver : address(0)
        });
        if (hop.bridgePath.sourceBridgeIsNative) {
            INativeTokenTransferrer(hop.bridgePath.bridgeSourceChain).send{value: amount}(input);
        } else {
            IERC20(token).forceApprove(hop.bridgePath.bridgeSourceChain, amount);
            IERC20TokenTransferrer(hop.bridgePath.bridgeSourceChain).send(input, amount - hop.bridgePath.teleporterFee);
        }
    }

    function _rollback(address token, uint256 amount, CellPayload memory payload) internal {
        SendTokensInput memory input = SendTokensInput({
            destinationBlockchainID: payload.instructions.sourceBlockchainId,
            destinationTokenTransferrerAddress: payload.instructions.hops[0].bridgePath.bridgeSourceChain,
            recipient: payload.instructions.receiver,
            primaryFeeTokenAddress: token,
            primaryFee: payload.instructions.rollbackTeleporterFee,
            secondaryFee: 0,
            requiredGasLimit: GAS_LIMIT_BRIDGE_HOP,
            multiHopFallback: address(0)
        });
        if (payload.instructions.hops[0].bridgePath.destinationBridgeIsNative) {
            INativeTokenTransferrer(payload.instructions.hops[0].bridgePath.bridgeDestinationChain).send{value: amount}(
                input
            );
        } else {
            IERC20(token).forceApprove(payload.instructions.hops[0].bridgePath.bridgeDestinationChain, amount);
            IERC20TokenTransferrer(payload.instructions.hops[0].bridgePath.bridgeDestinationChain).send(
                input, amount - payload.instructions.rollbackTeleporterFee
            );
        }
        emit Rollback(payload.instructions.receiver, token, amount - payload.instructions.rollbackTeleporterFee);
    }
}
