// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
/**
 * @title xYISKMiner is a stripped down version of Synthetix StakingRewards.sol, to reward xYISK to YiskUSD minters.
 * Differences from the original contract,
 * - Get `totalStaked` from totalSupply() in contract YiskUSD.
 * - Get `stakedOf(user)` from getBorrowedOf(user) in contract YiskUSD.
 * - When an address borrowed YiskUSD amount changes, call the refreshReward method to update rewards to be claimed.
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IYiskFinance.sol";
import "./interfaces/IxYISK.sol";

interface IYISK {
  function mint(address user, uint256 amount) external returns (bool);
}

interface Ihelper {
  function getCollateralRate(address user) external view returns (uint256);
}

interface IYiskFinanceFund {
  function refreshReward(address user) external;
}

interface IxYISKBoost {
  function getUserBoost(
    address user,
    uint256 userUpdatedAt,
    uint256 finishAt
  ) external view returns (uint256);

  function getUnlockTime(address user) external view returns (uint256 unlockTime);
}

contract xYISKMinter is Ownable {
  IYiskFinance public immutable yiskFinance;
  Ihelper public helper;
  IxYISKBoost public xYISKBoost;
  IYiskFinanceFund public yiskFinanceFund;
  IYISK public YISK;
  IxYISK public xYISK;

  // Portion of the rewards in Bips
  uint256 public portionRewardYISK = 2000;
  uint256 public portionRewardxYISK = 8000;
  // Duration of rewards to be paid out (in seconds)
  uint256 public duration = 2_592_000;
  // Timestamp of when the rewards finish
  uint256 public finishAt;
  // Minimum of last updated time and reward finish time
  uint256 public updatedAt;
  // Reward to be paid out per second
  uint256 public rewardRate;
  // Sum of (reward rate * dt * 1e18 / total supply)
  uint256 public rewardPerTokenStored;
  // User address => rewardPerTokenStored
  mapping(address => uint256) public userRewardPerTokenPaid;
  // User address => rewards to be claimed
  mapping(address => uint256) public rewards;
  mapping(address => uint256) public userUpdatedAt;
  uint256 public extraRate = 50 * 1e18;
  // Currently, the official rebase time for Lido is between 12PM to 13PM UTC.
  uint256 public lockdownPeriod = 12 hours;

  constructor(
    address _yiskFinance,
    address _helper,
    address _boost,
    address _fund,
    address _yisk,
    address _xYISK
  ) {
    yiskFinance = IYiskFinance(_yiskFinance);
    helper = Ihelper(_helper);
    xYISKBoost = IxYISKBoost(_boost);
    yiskFinanceFund = IYiskFinanceFund(_fund);
    YISK = IYISK(_yisk);
    xYISK = IxYISK(_xYISK);
  }

  function setyiskFinanceToken(address _yisk) external onlyOwner {
    YISK = IYISK(_yisk);
  }

  function setExtraRate(uint256 rate) external onlyOwner {
    extraRate = rate;
  }

  function setLockdownPeriod(uint256 _time) external onlyOwner {
    lockdownPeriod = _time;
  }

  function setBoost(address _boost) external onlyOwner {
    xYISKBoost = IxYISKBoost(_boost);
  }

  function setyiskFinanceFund(address _fund) external onlyOwner {
    yiskFinanceFund = IYiskFinanceFund(_fund);
  }

  function setRewardsDuration(uint256 _duration) external onlyOwner {
    require(finishAt < block.timestamp, "reward duration not finished");
    duration = _duration;
  }

  function totalStaked() internal view returns (uint256) {
    return yiskFinance.totalSupply();
  }

  function stakedOf(address user) public view returns (uint256) {
    return yiskFinance.getBorrowedOf(user);
  }

  modifier updateReward(address _account) {
    rewardPerTokenStored = rewardPerToken();
    updatedAt = lastTimeRewardApplicable();

    if (_account != address(0)) {
      rewards[_account] = earned(_account);
      userRewardPerTokenPaid[_account] = rewardPerTokenStored;
      userUpdatedAt[_account] = block.timestamp;
    }

    _;
  }

  function lastTimeRewardApplicable() public view returns (uint256) {
    return _min(finishAt, block.timestamp);
  }

  function rewardPerToken() public view returns (uint256) {
    if (totalStaked() == 0) {
      return rewardPerTokenStored;
    }

    return rewardPerTokenStored + (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) / totalStaked();
  }

  /**
   * @dev To limit the behavior of arbitrageurs who mint a large amount of YiskUSD after stETH rebase and before YiskUSD interest distribution to earn extra profit,
   * a 1-hour revert during stETH rebase is implemented to eliminate this issue.
   * If the user's collateral ratio is below safeCollateralRate, they are not subject to this restriction.
   */
  function pausedByLido(address _account) public view returns (bool) {
    uint256 collateralRate = helper.getCollateralRate(_account);
    return (block.timestamp - lockdownPeriod) % 1 days < 1 hours && collateralRate >= yiskFinance.safeCollateralRate();
  }

  /**
   * @notice Update user's claimable reward data and record the timestamp.
   */
  function refreshReward(address _account) external updateReward(_account) {
    if (pausedByLido(_account)) {
      revert("Minting and repaying functions of YiskUSD are temporarily disabled during stETH rebasing periods.");
    }
  }

  function getBoost(address _account) public view returns (uint256) {
    uint256 redemptionBoost;
    if (yiskFinance.isRedemptionProvider(_account)) {
      redemptionBoost = extraRate;
    }
    return 100 * 1e18 + redemptionBoost + xYISKBoost.getUserBoost(_account, userUpdatedAt[_account], finishAt);
  }

  function earned(address _account) public view returns (uint256) {
    return
      ((stakedOf(_account) * getBoost(_account) * (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e38) +
      rewards[_account];
  }

  function getReward() external updateReward(msg.sender) {
    require(
      block.timestamp >= xYISKBoost.getUnlockTime(msg.sender),
      "Your lock-in period has not ended. You can't claim your xYISK now."
    );
    uint256 reward = rewards[msg.sender];
    if (reward > 0) {
      rewards[msg.sender] = 0;
      yiskFinanceFund.refreshReward(msg.sender);
      uint256 yiskAmount = (portionRewardYISK * reward) / 10000;
      uint256 xYISKAmount = (portionRewardxYISK * reward) / 10000;
      YISK.mint(msg.sender, yiskAmount);
      xYISK.mintAndConvert(xYISKAmount, msg.sender);
    }
  }

  function notifyRewardAmount(uint256 amount) external onlyOwner updateReward(address(0)) {
    require(amount > 0, "amount = 0");
    if (block.timestamp >= finishAt) {
      rewardRate = amount / duration;
    } else {
      uint256 remainingRewards = (finishAt - block.timestamp) * rewardRate;
      rewardRate = (amount + remainingRewards) / duration;
    }

    require(rewardRate > 0, "reward rate = 0");

    finishAt = block.timestamp + duration;
    updatedAt = block.timestamp;
  }

  // in Bips, 100 means 1%
  function setPortionReward(uint256 _portionRewardYISK, uint256 _portionRewardxYISK) external onlyOwner {
    require(_portionRewardxYISK + _portionRewardxYISK == 10000, "portion reward total must be 10000");
    portionRewardYISK = _portionRewardYISK;
    portionRewardxYISK = _portionRewardxYISK;
  }

  function _min(uint256 x, uint256 y) private pure returns (uint256) {
    return x <= y ? x : y;
  }
}
