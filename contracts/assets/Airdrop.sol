// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }
}

interface IWHT {
    function balanceOf(address owner) external view returns (uint);

    function transfer(address to, uint value) external returns (bool);
}

contract Airdrop is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accWhtPerShare;
    }

    IWHT public wht;
    // Airdrop tokens for per block.
    uint256 public whtPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when wht mining starts.
    uint256 public startBlock;
    // The block number when wht mining end;
    uint256 public endBlock;
    // Airdrop cycle default 1day
    uint256 public cycle;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IWHT _wht,
        uint256 _cycle
    ) public {
        wht = _wht;
        cycle = _cycle;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function newAirdrop(uint256 _whtAmount, uint256 _newPerBlock, uint256 _startBlock) public onlyOwner {
        require(block.number > endBlock && _startBlock >= endBlock, "Not finished");
        massUpdatePools();
        uint256 beforeAmount = IWHT(wht).balanceOf(address(this));
        TransferHelper.safeTransferFrom(address(wht), msg.sender, address(this), _whtAmount);
        uint256 afterAmount = IWHT(wht).balanceOf(address(this));
        uint256 balance = afterAmount.sub(beforeAmount);
        require(balance == _whtAmount, "Error balance");
        require(balance > 0 && (cycle * _newPerBlock) <= balance, "Balance not enough");
        whtPerBlock = _newPerBlock;
        startBlock = _startBlock;
        endBlock = _startBlock.add(cycle);
        updatePoolLastRewardBlock(_startBlock);
    }

    function updatePoolLastRewardBlock(uint256 _lastRewardBlock) private {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardBlock = _lastRewardBlock;
        }
    }

    function setCycle(uint256 _newCycle) public onlyOwner {
        cycle = _newCycle;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        require(address(_lpToken) != address(0), "lpToken is the zero address");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accWhtPerShare : 0
        }));
    }

    // Update the given pool's wht allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 number = block.number > endBlock ? endBlock : block.number;
        if (number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = number;
            return;
        }
        uint256 multiplier = number.sub(pool.lastRewardBlock);
        uint256 whtReward = multiplier.mul(whtPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accWhtPerShare = pool.accWhtPerShare.add(whtReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = number;
    }


    function pending(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accWhtPerShare = pool.accWhtPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 number = block.number > endBlock ? endBlock : block.number;
        if (number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = number.sub(pool.lastRewardBlock);
            uint256 whtReward = multiplier.mul(whtPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accWhtPerShare = accWhtPerShare.add(whtReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accWhtPerShare).div(1e12).sub(user.rewardDebt);
    }


    // Deposit LP tokens dividends WHT;
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pendingAmount = user.amount.mul(pool.accWhtPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingAmount > 0) {
                safeWhtTransfer(msg.sender, pendingAmount);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accWhtPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pendingAmount = user.amount.mul(pool.accWhtPerShare).div(1e12).sub(user.rewardDebt);
        if (pendingAmount > 0) {
            safeWhtTransfer(msg.sender, pendingAmount);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accWhtPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe wht transfer function, just in case if rounding error causes pool to not have enough whts.
    function safeWhtTransfer(address _to, uint256 _amount) internal {
        uint256 whtBal = IWHT(wht).balanceOf(address(this));
        if (_amount > whtBal) {
            wht.transfer(_to, whtBal);
        } else {
            wht.transfer(_to, _amount);
        }
    }
}
