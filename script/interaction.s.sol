// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {EProp} from "../src/eProp.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract MintNft is Script {
    function run() external {
        //install DevOpsTools first with [forge install Cyfrin/foundry-devops --no-commit]
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("EProp", block.chainid);
        mintNftOnContract(mostRecentlyDeployed);
    }

    function mintNftOnContract(address contractaddress) public {
        address yourAddress = 0xd7c7D282d2DFe653382997610Fe67e9695d60B58;

        console.log("minting token for: ", yourAddress);
        vm.startBroadcast();
        EProp(contractaddress).mintProp(yourAddress, 65, 45, 1, 1, 0);
        vm.stopBroadcast();
    }
}
