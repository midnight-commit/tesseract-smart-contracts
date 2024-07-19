// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Script.sol";
import "./../src/HopOnlyCell.sol";

contract DeployCellTes is Script {
    address public constant TELEPORTER_REGISTRY = 0xfF344ea9174690B240eE1bb8533746dC7290F305;
    address public constant PRIMARY_FEE_TOKEN = 0xB8C177f201B9Fea640cD667c6327aBb756A1D5Ea;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new HopOnlyCell(TELEPORTER_REGISTRY, PRIMARY_FEE_TOKEN);

        vm.stopBroadcast();
    }
}

// forge script --chain 732 script/DeployCellTes.s.sol:DeployCellTes --rpc-url $TESCHAIN_RPC_URL --broadcast -vvvv