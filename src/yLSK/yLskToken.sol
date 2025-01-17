// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract yLskToken is ERC20, Ownable {
  address public operator;

  constructor() ERC20('Yisk LSK', 'yLSK') {}

  function mint(address _to, uint256 _amount) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _mint(_to, _amount);
  }

  function burn(address _from, uint256 _amount) external {
    if (msg.sender != operator) revert UNAUTHORIZED();
    _burn(_from, _amount);
  }

  /** OWNER FUNCTIONS */
  function setOperator(address _operator) external onlyOwner {
    operator = _operator;
  }

  error UNAUTHORIZED();
}
