// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract Catemoon is ERC20, ERC20Burnable {
  // 200 billion tokens as total supply
  uint256 private constant TOTAL_SUPPLY = 2 * 10**2 * 10**9 * 10**18;

  constructor () ERC20("Catemoon", "CTM") {
    _mint(msg.sender, TOTAL_SUPPLY);

    _burn(msg.sender, TOTAL_SUPPLY / 2);
  }
}