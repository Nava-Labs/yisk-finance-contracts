// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
/**
 * @title YISK is an ERC20-compliant token.
 * - YISK can only be exchanged to xYISK in the YiskFund contract.
 * - Apart from the initial production, YISK can only be produced by destroying xYISK in the fund contract.
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract YISK is Ownable, AccessControl, ERC20 {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant RESCUER_ROLE = keccak256("RESCUER_ROLE");
  uint256 maxSupply = 100_000_000 * 1e18;

  address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

  constructor() ERC20("Yisk Finance", "YISK") {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(MINTER_ROLE, msg.sender);
    _setupRole(RESCUER_ROLE, msg.sender);
  }

  function mint(address user, uint256 amount) external onlyRole(MINTER_ROLE) returns (bool) {
    require(totalSupply() + amount <= maxSupply, "exceeding the maximum supply quantity.");
    _mint(user, amount);
    return true;
  }

  function burn(uint256 amount) external {
    _transfer(msg.sender, BURN_ADDRESS, amount);
  }

  /**
   * @dev Burns "amount" of YISK by sending it to BURN_ADDRESS
   */
  function _burn(address account, uint256 amount) internal override {
    _transfer(account, BURN_ADDRESS, amount);
  }

  function rescueTokens(IERC20 token, uint256 value) external onlyRole(RESCUER_ROLE) {
    token.transfer(msg.sender, value);
  }
}
