// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interface/IMdx.sol";
import "./interface/IMasterChef.sol";


contract CoinChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _sushiLP;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
        uint256 sushiRewardDebt; //sushi Reward debt.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. MDXs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that MDXs distribution occurs.
        uint256 accMdxPerShare; // Accumulated MDXs per share, times 1e12.
        uint256 totalAmount;    // Total amount of current pool deposit.
        uint256 accSushiPerShare; //Accumulated SuSHIs per share
    }

    // The MDX TOKEN!
    IMdx public mdx;
    // MDX tokens created per block.
    uint256 public mdxPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Corresponding to the pid of the sushi pool
    mapping(uint256 => uint256) public poolCorrespond;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when MDX mining starts.
    uint256 public startBlock;
    // The block number when MDX mining end;
    uint256 public endBlock;
    // SUSHI MasterChef 0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd
    address public constant sushiChef = 0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd;
    // SUSHI Token 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2
    address public constant sushiToken = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IMdx _mdx,
        uint256 _mdxPerBlock,
        uint256 _startBlock
    ) public {
        mdx = _mdx;
        mdxPerBlock = _mdxPerBlock;
        startBlock = _startBlock;
        endBlock = _startBlock.add(200000);
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function addSushiLP(address _addLP) public onlyOwner returns (bool) {
        require(_addLP != address(0), "LP is the zero address");
        IERC20(_addLP).approve(sushiChef, uint256(- 1));
        return EnumerableSet.add(_sushiLP, _addLP);
    }

    function isSushiLP(address _LP) public view returns (bool) {
        return EnumerableSet.contains(_sushiLP, _LP);
    }

    function getSushiLPLength() public view returns (uint256) {
        return EnumerableSet.length(_sushiLP);
    }

    function getSushiLPAddress(uint256 _pid) public view returns (address){
        require(_pid <= getSushiLPLength() - 1, "not find this SushiLP");
        return EnumerableSet.at(_sushiLP, _pid);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        require(block.number < endBlock, "All token mining completed");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accMdxPerShare : 0,
        totalAmount : 0,
        accSushiPerShare : 0
        }));
    }

    // Update the given pool's MDX allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // The current pool corresponds to the pid of the sushi pool
    function setPoolCorr(uint256 _pid, uint256 _sid) public onlyOwner {
        require(_pid <= poolLength() - 1, "not find this pool");
        poolCorrespond[_pid] = _sid;
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
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply;
        if (isSushiLP(address(pool.lpToken))) {
            if (pool.totalAmount == 0) {
                pool.lastRewardBlock = block.number;
                return;
            }
            lpSupply = pool.totalAmount;
        } else {
            lpSupply = pool.lpToken.balanceOf(address(this));
            if (lpSupply == 0) {
                pool.lastRewardBlock = block.number;
                return;
            }
        }
        uint256 number = block.number > endBlock ? endBlock : block.number;
        uint256 multiplier = number.sub(pool.lastRewardBlock);
        uint256 mdxReward = multiplier.mul(mdxPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        bool minRet = mdx.mint(address(this), mdxReward);
        if (minRet) {
            pool.accMdxPerShare = pool.accMdxPerShare.add(mdxReward.mul(1e12).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    // View function to see pending MDXs on frontend.
    function pending(uint256 _pid, address _user) external view returns (uint256, uint256){
        PoolInfo storage pool = poolInfo[_pid];
        if (isSushiLP(address(pool.lpToken))) {
            (uint256 mdxAmount, uint256 sushiAmount) = pendingMdxAndSushi(_pid, _user);
            return (mdxAmount, sushiAmount);
        } else {
            uint256 mdxAmount = pendingMdx(_pid, _user);
            return (mdxAmount, 0);
        }
    }

    function pendingMdxAndSushi(uint256 _pid, address _user) private view returns (uint256, uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMdxPerShare = pool.accMdxPerShare;
        uint256 accSushiPerShare = pool.accSushiPerShare;
        uint256 number = block.number > endBlock ? endBlock : block.number;
        if (user.amount > 0) {
            uint256 sushiPending = IMasterChef(sushiChef).pendingSushi(poolCorrespond[_pid], address(this));
            accSushiPerShare = accSushiPerShare.add(sushiPending.mul(1e12).div(pool.totalAmount));
            uint256 userPending = user.amount.mul(accSushiPerShare).div(1e12).sub(user.sushiRewardDebt);
            if (number > pool.lastRewardBlock) {
                uint256 multiplier = number.sub(pool.lastRewardBlock);
                uint256 mdxReward = multiplier.mul(mdxPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
                accMdxPerShare = accMdxPerShare.add(mdxReward.mul(1e12).div(pool.totalAmount));
                return (user.amount.mul(accMdxPerShare).div(1e12).sub(user.rewardDebt), userPending);
            }
            if (number == pool.lastRewardBlock) {
                return (user.amount.mul(accMdxPerShare).div(1e12).sub(user.rewardDebt), userPending);
            }
        }
        return (0, 0);
    }

    function pendingMdx(uint256 _pid, address _user) private view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMdxPerShare = pool.accMdxPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        uint256 number = block.number > endBlock ? endBlock : block.number;
        if (user.amount > 0) {
            if (number > pool.lastRewardBlock) {
                uint256 multiplier = block.number.sub(pool.lastRewardBlock);
                uint256 mdxReward = multiplier.mul(mdxPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
                accMdxPerShare = accMdxPerShare.add(mdxReward.mul(1e12).div(lpSupply));
                return user.amount.mul(accMdxPerShare).div(1e12).sub(user.rewardDebt);
            }
            if (number == pool.lastRewardBlock) {
                return user.amount.mul(accMdxPerShare).div(1e12).sub(user.rewardDebt);
            }
        }
        return 0;
    }

    // Deposit LP tokens to CoinChef for MDX allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (isSushiLP(address(pool.lpToken))) {
            depositMdxAndSushi(_pid, _amount, msg.sender);
        } else {
            depositMdx(_pid, _amount, msg.sender);
        }
    }

    function depositMdxAndSushi(uint256 _pid, uint256 _amount, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pendingAmount = user.amount.mul(pool.accMdxPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingAmount > 0) {
                safeMdxTransfer(_user, pendingAmount);
            }
            uint256 beforeSushi = IERC20(sushiToken).balanceOf(address(this));
            IMasterChef(sushiChef).deposit(poolCorrespond[_pid], 0);
            uint256 afterSushi = IERC20(sushiToken).balanceOf(address(this));
            pool.accSushiPerShare = pool.accSushiPerShare.add(afterSushi.sub(beforeSushi).mul(1e12).div(pool.totalAmount));
            uint256 sushiPending = user.amount.mul(pool.accSushiPerShare).div(1e12).sub(user.sushiRewardDebt);
            if (sushiPending > 0) {
                IERC20(sushiToken).safeTransfer(_user, sushiPending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(_user, address(this), _amount);
            if (pool.totalAmount == 0) {
                IMasterChef(sushiChef).deposit(poolCorrespond[_pid], _amount);
                pool.totalAmount = pool.totalAmount.add(_amount);
                user.amount = user.amount.add(_amount);
            } else {
                uint256 beforeSushi = IERC20(sushiToken).balanceOf(address(this));
                IMasterChef(sushiChef).deposit(poolCorrespond[_pid], _amount);
                uint256 afterSushi = IERC20(sushiToken).balanceOf(address(this));
                pool.accSushiPerShare = pool.accSushiPerShare.add(afterSushi.sub(beforeSushi).mul(1e12).div(pool.totalAmount));
                pool.totalAmount = pool.totalAmount.add(_amount);
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accMdxPerShare).div(1e12);
        user.sushiRewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        emit Deposit(_user, _pid, _amount);
    }

    function depositMdx(uint256 _pid, uint256 _amount, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pendingAmount = user.amount.mul(pool.accMdxPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingAmount > 0) {
                safeMdxTransfer(_user, pendingAmount);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(_user, address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalAmount = pool.totalAmount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMdxPerShare).div(1e12);
        emit Deposit(_user, _pid, _amount);
    }

    // Withdraw LP tokens from CoinChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (isSushiLP(address(pool.lpToken))) {
            withdrawMdxAndSushi(_pid, _amount, msg.sender);
        } else {
            withdrawMdx(_pid, _amount, msg.sender);
        }
    }

    function withdrawMdxAndSushi(uint256 _pid, uint256 _amount, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(user.amount >= _amount, "withdrawMdxAndSushi: not good");
        updatePool(_pid);
        uint256 pendingAmount = user.amount.mul(pool.accMdxPerShare).div(1e12).sub(user.rewardDebt);
        if (pendingAmount > 0) {
            safeMdxTransfer(_user, pendingAmount);
        }
        if (_amount > 0) {
            uint256 beforeSushi = IERC20(sushiToken).balanceOf(address(this));
            IMasterChef(sushiChef).withdraw(poolCorrespond[_pid], _amount);
            uint256 afterSushi = IERC20(sushiToken).balanceOf(address(this));
            pool.accSushiPerShare = pool.accSushiPerShare.add(afterSushi.sub(beforeSushi).mul(1e12).div(pool.totalAmount));
            uint256 sushiPending = user.amount.mul(pool.accSushiPerShare).div(1e12).sub(user.sushiRewardDebt);
            if (sushiPending > 0) {
                IERC20(sushiToken).safeTransfer(_user, sushiPending);
            }
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            pool.lpToken.safeTransfer(_user, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMdxPerShare).div(1e12);
        user.sushiRewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        emit Withdraw(_user, _pid, _amount);
    }

    function withdrawMdx(uint256 _pid, uint256 _amount, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(user.amount >= _amount, "withdrawMdx: not good");
        updatePool(_pid);
        uint256 pendingAmount = user.amount.mul(pool.accMdxPerShare).div(1e12).sub(user.rewardDebt);
        if (pendingAmount > 0) {
            safeMdxTransfer(_user, pendingAmount);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            pool.lpToken.safeTransfer(_user, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMdxPerShare).div(1e12);
        emit Withdraw(_user, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (isSushiLP(address(pool.lpToken))) {
            emergencyWithdrawMdxAndSushi(_pid, msg.sender);
        } else {
            emergencyWithdrawMdx(_pid, msg.sender);
        }
    }

    function emergencyWithdrawMdxAndSushi(uint256 _pid, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 amount = user.amount;
        uint256 beforeSushi = IERC20(sushiToken).balanceOf(address(this));
        IMasterChef(sushiChef).withdraw(poolCorrespond[_pid], amount);
        uint256 afterSushi = IERC20(sushiToken).balanceOf(address(this));
        pool.accSushiPerShare = pool.accSushiPerShare.add(afterSushi.sub(beforeSushi).mul(1e12).div(pool.totalAmount));
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(_user, amount);
        pool.totalAmount = pool.totalAmount.sub(amount);
        emit EmergencyWithdraw(_user, _pid, amount);
    }

    function emergencyWithdrawMdx(uint256 _pid, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(_user, amount);
        pool.totalAmount = pool.totalAmount.sub(amount);
        emit EmergencyWithdraw(_user, _pid, amount);
    }

    // Safe MDX transfer function, just in case if rounding error causes pool to not have enough MDXs.
    function safeMdxTransfer(address _to, uint256 _amount) internal {
        uint256 mdxBal = mdx.balanceOf(address(this));
        if (_amount > mdxBal) {
            mdx.transfer(_to, mdxBal);
        } else {
            mdx.transfer(_to, _amount);
        }
    }

}
