// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
/**
 * @title YiskFinanceFund is a derivative version of Synthetix StakingRewards.sol, distributing Protocol revenue to xYISK stakers.
 * Converting xYISK to YISK.
 * Differences from the original contract,
 * - Get `totalStaked` from totalSupply() in contract xYISK.
 * - Get `stakedOf(user)` from balanceOf(user) in contract xYISK.
 * - When an address xYISK balance changes, call the refreshReward method to update rewards to be claimed.
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IYiskFinance.sol";
import "./interfaces/IxYISK.sol";

contract YiskFund is Ownable {
  IYiskFinance public yiskFinance;
  IxYISK public xYISK;

  // Sum of (reward rate * dt * 1e18 / total supply)
  uint256 public rewardPerTokenStored;
  // User address => rewardPerTokenStored
  mapping(address => uint256) public userRewardPerTokenPaid;
  // User address => rewards to be claimed
  mapping(address => uint256) public rewards;
  mapping(address => uint256) public lastWithdrawTime;

  address public protocolFeeReceiver;
  // in Bips, 100 means 1%
  uint256 public protocolFee;

  constructor(
    address _yiskFinance,
    address _protocolFeeReceiver,
    uint256 _protocolFee
  ) {
    yiskFinance = IYiskFinance(_yiskFinance);
    protocolFeeReceiver = _protocolFeeReceiver;
    protocolFee = _protocolFee;
  }

  function setYiskFinance(address _yiskFinance) external onlyOwner {
    yiskFinance = IYiskFinance(_yiskFinance);
  }

  function setProtocolDetails(address _protocolFeeReceiver, uint256 _protocolFee) external onlyOwner {
    protocolFeeReceiver = _protocolFeeReceiver;
    protocolFee = _protocolFee;
  }

  function setTokenAddress(address _xYISK) external onlyOwner {
    xYISK = IxYISK(_xYISK);
  }

  // Total staked
  function totalStaked() internal view returns (uint256) {
  return xYISK.totalSupply() - xYISK.balanceOf(address(xYISK));
  }

  // User address => xYISK balance
  function stakedOf(address staker) internal view returns (uint256) {
    return xYISK.balanceOf(staker);
  }

  function earned(address _account) public view returns (uint256) {
    return
      ((stakedOf(_account) * (rewardPerTokenStored - userRewardPerTokenPaid[_account])) / 1e18) + rewards[_account];
  }

  function getClaimAbleYiskUSD(address user) external view returns (uint256 amount) {
    amount = yiskFinance.getMintedYiskUSDByShares(earned(user));
  }

  /**
   * @dev Call this function when deposit or withdraw ETH on YiskFinance and update the status of corresponding user.
   */
  modifier updateReward(address account) {
    rewards[account] = earned(account);
    userRewardPerTokenPaid[account] = rewardPerTokenStored;
    _;
  }

  function refreshReward(address _account) external updateReward(_account) {}

  function getReward() external updateReward(msg.sender) {
    uint256 reward = rewards[msg.sender];
    if (reward > 0) {
      rewards[msg.sender] = 0;
      uint256 userRewardAmount = ((10000 - protocolFee) * reward) / 10000;
      uint256 deductedFeeAmount = (protocolFee * reward) / 10000;
      yiskFinance.transferShares(msg.sender, userRewardAmount);
      yiskFinance.transferShares(protocolFeeReceiver, deductedFeeAmount);
    }
  }

  /**
   * @dev The amount of YiskUSD acquiered from the sender is euitably distributed to YISK stakers.
   * Calculate share by amount, and calculate the shares could claim by per unit of staked ETH.
   * Add into rewardPerTokenStored.
   */
  function notifyRewardAmount(uint256 amount) external {
    require(msg.sender == address(yiskFinance));
    if (totalStaked() == 0) return;
    require(amount > 0, "amount = 0");
    uint256 share = yiskFinance.getSharesByMintedYiskUSD(amount);
    rewardPerTokenStored = rewardPerTokenStored + (share * 1e18) / totalStaked();
  }
}
