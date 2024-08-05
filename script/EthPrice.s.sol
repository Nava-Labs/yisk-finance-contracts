// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17;

import { BaseScript } from "./Base.s.sol";

interface IYiskFinance {
  function setYLSKPrice(uint256) external;
}

interface IYiskHelper {
  function setYLSKPrice(uint256) external;
}

contract PriceChange is BaseScript {
  function run() public broadcaster {
    IYiskFinance yiskFinance = IYiskFinance(0x6A8e29fcaDad07BB8dc6C80D3e61200625d14051);
    IYiskHelper yiskHelper = IYiskHelper(0x0cD895fbE317B8A5FDa5D53025A1bAD023691f66);
    yiskFinance.setYLSKPrice(1750 ether);
    yiskHelper.setYLSKPrice(175000000000);
  }
}
