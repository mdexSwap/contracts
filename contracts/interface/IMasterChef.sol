// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface IMasterChef {
    function pendingSushi(uint256 pid, address user) external view returns (uint256);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function emergencyWithdraw(uint256 pid) external;
}