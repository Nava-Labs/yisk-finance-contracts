// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/IYiskFinance.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface IStakingRewards {
  function rewardRate() external view returns (uint256);
}

contract YiskHelper {
  IYiskFinance public immutable yiskFinance;
  AggregatorV3Interface internal priceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

  // NOTE: currenly hardoced to $1, this is just POC, 
  // fetch using Oracle, Trellor in PriceFeed or using Price Aggregator later on.
  uint256 public hardcodedYLSKPrice = 10**8;

  constructor(address _yiskFinance) {
    yiskFinance = IYiskFinance(_yiskFinance);
  }

  // function getYLSKPrice() public view returns (uint256) {
  //   // prettier-ignore
  //   (
  //           /* uint80 roundID */,
  //           int price,
  //           /*uint startedAt*/,
  //           /*uint timeStamp*/,
  //           /*uint80 answeredInRound*/
  //       ) = priceFeed.latestRoundData();
  //   return uint256(price);
  // }
  
  // in decimals 8
  // NOTE: Hardcoded for demo testing
  function getYLSKPrice() public view returns (uint256) {
    return hardcodedYLSKPrice;
  }

  /**
  * @dev NOTE: TESTING function, change yLSK price
  */
  function setYLSKPrice(uint256 priceInDecimals8) public {
      hardcodedYLSKPrice = priceInDecimals8;
  }

  function getCollateralRate(address user) public view returns (uint256) {
    if (yiskFinance.getBorrowedOf(user) == 0) return 1e22;
    return (yiskFinance.depositedYLsk(user) * getYLSKPrice() * 1e12) / yiskFinance.getBorrowedOf(user);
  }

  function getOverallCollateralRate() public view returns (uint256) {
    return (yiskFinance.totalDepositedYLsk() * getYLSKPrice() * 1e12) / yiskFinance.totalSupply();
  }

  function getLiquidateableAmount(address user) external view returns (uint256 yLskAmount, uint256 yiskUSDAmount) {
    if (getCollateralRate(user) > 150 * 1e18) return (0, 0);
    if (getCollateralRate(user) >= 125 * 1e18 || getOverallCollateralRate() >= 150 * 1e18) {
      yLskAmount = yiskFinance.depositedYLsk(user) / 2;
      yiskUSDAmount = (yLskAmount * getYLSKPrice()) / 1e8;
    } else {
      yLskAmount = yiskFinance.depositedYLsk(user);
      yiskUSDAmount = (yLskAmount * getYLSKPrice()) / 1e8;
      if (getCollateralRate(user) >= 1e20) {
        yiskUSDAmount = (yiskUSDAmount * 1e20) / getCollateralRate(user);
      }
    }
  }

  function getRedeemableAmount(address user) external view returns (uint256) {
    if (!yiskFinance.isRedemptionProvider(user)) return 0;
    return yiskFinance.getBorrowedOf(user);
  }

  function getRedeemableAmounts(address[] calldata users) external view returns (uint256[] memory amounts) {
    amounts = new uint256[](users.length);
    for (uint256 i = 0; i < users.length; i++) {
      if (!yiskFinance.isRedemptionProvider(users[i])) amounts[i] = 0;
      amounts[i] = yiskFinance.getBorrowedOf(users[i]);
    }
  }

  function getLiquidateFund(address user) external view returns (uint256 yiskUSDAmount) {
    uint256 appro = yiskFinance.allowance(user, address(yiskFinance));
    if (appro == 0) return 0;
    uint256 bal = yiskFinance.balanceOf(user);
    yiskUSDAmount = appro > bal ? bal : appro;
  }

  function getWithdrawableAmount(address user) external view returns (uint256) {
    if (yiskFinance.getBorrowedOf(user) == 0) return yiskFinance.depositedYLsk(user);
    if (getCollateralRate(user) <= 160 * 1e18) return 0;
    return (yiskFinance.depositedYLsk(user) * (getCollateralRate(user) - 160 * 1e18)) / getCollateralRate(user);
  }

  function getYiskUSDMintableAmount(address user) external view returns (uint256 yiskUSDAmount) {
    if (getCollateralRate(user) <= 160 * 1e18) return 0;
    return (yiskFinance.depositedYLsk(user) * getYLSKPrice()) / 1e6 / 160 - yiskFinance.getBorrowedOf(user);
  }

  function getStakingPoolAPR(
    address poolAddress,
    address YISK,
    address lpToken
  ) external view returns (uint256 apr) {
    uint256 pool_lp_stake = IERC20(poolAddress).totalSupply();
    uint256 rewardRate = IStakingRewards(poolAddress).rewardRate();
    uint256 lp_YISK_amount = IERC20(YISK).balanceOf(lpToken);
    uint256 lp_total_supply = IERC20(lpToken).totalSupply();
    apr = (lp_total_supply * rewardRate * 86400 * 365 * 1e6) / (pool_lp_stake * lp_YISK_amount * 2);
  }

  function getTokenPrice(
    address token,
    address UniPool,
    address wethAddress
  ) external view returns (uint256 price) {
    uint256 token_in_pool = IERC20(token).balanceOf(UniPool);
    uint256 weth_in_pool = IERC20(wethAddress).balanceOf(UniPool);
    price = (weth_in_pool * getYLSKPrice() * 1e10) / token_in_pool;
  }
}
