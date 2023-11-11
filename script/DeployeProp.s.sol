// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {EProp} from "../src/eProp.sol";
import {MockV3Aggregator} from "../test/Mocks/MockV3Aggregator.sol";

contract DeployEProp is Script {
    string private imageUri = "https://ipfs.io/ipfs/QmVQfqv5YNXL73ypG125BBsooWRiVubF5nm2g9tRtPtyx8";
    address private ethPriceFeed;

    function run() external returns (EProp) {
        if (block.chainid == 11155111) {
            ethPriceFeed = address(0);
        } else {
            uint8 DECIMALS = 8;
            int256 ETH_USD_PRICE = 2000e8;
            vm.startBroadcast();
            MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
            vm.stopBroadcast();
            ethPriceFeed = address(ethUsdPriceFeed);
        }

        vm.startBroadcast();
        EProp eprop = new EProp(imageUri,ethPriceFeed);
        vm.stopBroadcast();
        return eprop;
    }
}
