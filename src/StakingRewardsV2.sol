// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "./interfaces/IERC20.sol";

interface IxYISKBoost {
  function getUserBoost(
    address user,
    uint256 userUpdatedAt,
    uint256 finishAt
  ) external view returns (uint256);

  function getUnlockTime(address user) external view returns (uint256 unlockTime);
}

interface IYiskFinanceFund {
  function refreshReward(address user) external;
}

interface IYISK {
  function mint(address user, uint256 amount) external returns (uint256);
}

interface IxYISK {
  function mintAndConvert(uint256 amount, address to) external;
}

contract StakingRewardsV2 {
  // Immutable variables for staking and rewards tokens
  IERC20 public immutable stakingToken;
  IYISK public immutable yisk;
  IxYISK public immutable xYISK;
  IxYISKBoost public xYISKBoost;
  IYiskFinanceFund public yiskFinanceFund;

  address public owner;

  // Portion of the rewards in Bips
  uint256 public portionRewardYISK = 2000;
  uint256 public portionRewardXYISK = 8000;
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

  // Total staked
  uint256 public totalSupply;
  // User address => staked amount
  mapping(address => uint256) public balanceOf;

  constructor(
    address _stakingToken,
    address _yisk,
    address _xYISK,
    address _boost,
    address _fund
  ) {
    owner = msg.sender;
    stakingToken = IERC20(_stakingToken);
    yisk = IYISK(_yisk);
    xYISK = IxYISK(_xYISK);
    xYISKBoost = IxYISKBoost(_boost);
    yiskFinanceFund = IYiskFinanceFund(_fund);
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "not authorized");
    _;
  }

  // Update user's claimable reward data and record the timestamp.
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

  // Returns the last time the reward was applicable
  function lastTimeRewardApplicable() public view returns (uint256) {
    return _min(finishAt, block.timestamp);
  }

  // Calculates and returns the reward per token
  function rewardPerToken() public view returns (uint256) {
    if (totalSupply == 0) {
      return rewardPerTokenStored;
    }

    return rewardPerTokenStored + (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) / totalSupply;
  }

  // Allows users to stake a specified amount of tokens
  function stake(uint256 _amount) external updateReward(msg.sender) {
    require(_amount > 0, "amount = 0");
    stakingToken.transferFrom(msg.sender, address(this), _amount);
    balanceOf[msg.sender] += _amount;
    totalSupply += _amount;
  }

  // Allows users to withdraw a specified amount of staked tokens
  function withdraw(uint256 _amount) external updateReward(msg.sender) {
    require(_amount > 0, "amount = 0");
    balanceOf[msg.sender] -= _amount;
    totalSupply -= _amount;
    stakingToken.transfer(msg.sender, _amount);
  }

  function getBoost(address _account) public view returns (uint256) {
    return 100 * 1e18 + xYISKBoost.getUserBoost(_account, userUpdatedAt[_account], finishAt);
  }

  // Calculates and returns the earned rewards for a user
  function earned(address _account) public view returns (uint256) {
    return
      ((balanceOf[_account] * getBoost(_account) * (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e38) +
      rewards[_account];
  }

  // Allows users to claim their earned rewards
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
      uint256 xyiskAmount = (portionRewardXYISK * reward) / 10000;
      yisk.mint(msg.sender, yiskAmount);
      xYISK.mintAndConvert(xyiskAmount, msg.sender);
    }
  }

  // Allows the owner to set the rewards duration
  function setRewardsDuration(uint256 _duration) external onlyOwner {
    require(finishAt < block.timestamp, "reward duration not finished");
    duration = _duration;
  }

  // Allows the owner to set the boost contract address
  function setBoost(address _boost) external onlyOwner {
    xYISKBoost = IxYISKBoost(_boost);
  }

  // Allows the owner to set the mining rewards.
  function notifyRewardAmount(uint256 _amount) external onlyOwner updateReward(address(0)) {
    if (block.timestamp >= finishAt) {
      rewardRate = _amount / duration;
    } else {
      uint256 remainingRewards = (finishAt - block.timestamp) * rewardRate;
      rewardRate = (_amount + remainingRewards) / duration;
    }

    require(rewardRate > 0, "reward rate = 0");

    finishAt = block.timestamp + duration;
    updatedAt = block.timestamp;
  }

  // in Bips, 100 means 1%
  function setPortionReward(uint256 _portionRewardYISK, uint256 _portionRewardXYISK) external onlyOwner {
    require(_portionRewardXYISK + _portionRewardXYISK == 10000, "portion reward total must be 10000");
    portionRewardYISK = _portionRewardYISK;
    portionRewardXYISK = _portionRewardXYISK;
  }

  function _min(uint256 x, uint256 y) private pure returns (uint256) {
    return x <= y ? x : y;
  }
}
