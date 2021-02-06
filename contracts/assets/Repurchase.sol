// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../interface/IMdexPair.sol";

contract Repurchase is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _caller;

    address public constant USDT = 0xa71EdC38d189767582C38A3145b5873052c3e47a;
    address public constant MDX = 0x25D2e80cB6B86881Fd7e07dd263Fb79f4AbE033c;
    address public constant MDX_USDT = 0x615E6285c5944540fd8bd921c9c8c56739Fd1E13;
    address public constant destroyAddress = 0xF9852C6588b70ad3c26daE47120f174527e03a25;
    address public emergencyAddress;
    uint256 public amountIn;

    constructor (uint256 _amount, address _emergencyAddress) public {
        require(_amount > 0, "Amount must be greater than zero");
        require(_emergencyAddress != address(0), "Is zero address");
        amountIn = _amount;
        emergencyAddress = _emergencyAddress;
    }

    function setAmountIn(uint256 _newIn) public onlyOwner {
        amountIn = _newIn;
    }

    function setEmergencyAddress(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "Is zero address");
        emergencyAddress = _newAddress;
    }

    function addCaller(address _newCaller) public onlyOwner returns (bool) {
        require(_newCaller != address(0), "NewCaller is the zero address");
        return EnumerableSet.add(_caller, _newCaller);
    }

    function delCaller(address _delCaller) public onlyOwner returns (bool) {
        require(_delCaller != address(0), "DelCaller is the zero address");
        return EnumerableSet.remove(_caller, _delCaller);
    }

    function getCallerLength() public view returns (uint256) {
        return EnumerableSet.length(_caller);
    }

    function isCaller(address _call) public view returns (bool) {
        return EnumerableSet.contains(_caller, _call);
    }

    function getCaller(uint256 _index) public view returns (address){
        require(_index <= getCallerLength() - 1, "index out of bounds");
        return EnumerableSet.at(_caller, _index);
    }

    function swap() external onlyCaller returns (uint256 amountOut){
        require(IERC20(USDT).balanceOf(address(this)) >= amountIn, "Insufficient contract balance");
        (uint256 reserve0, uint256 reserve1,) = IMdexPair(MDX_USDT).getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        amountOut = amountIn.mul(997).mul(reserve0) / reserve1.mul(1000).add(amountInWithFee);
        IERC20(USDT).safeTransfer(MDX_USDT, amountIn);
        IMdexPair(MDX_USDT).swap(amountOut, 0, destroyAddress, new bytes(0));
    }

    modifier onlyCaller() {
        require(isCaller(msg.sender), "Not the caller");
        _;
    }

    function emergencyWithdraw(address _token) public onlyOwner {
        require(IERC20(_token).balanceOf(address(this)) > 0, "Insufficient contract balance");
        IERC20(_token).transfer(emergencyAddress, IERC20(_token).balanceOf(address(this)));
    }
}
