// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17;

import { yLskToken } from "../src/yLSK/yLskToken.sol";
import { LskDepositor } from "../src/yLSK/LskDepositor.sol";
import { YISK } from "../src/YISK.sol";
import { xYISK } from "../src/xYISK.sol";
import { Governable } from "../src/Governable.sol";
import { YiskFinance } from "../src/YiskFinance.sol";
import { YiskHelper } from "../src/YiskHelper.sol";
import { xYISKBoost } from "../src/xYISKBoost.sol";
import { YiskFund } from "../src/YiskFund.sol";
import { xYISKMinter } from "../src/xYISKMinter.sol";
import { StakingRewardsV2 } from "../src/StakingRewardsV2.sol";
import { BaseScript } from "./Base.s.sol";

contract Deploy is BaseScript {
  address _team = 0x75D11987488c7ecE47fFDFa623Bf109b85a1Af33;

  function run()
    public
    broadcaster
    returns (
      yLskToken yLSK,
      LskDepositor lskDepositor,
      YISK yisk,
      xYISK xyisk,
      Governable governable,
      YiskFinance yiskFinance,
      YiskHelper yiskHelper,
      xYISKBoost xyiskBoost,
      YiskFund yiskFund,
      xYISKMinter xyiskMinter
    )
  {
    address LISK = 0x8a21CF9Ba08Ae709D64Cb25AfAA951183EC9FF6D;
    address LISK_SEPOLIA_STAKING = 0x77F4Ed75081c62aD9fA254b0E088A4660AacF68D;

    yLSK = new yLskToken();
    lskDepositor = new LskDepositor(LISK, LISK_SEPOLIA_STAKING,address(yLSK));
    yisk = new YISK();
    xyisk = new xYISK(address(yisk));
    governable = new Governable();
    yiskFinance = new YiskFinance();
    yiskHelper = new YiskHelper(address(yiskFinance));
    xyiskBoost = new xYISKBoost();
    yiskFund = new YiskFund(address(yiskFinance), _team, 2000);
    xyiskMinter = new xYISKMinter(
      address(yiskFinance),
      address(yiskHelper),
      address(xyiskBoost),
      address(yiskFund),
      address(yisk),
      address(xyisk)
    );

    // Auth Access
    // grant role to xYISK for can mint the YISK
    yisk.grantRole(keccak256("MINTER_ROLE"), address(xyisk));
    // grant role to xYISKMinter for can mint the YISK
    yisk.grantRole(keccak256("MINTER_ROLE"), address(xyiskMinter));

    yiskFinance.setXYISKMinter(address(xyiskMinter));
    yiskFinance.setYISKStakingPool(address(yiskFund));
    yiskFund.setTokenAddress(address(xyisk));
    xyisk.setAuthorizedYiskMinterAndConverter(address(xyiskMinter), true);

    // xyiskMinter.setExtraRate(20 ether);
    // xyiskMinter.notifyRewardAmount(1000000 ether);

    // FOR Testing Only
    // xyiskMinter.setExtraRate(20 ether);
    // xyiskMinter.notifyRewardAmount(30000 ether);

    // yisk.mint(0x90057d39384eb10607a8953eC735f2d9EC169cf1, 10000 ether);
    // yisk.mint(0xB396bDA61ff0e411F828768d958a4C2684140171, 100 ether);
    // yisk.mint(0xE46bBc922c0537349ce6F7A12F8F74d360768756, 100 ether);
    // yisk.mint(0xeD7B73A82dB4D2406c0a25c55122fc317f2e6Afd, 100 ether);

    yiskFinance.setYLSKAddress(address(yLSK));

    yLSK.setOperator(address(lskDepositor));

    lskDepositor.setPaused(false);

    YiskFinance(LISK).approve(address(lskDepositor), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    // lskDepositor.deposit(0.1 ether);


    // yLSK.approve(address(yiskFinance), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
  }
}
