pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20Token is ERC20 {
  constructor() ERC20("Test", "Test") {}

  function mint(address account, uint256 amount) public {
    _mint(account, amount);
  }
}
