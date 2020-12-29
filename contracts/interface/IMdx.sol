// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMdx is IERC20 {
    function mint(address to, uint256 amount) external returns (bool);
}