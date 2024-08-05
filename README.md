# **Foundry Template** 

[![Foundry][foundry-badge]][foundry] [![License: MIT][license-badge]][license]

## **Yisk Finance Contracts**

### **What's Inside**
1. **YiskFinance (yiskUSD)**: Main protocol (Lending)
2. **YiskFund**: Protocol Revenue Distributor (xYISK Holders got yiskUSD)
3. **Yisk Helper**: Serving data to FE
4. **YISK**: Main Token
5. **xYISK**: version X of YISK
6. **Governable**: Authorities for Yisk
7. **StakingRewardsV2**: Farming (Stake LP got 20% yisk and 80% xYISK)
8. **xYISKBoost**: Handle xYISK Boost (Staking LP and yiskUSD Minters)
9. **xYISKMinter**: yiskUSD Minters got 20% yisk and 80% xYISK

> **Note**: We need to determine the token emission for StakingRewardsV2 and xYISKMinter

### **Lisk Sepolia Env**

**Addresses and main methods**:

1. **YISK**: `0x89DAFc0a0B3FD8f9f94B07d84a3c93f3316F1484`
2. **xYISK**: `0x6266704AA4BED781Bc79077B282758AEd8f8baA5`
   - `convert(uint256 amount)`
   - `redeem(uint256 xYISKAmount, uint256 duration)` - Duration must be >= 15 days (in epoch)
   - `userRedeems(address)` - getting user redeem or vesting info
   - `finalizeRedeem(uint256 redeemIndex)` - claim the vesting (redeemIndex should be passing with one of index in userRedeems[] result)
   - `cancelRedeem(uint256 redeemIndex)`
3. **Governable**: `0x6BE056691DBC6F2B964e3A6Cee5b9587c344CbFC`
4. **Yisk (yiskUSD)**: `0xEBea66f410eEeE0901309886EfCe08390b860FD2`
   - `depositYLSKToMint(address onBehalfOf,uint256 yLSKamount, uint256 mintAmount)` => add yLSK as collateral and borrow
   - **onBehalfOf** => deposit for who
   - **mintAmount** => amount of yiskUSD
   - **passing 0 to mintAmount for add collateral only**
   - `withdraw(address onBehalfOf, uint256 amount)` => withdraw collateral
   - `mint(address onBehalfOf, uint256 amount)` => mint yiskUSD (borrow again)
   - `burn(address onBehalfOf, uint256 amount)` => repay 
   - `rigidRedemption(address provider, uint256 yiskUSDAmount)` => redeem
   - **provider should be the redempetion provider, for applying to become redempetionProvider, use this function becomeRedemptionProvider(bool _bool)**
5. **YiskHelper**: `0x03Ac03851f760e9Bd1F6A2BddDCD3d7E209e54ed`
   => Check this out, for serving data to FE
6. **xYISKBoost**: `0x6cb44B5F1e6A5F597E486550935548b52F1ab6a3`
   - `setLockStatus(uint256 id)`
   - **Id 0 for 30 days**
   - **Id 1 for 90 days**
   - **Id 2 for 180 days**
   - **Id 3 for 365 days**
   - `getUnlockTime(address user)` => get time when the boost finished (so user can claim the reward)
7. **YiskFund**: `0x3C598375DaedE2CfedF3b2292c2ddfFD7354F4a2`
   - `getReward()` => claim yiskUSD
   - `getClaimableYiskUSD(address user)` => get earned yiskUSD
8. **xYISKMinter**: `0x09343C2c129Df57E13EE07AD59B7250D22FBe0D3`
   - `getReward()` => claim 20% YISK and 80% xYISK
   - `earned(address _account)` => get earned rewards
9. **StakingRewardsV2**:
   - `getReward()` => claim 20% YISK and 80% xYISK
   - `earned(address _account)` => get earned rewards

## **APR Calculation**
1. YISK/ETH LP -> 
- yiskHelper -> getStakingPoolAPR(poolAddress, yiskAddress, lpToken) + (boost percent from APR)
  OR
- (RPS* 31536000*tokenPriceInUSD/totalValueLiquidity)*100
2. yiskUSD mint pool -> 
annualReward = rewardRateInDollar * 31,556,926(secondsPerYear)
APR = (annualReward / totalStaked) * 100
3. Earn Revenue
APR = (Total Protocol Revenue / Total Staked in Dollar) * 365 / Reward Distribution Period * 100%
4. yiskUSD/USDT LP
- (RPS* 31536000*tokenPriceInUSD/totalValueLiquidity)*100

## **Acknowledgments**

This project was developed by [Nava Labs](https://www.navalabs.io).

### **License**

This project is licensed under MIT.

[foundry-badge]: https://img.shields.io/badge/Foundry-v1.0-green
[foundry]: https://link-to-foundry.com
[license-badge]: https://img.shields.io/badge/license-MIT-blue
[license]: https://link-to-license.com
