// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IYiskFinance {
  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function totalDepositedYLsk() external view returns (uint256);

  function safeCollateralRate() external view returns (uint256);

  function redemptionFee() external view returns (uint256);

  function keeperRate() external view returns (uint256);

  function depositedYLsk(address user) external view returns (uint256);

  function getBorrowedOf(address user) external view returns (uint256);

  function isRedemptionProvider(address user) external view returns (bool);

  function allowance(address owner, address spender) external view returns (uint256);

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) external returns (bool);

  function transferShares(address _recipient, uint256 _sharesAmount) external returns (uint256);

  function getSharesByMintedYiskUSD(uint256 _yiskUSDAmount) external view returns (uint256);

  function getMintedYiskUSDByShares(uint256 _sharesAmount) external view returns (uint256);
}
