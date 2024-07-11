// (c) 2024, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity 0.8.18;

import {IERC20} from "@openzeppelin/contracts@4.8.1/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts@4.8.1/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev Provides a wrapper used for calling an ERC20 transferFrom method to receive tokens to a contract
 * from a specified sender. Differs from the "SafeERC20TransferFrom" implementation found here
 * https://github.com/ava-labs/teleporter/blob/main/contracts/src/Teleporter/SafeERC20TransferFrom.sol in that
 * it supports passing arbitrary sender address values, allowing its use in ERC-2771 compliant meta-transactions.
 *
 * Checks the balance of the contract using the library before and after the call to safeTransferFrom, and
 * returns balance increase. Designed for safely handling ERC20 "fee on transfer" and "burn on transfer"
 * implementations.
 *
 * Note: Contracts that use this library must ensure that users cannot pass arbitrary addresses as
 * the {from} address for the {transferFrom} call. Proper authorization (such as msg.sender) must
 * be required to ensure no one can improperly transfer tokens from any address.
 *
 * Note: A reentrancy guard must always be used when calling token.safeTransferFrom in order to
 * prevent against possible "before-after" pattern vulnerabilities.
 *
 * @custom:security-contact https://github.com/ava-labs/avalanche-interchain-token-transfer/blob/main/SECURITY.md
 */
library SafeERC20TransferFrom {
    using SafeERC20 for IERC20;

    /**
     * @dev Checks the balance of the contract before and after the call to safeTransferFrom, and returns the balance
     * increase. Designed for safely handling ERC20 "fee on transfer" and "burn on transfer" implementations.
     */
    // solhint-disable private-vars-leading-underscore
    function safeTransferFrom(
        IERC20 erc20,
        address from,
        uint256 amount
    ) internal returns (uint256) {
        uint256 balanceBefore = erc20.balanceOf(address(this));
        erc20.safeTransferFrom(from, address(this), amount);
        uint256 balanceAfter = erc20.balanceOf(address(this));

        require(balanceAfter > balanceBefore, "SafeERC20TransferFrom: balance not increased");

        return balanceAfter - balanceBefore;
    }
    // solhint-enable private-vars-leading-underscore
}
