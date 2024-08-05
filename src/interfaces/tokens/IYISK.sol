// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYISK is IERC20 {
  function mint(address user, uint256 amount) external;

  function burn(uint256 amount) external;
}
