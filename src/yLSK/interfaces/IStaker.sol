// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IStaker {
  function lockAmount(address, uint256, uint256) external;

  function unlock(uint256) external;
}
