// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./YiskUSD.sol";
import "./Governable.sol";

interface ILskDepositor {
    function mint(address _referral) external payable returns (uint256 yLSK);

    function withdraw(address _to) external returns (uint256 ETH);

}

interface IyLSK {
    function balanceOf(address _account) external view returns (uint256);

    function transfer(address _recipient, uint256 _amount)
        external
        returns (bool);

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool);
}

interface YiskStakingPool {
    function notifyRewardAmount(uint256 amount) external;
}

interface xYISKMinter {
    function refreshReward(address user) external;
}

interface IPriceFeed {
    function fetchPrice() external returns (uint256);
}

contract YiskFinance is YiskUSD, Governable {
    uint256 public totalDepositedYLSK;
    uint256 public lastReportTime;
    uint256 public totalYiskUSDCirculation;
    uint256 year = 86400 * 365;

    uint256 public mintFeeApy = 150;
    uint256 public safeCollateralRate = 160 * 1e18;
    uint256 public immutable badCollateralRate = 150 * 1e18;
    uint256 public redemptionFee = 50;
    uint8 public keeperRate = 1;

    mapping(address => uint256) public depositedYLsk;
    mapping(address => uint256) private borrowed;
    mapping(address => bool) redemptionProvider;
    uint256 public feeStored;

    // NOTE: CURRENTLY HARDCODED, to $1, this is just POC, fetch using Oracle, Trellor in PriceFeed later on.
    uint256 public hardcodedYLSKPrice = 10**18;

    IyLSK public yLSK = IyLSK(0x5A86858aA3b595FD6663c2296741eF4cd8BC4d01);
    xYISKMinter public xYiskMinter;
    YiskStakingPool public serviceFeePool;

    event BorrowApyChanged(uint256 newApy);
    event SafeCollateralRateChanged(uint256 newRatio);
    event KeeperRateChanged(uint256 newSlippage);
    event RedemptionFeeChanged(uint256 newSlippage);
    event DepositYLSK(
        address sponsor,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 timestamp
    );
    event WithdrawYLSK(
        address sponsor,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 timestamp
    );
    event Mint(
        address sponsor,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 timestamp
    );
    event Burn(
        address sponsor,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 timestamp
    );
    event LiquidationRecord(
        address provider,
        address keeper,
        address indexed onBehalfOf,
        uint256 YiskUSDamount,
        uint256 LiquidateYLSKAmount,
        uint256 keeperReward,
        bool superLiquidation,
        uint256 timestamp
    );
    event LSDistribution(
        uint256 yLSKAdded,
        uint256 payoutYiskUSD,
        uint256 timestamp
    );
    event RedemptionProvider(address user, bool status);
    event RigidRedemption(
        address indexed caller,
        address indexed provider,
        uint256 YiskUSDAmount,
        uint256 yLskAmount,
        uint256 timestamp
    );
    event FeeDistribution(
        address indexed feeAddress,
        uint256 feeAmount,
        uint256 timestamp
    );
    event ServiceFeePoolChanged(address pool, uint256 timestamp);
    event XYISKMinterChanged(address pool, uint256 timestamp);

    constructor() {
        gov = msg.sender;
    }

    function setYLSKAddress(address yslkAddress) external onlyGov {
        yLSK = IyLSK(yslkAddress);
    }

    function setBorrowApy(uint256 newApy) external onlyGov {
        require(newApy <= 150, "Borrow APY cannot exceed 1.5%");
        _saveReport();
        mintFeeApy = newApy;
        emit BorrowApyChanged(newApy);
    }

    /**
     * @notice  safeCollateralRate can be decided by DAO,starts at 160%
     */
    function setSafeCollateralRate(uint256 newRatio) external onlyGov {
        require(
            newRatio >= 160 * 1e18,
            "Safe CollateralRate should more than 160%"
        );
        safeCollateralRate = newRatio;
        emit SafeCollateralRateChanged(newRatio);
    }

    /**
     * @notice KeeperRate can be decided by DAO,1 means 1% of revenue
     */
    function setKeeperRate(uint8 newRate) external onlyGov {
        require(newRate <= 5, "Max Keeper reward is 5%");
        keeperRate = newRate;
        emit KeeperRateChanged(newRate);
    }

    /**
     * @notice DAO sets RedemptionFee, 100 means 1%
     */
    function setRedemptionFee(uint8 newFee) external onlyGov {
        require(newFee <= 500, "Max Redemption Fee is 5%");
        redemptionFee = newFee;
        emit RedemptionFeeChanged(newFee);
    }

    function setYISKStakingPool(address addr) external onlyGov {
        serviceFeePool = YiskStakingPool(addr);
        emit ServiceFeePoolChanged(addr, block.timestamp);
    }

    function setXYISKMinter(address addr) external onlyGov {
        xYiskMinter = xYISKMinter(addr);
        emit XYISKMinterChanged(addr, block.timestamp);
    }

    /**
     * @notice User chooses to become a Redemption Provider
     */
    function becomeRedemptionProvider(bool _bool) external {
        xYiskMinter.refreshReward(msg.sender);
        redemptionProvider[msg.sender] = _bool;
        emit RedemptionProvider(msg.sender, _bool);
    }

    /**
     * @notice Deposit yLSK on behalf of an address, update the interest distribution and deposit record the this address, can mint YiskUSD directly
     * Emits a `DepositYLSK` event.
     *
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `yLSK` Must be higher than 0.
     * - `mintAmount` Send 0 if doesn't mint YiskUSD
     * @dev Record the deposited yLSK in the ratio of 1:1.
     */
    function depositYLSKToMint(
        address onBehalfOf,
        uint256 yLSKamount,
        uint256 mintAmount
    ) external {
        require(onBehalfOf != address(0), "DEPOSIT_TO_THE_ZERO_ADDRESS");
        require(yLSKamount >= 1 ether, "Deposit should not be less than 1 yLSK.");
        yLSK.transferFrom(msg.sender, address(this), yLSKamount);

        totalDepositedYLSK += yLSKamount;
        depositedYLsk[onBehalfOf] += yLSKamount;
        if (mintAmount > 0) {
            _mintYiskUSD(onBehalfOf, onBehalfOf, mintAmount);
        }
        emit DepositYLSK(msg.sender, onBehalfOf, yLSKamount, block.timestamp);
    }

    /**
     * @notice Withdraw collateral assets to an address
     * Emits a `WithdrawYLSK` event.
     *
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0.
     *
     * @dev Withdraw yLSK. Check user’s collateral rate after withdrawal, should be higher than `safeCollateralRate`
     */
    function withdraw(address onBehalfOf, uint256 amount) external {
        require(onBehalfOf != address(0), "WITHDRAW_TO_THE_ZERO_ADDRESS");
        require(amount > 0, "ZERO_WITHDRAW");
        require(depositedYLsk[msg.sender] >= amount, "Insufficient Balance");
        totalDepositedYLSK -= amount;
        depositedYLsk[msg.sender] -= amount;

        yLSK.transfer(onBehalfOf, amount);
        if (borrowed[msg.sender] > 0) {
            _checkHealth(msg.sender);
        }
        emit WithdrawYLSK(msg.sender, onBehalfOf, amount, block.timestamp);
    }

    /**
     * @notice The mint amount number of YiskUSD is minted to the address
     * Emits a `Mint` event.
     *
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0. Individual mint amount shouldn't surpass 10% when the circulation reaches 10_000_000
     */
    function mint(address onBehalfOf, uint256 amount) public {
        require(onBehalfOf != address(0), "MINT_TO_THE_ZERO_ADDRESS");
        require(amount > 0, "ZERO_MINT");
        _mintYiskUSD(msg.sender, onBehalfOf, amount);
        if (
            (borrowed[msg.sender] * 100) / totalSupply() > 10 &&
            totalSupply() > 10_000_000 * 1e18
        ) revert("Mint Amount cannot be more than 10% of total circulation");
    }

    /**
     * @notice Burn the amount of YiskUSD and payback the amount of minted YiskUSD
     * Emits a `Burn` event.
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0.
     * @dev Calling the internal`_repay`function.
     */
    function burn(address onBehalfOf, uint256 amount) external {
        require(onBehalfOf != address(0), "BURN_TO_THE_ZERO_ADDRESS");
        _repay(msg.sender, onBehalfOf, amount);
    }

    /**
     * @notice When overallCollateralRate is above 150%, Keeper liquidates borrowers whose collateral rate is below badCollateralRate, using YiskUSD provided by Liquidation Provider.
     *
     * Requirements:
     * - onBehalfOf Collateral Rate should be below badCollateralRate
     * - yLskAmount should be less than 50% of collateral
     * - provider should authorize YiskFinance to utilize YiskUSD
     * @dev After liquidation, borrower's debt is reduced by yLskAmount * yLskPrice, collateral is reduced by the yLskAmount corresponding to 110% of the value. Keeper gets keeperRate / 110 of Liquidation Reward and Liquidator gets the remaining yLSK.
     */
    function liquidation(
        address provider,
        address onBehalfOf,
        uint256 yLskAmount
    ) external {
        uint256 yLskPrice = _yLskPrice();
        uint256 onBehalfOfCollateralRate = (depositedYLsk[onBehalfOf] *
            yLskPrice *
            100) / borrowed[onBehalfOf];
        require(
            onBehalfOfCollateralRate < badCollateralRate,
            "Borrowers collateral rate should below badCollateralRate"
        );

        require(
            yLskAmount * 2 <= depositedYLsk[onBehalfOf],
            "a max of 50% collateral can be liquidated"
        );
        uint256 YiskUSDAmount = (yLskAmount * yLskPrice) / 1e18;
        require(
            allowance(provider, address(this)) >= YiskUSDAmount,
            "provider should authorize to provide liquidation YiskUSD"
        );

        _repay(provider, onBehalfOf, YiskUSDAmount);
        uint256 reducedYLSK = (yLskAmount * 11) / 10;
        totalDepositedYLSK -= reducedYLSK;
        depositedYLsk[onBehalfOf] -= reducedYLSK;
        uint256 reward2keeper;
        if (provider == msg.sender) {
            yLSK.transfer(msg.sender, reducedYLSK);
        } else {
            reward2keeper = (reducedYLSK * keeperRate) / 110;
            yLSK.transfer(provider, reducedYLSK - reward2keeper);
            yLSK.transfer(msg.sender, reward2keeper);
        }
        emit LiquidationRecord(
            provider,
            msg.sender,
            onBehalfOf,
            YiskUSDAmount,
            reducedYLSK,
            reward2keeper,
            false,
            block.timestamp
        );
    }

    /**
     * @notice When overallCollateralRate is below badCollateralRate, borrowers with collateralRate below 125% could be fully liquidated.
     * Emits a `LiquidationRecord` event.
     *
     * Requirements:
     * - Current overallCollateralRate should be below badCollateralRate
     * - `onBehalfOf`collateralRate should be below 125%
     * @dev After Liquidation, borrower's debt is reduced by yLskAmount * yLskPrice, deposit is reduced by yLskAmount * borrower's collateralRate. Keeper gets a liquidation reward of `keeperRate / borrower's collateralRate
     */
    function superLiquidation(
        address provider,
        address onBehalfOf,
        uint256 yLskAmount
    ) external {
        uint256 yLskPrice = _yLskPrice();
        require(
            (totalDepositedYLSK * yLskPrice * 100) / totalSupply() <
                badCollateralRate,
            "overallCollateralRate should below 150%"
        );
        uint256 onBehalfOfCollateralRate = (depositedYLsk[onBehalfOf] *
            yLskPrice *
            100) / borrowed[onBehalfOf];
        require(
            onBehalfOfCollateralRate < 125 * 1e18,
            "borrowers collateralRate should below 125%"
        );
        require(
            yLskAmount <= depositedYLsk[onBehalfOf],
            "total of collateral can be liquidated at most"
        );
        uint256 YiskUSDAmount = (yLskAmount * yLskPrice) / 1e18;
        if (onBehalfOfCollateralRate >= 1e20) {
            YiskUSDAmount = (YiskUSDAmount * 1e20) / onBehalfOfCollateralRate;
        }
        require(
            allowance(provider, address(this)) >= YiskUSDAmount,
            "provider should authorize to provide liquidation YiskUSD"
        );

        _repay(provider, onBehalfOf, YiskUSDAmount);

        totalDepositedYLSK -= yLskAmount;
        depositedYLsk[onBehalfOf] -= yLskAmount;
        uint256 reward2keeper;
        if (
            msg.sender != provider &&
            onBehalfOfCollateralRate >= 1e20 + keeperRate * 1e18
        ) {
            reward2keeper =
                ((yLskAmount * keeperRate) * 1e18) /
                onBehalfOfCollateralRate;
            yLSK.transfer(msg.sender, reward2keeper);
        }
        yLSK.transfer(provider, yLskAmount - reward2keeper);

        emit LiquidationRecord(
            provider,
            msg.sender,
            onBehalfOf,
            YiskUSDAmount,
            yLskAmount,
            reward2keeper,
            true,
            block.timestamp
        );
    }


    /**
     * @notice Choose a Redemption Provider, Rigid Redeem `YiskUSDAmount` of YiskUSD and get 1:1 value of yLSK
     * Emits a `RigidRedemption` event.
     *
     * *Requirements:
     * - `provider` must be a Redemption Provider
     * - `provider`debt must equal to or above`YiskUSDAmount`
     * @dev Service Fee for rigidRedemption `redemptionFee` is set to 0.5% by default, can be revised by DAO.
     */
    function rigidRedemption(address provider, uint256 YiskUSDAmount) external {
        require(
            redemptionProvider[provider],
            "provider is not a RedemptionProvider"
        );
        require(
            borrowed[provider] >= YiskUSDAmount,
            "YiskUSDAmount cannot surpass providers debt"
        );
        uint256 yLskPrice = _yLskPrice();
        uint256 providerCollateralRate = (depositedYLsk[provider] *
            yLskPrice *
            100) / borrowed[provider];
        require(
            providerCollateralRate >= 100 * 1e18,
            "provider's collateral rate should more than 100%"
        );
        _repay(msg.sender, provider, YiskUSDAmount);
        uint256 yLskAmount = (((YiskUSDAmount * 1e18) / yLskPrice) *
            (10000 - redemptionFee)) / 10000;
        depositedYLsk[provider] -= yLskAmount;
        totalDepositedYLSK -= yLskAmount;
        yLSK.transfer(msg.sender, yLskAmount);
        emit RigidRedemption(
            msg.sender,
            provider,
            YiskUSDAmount,
            yLskAmount,
            block.timestamp
        );
    }

    /**
     * @dev Refresh YISK reward before adding providers debt. Refresh YiskFinance generated service fee before adding totalYiskUSDCirculation. Check providers collateralRate cannot below `safeCollateralRate`after minting.
     */
    function _mintYiskUSD(
        address _provider,
        address _onBehalfOf,
        uint256 _amount
    ) internal {
        uint256 sharesAmount = getSharesByMintedYiskUSD(_amount);
        if (sharesAmount == 0) {
            //YiskUSD totalSupply is 0: assume that shares correspond to YiskUSD 1-to-1
            sharesAmount = _amount;
        }
        xYiskMinter.refreshReward(_provider);
        borrowed[_provider] += _amount;

        _mintShares(_onBehalfOf, sharesAmount);

        _saveReport();
        totalYiskUSDCirculation += _amount;
        _checkHealth(_provider);
        emit Mint(msg.sender, _onBehalfOf, _amount, block.timestamp);
    }

    /**
     * @notice Burn _provideramount YiskUSD to payback minted YiskUSD for _onBehalfOf.
     *
     * @dev Refresh YISK reward before reducing providers debt. Refresh YiskFinance generated service fee before reducing totalYiskUSDCirculation.
     */
    function _repay(
        address _provider,
        address _onBehalfOf,
        uint256 _amount
    ) internal {
        require(
            borrowed[_onBehalfOf] >= _amount,
            "Repaying Amount Surpasses Borrowing Amount"
        );

        uint256 sharesAmount = getSharesByMintedYiskUSD(_amount);
        _burnShares(_provider, sharesAmount);

        xYiskMinter.refreshReward(_onBehalfOf);

        borrowed[_onBehalfOf] -= _amount;
        _saveReport();
        totalYiskUSDCirculation -= _amount;

        emit Burn(_provider, _onBehalfOf, _amount, block.timestamp);
    }

    function _saveReport() internal {
        feeStored += _newFee();
        lastReportTime = block.timestamp;
    }

    /**
     * @dev Get USD value of current collateral asset and minted YiskUSD through price oracle / Collateral asset USD value must higher than safe Collateral Rate.
     */
    function _checkHealth(address user) internal {
        if (
            ((depositedYLsk[user] * _yLskPrice() * 100) / borrowed[user]) <
            safeCollateralRate
        ) revert("collateralRate is Below safeCollateralRate");
    }

    /**
     * @dev NOTE: Return USD value of current yLSK through oracle
     */
    function _yLskPrice() public returns (uint256) {
        return hardcodedYLSKPrice;
    }

    /**
     * @dev NOTE: TESTING FUNCTION, change yLSK price
     */
    function setYLSKPrice(uint256 priceInWei) public onlyGov {
        hardcodedYLSKPrice = priceInWei;
    }

    function _newFee() internal view returns (uint256) {
        return
            (totalYiskUSDCirculation *
                mintFeeApy *
                (block.timestamp - lastReportTime)) /
            year /
            10000;
    }

    /**
     * @dev total circulation of YiskUSD
     */
    function _getTotalMintedYiskUSD() internal view override returns (uint256) {
        return totalYiskUSDCirculation;
    }

    function getBorrowedOf(address user) external view returns (uint256) {
        return borrowed[user];
    }

    function isRedemptionProvider(address user) external view returns (bool) {
        return redemptionProvider[user];
    }
}

