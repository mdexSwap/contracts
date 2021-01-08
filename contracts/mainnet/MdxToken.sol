// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MdxToken is ERC20("MDX Token", "MDX"), Ownable {
    uint256 private constant maxSupply = 30000000 * 1e18;     // the total supply
    address public minter;

    // mint with max supply
    function mint(address _to, uint256 _amount) public onlyMinter returns (bool) {
        if (_amount.add(totalSupply()) > maxSupply) {
            return false;
        }
        _mint(_to, _amount);
        return true;
    }

    function setMinter(address _newMinter) public onlyOwner {
        require(_newMinter != address(0), "is zero address");
        minter = _newMinter;
    }
    // modifier for mint function
    modifier onlyMinter() {
        require(msg.sender == minter, "caller is not the minter");
        _;
    }
}
