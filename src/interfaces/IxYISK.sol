// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IxYISK {
  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function convertTo(uint256 amount, address to) external returns (bool);

  function mintAndConvert(uint256 amount, address to) external;
}
