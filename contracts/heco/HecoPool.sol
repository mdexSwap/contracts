// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interface/IMdx.sol";
import "../interface/IMasterChefHeco.sol";

// HecoPool is the master of MDX. He can make MDXToken and he is a fair guy.
contract HecoPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _multLP;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
        uint256 multLpRewardDebt; //multLp Reward debt.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. MDXs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that MDXs distribution occurs.
        uint256 accMdxPerShare; // Accumulated MDXs per share, times 1e12.
        uint256 accMultLpPerShare; //Accumulated multLp per share
        uint256 totalAmount;    // Total amount of current pool deposit.
    }

    // The MDX TOKEN!
    IMdx public mdx;
    // Dev address.
    address public devAddress;
    // MDX tokens created per block.
    uint256 public mdxPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Corresponding to the pid of the multLP pool
    mapping(uint256 => uint256) public poolCorrespond;
    // pid corresponding address
    mapping(address => uint256) public LpOfPid;
    // Control mining
    bool public pause = true;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when MDX mining starts.
    uint256 public startBlock;
    // The block number when MDX mining end;
    uint256 public endBlock;
    // multLP MasterChef
    address public multLpChef;
    // multLP Token
    address public multLpToken;
    // dev address reward
    uint256 public devReward;
    // How many blocks are halved
    uint256 public halvingPeriod;
    // Halving cycle
    uint256 public halvingTimes;
    // Block that started halving
    uint256 public startHalvingPeriod;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IMdx _mdx,
        address _devAddress,
        uint256 _mdxPerBlock,
        uint256 _startBlock
    ) public {
        mdx = _mdx;
        devAddress = _devAddress;
        mdxPerBlock = _mdxPerBlock;
        startBlock = _startBlock;
        endBlock = _startBlock.add(877193);
    }

    function setStartHalvingPeriod(uint256 _block) public onlyOwner {
        startHalvingPeriod = _block;
    }

    function setHalvingPeriod(uint256 _block) public onlyOwner {
        halvingPeriod = _block;
    }

    function setHalvingTimes(uint256 _cycle) public onlyOwner {
        halvingTimes = _cycle;
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function addMultLP(address _addLP) public onlyOwner returns (bool) {
        require(_addLP != address(0), "LP is the zero address");
        IERC20(_addLP).approve(multLpChef, uint256(- 1));
        return EnumerableSet.add(_multLP, _addLP);
    }

    function isMultLP(address _LP) public view returns (bool) {
        return EnumerableSet.contains(_multLP, _LP);
    }

    function getMultLPLength() public view returns (uint256) {
        return EnumerableSet.length(_multLP);
    }

    function getMultLPAddress(uint256 _pid) public view returns (address){
        require(_pid <= getMultLPLength() - 1, "not find this multLP");
        return EnumerableSet.at(_multLP, _pid);
    }

    function setDevReward(uint256 _proportion) public onlyOwner {
        devReward = _proportion;
    }

    function setPause() public onlyOwner {
        pause = !pause;
    }

    function setEndBlock(uint256 _block) public onlyOwner {
        require(_block > endBlock, "EndBlock : OVERFLOW");
        endBlock = _block;
    }

    function setMultLP(address _multLpToken, address _multLpChef) public onlyOwner {
        require(_multLpToken != address(0) && _multLpChef != address(0), "is the zero address");
        multLpToken = _multLpToken;
        multLpChef = _multLpChef;
    }

    function replaceMultLP(address _multLpToken, address _multLpChef) public onlyOwner {
        require(_multLpToken != address(0) && _multLpChef != address(0), "is the zero address");
        require(pause == false, "No mining suspension");
        multLpToken = _multLpToken;
        multLpChef = _multLpChef;
        uint256 length = getMultLPLength();
        while (length > 0) {
            address dAddress = EnumerableSet.at(_multLP, 0);
            uint256 pid = LpOfPid[dAddress];
            IMasterChefHeco(multLpChef).emergencyWithdraw(poolCorrespond[pid]);
            EnumerableSet.remove(_multLP, dAddress);
            length--;
        }
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
        accMultLpPerShare : 0,
        totalAmount : 0
        }));
        LpOfPid[address(_lpToken)] = poolLength() - 1;
    }

    // Update the given pool's MDX allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // The current pool corresponds to the pid of the multLP pool
    function setPoolCorr(uint256 _pid, uint256 _sid) public onlyOwner {
        require(_pid <= poolLength() - 1, "not find this pool");
        poolCorrespond[_pid] = _sid;
    }

    function _mdxHalving() internal view returns (uint256){
        if (startHalvingPeriod == 0 || halvingPeriod == 0) {
            return 1;
        }
        uint256 parseHalving = block.number.sub(startHalvingPeriod).div(halvingPeriod);
        return 2 ** parseHalving;
    }

    function getMdxBlockReward() public view returns (uint256){
        if (halvingTimes == 0) {
            return mdxPerBlock;
        }
        uint256 halving = _mdxHalving();
        if (halving > halvingTimes) {
            return 0;
        }
        return mdxPerBlock.div(halving);
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
        if (isMultLP(address(pool.lpToken))) {
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
        uint256 blockReward = getMdxBlockReward();
        if (blockReward <= 0) {
            return;
        }
        uint256 mdxReward = multiplier.mul(blockReward).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 devGet;
        bool devRet = true;
        bool minRet = true;
        if (devReward != 0) {
            devGet = mdxReward.div(devReward);
            devRet = mdx.mint(devAddress, devGet);
        }
        if (mdxReward.sub(devGet) > 0) {
            minRet = mdx.mint(address(this), mdxReward.sub(devGet));
        }
        if (devRet && minRet) {
            pool.accMdxPerShare = pool.accMdxPerShare.add((mdxReward.sub(devGet)).mul(1e12).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    // View function to see pending MDXs on frontend.
    function pending(uint256 _pid, address _user) external view returns (uint256, uint256){
        PoolInfo storage pool = poolInfo[_pid];
        if (isMultLP(address(pool.lpToken))) {
            (uint256 mdxAmount, uint256 tokenAmount) = pendingMdxAndToken(_pid, _user);
            return (mdxAmount, tokenAmount);
        } else {
            uint256 mdxAmount = pendingMdx(_pid, _user);
            return (mdxAmount, 0);
        }
    }

    function pendingMdxAndToken(uint256 _pid, address _user) private view returns (uint256, uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMdxPerShare = pool.accMdxPerShare;
        uint256 accMultLpPerShare = pool.accMultLpPerShare;
        uint256 number = block.number > endBlock ? endBlock : block.number;
        if (user.amount > 0) {
            uint256 TokenPending = IMasterChefHeco(multLpChef).pending(poolCorrespond[_pid], address(this));
            accMultLpPerShare = accMultLpPerShare.add(TokenPending.mul(1e12).div(pool.totalAmount));
            uint256 userPending = user.amount.mul(accMultLpPerShare).div(1e12).sub(user.multLpRewardDebt);
            if (number > pool.lastRewardBlock) {
                uint256 multiplier = number.sub(pool.lastRewardBlock);
                uint256 blockReward = getMdxBlockReward();
                uint256 mdxReward = multiplier.mul(blockReward).mul(pool.allocPoint).div(totalAllocPoint);
                uint256 devGet;
                if (devReward > 0) {
                    devGet = mdxReward.div(devReward);
                }
                accMdxPerShare = accMdxPerShare.add(mdxReward.sub(devGet).mul(1e12).div(pool.totalAmount));
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
                uint256 blockReward = getMdxBlockReward();
                uint256 mdxReward = multiplier.mul(blockReward).mul(pool.allocPoint).div(totalAllocPoint);
                uint256 devGet;
                if (devReward > 0) {
                    devGet = mdxReward.div(devReward);
                }
                accMdxPerShare = accMdxPerShare.add(mdxReward.sub(devGet).mul(1e12).div(lpSupply));
                return user.amount.mul(accMdxPerShare).div(1e12).sub(user.rewardDebt);
            }
            if (number == pool.lastRewardBlock) {
                return user.amount.mul(accMdxPerShare).div(1e12).sub(user.rewardDebt);
            }
        }
        return 0;
    }

    // Deposit LP tokens to CoinChef for MDX allocation.
    function deposit(uint256 _pid, uint256 _amount) public notPause {
        PoolInfo storage pool = poolInfo[_pid];
        if (isMultLP(address(pool.lpToken))) {
            depositMdxAndToken(_pid, _amount, msg.sender);
        } else {
            depositMdx(_pid, _amount, msg.sender);
        }
    }

    function depositMdxAndToken(uint256 _pid, uint256 _amount, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pendingAmount = user.amount.mul(pool.accMdxPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingAmount > 0) {
                safeMdxTransfer(_user, pendingAmount);
            }
            uint256 beforeToken = IERC20(multLpToken).balanceOf(address(this));
            IMasterChefHeco(multLpChef).deposit(poolCorrespond[_pid], 0);
            uint256 afterToken = IERC20(multLpToken).balanceOf(address(this));
            pool.accMultLpPerShare = pool.accMultLpPerShare.add(afterToken.sub(beforeToken).mul(1e12).div(pool.totalAmount));
            uint256 tokenPending = user.amount.mul(pool.accMultLpPerShare).div(1e12).sub(user.multLpRewardDebt);
            if (tokenPending > 0) {
                IERC20(multLpToken).safeTransfer(_user, tokenPending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(_user, address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalAmount = pool.totalAmount.add(_amount);
            IMasterChefHeco(multLpChef).deposit(poolCorrespond[_pid], _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMdxPerShare).div(1e12);
        user.multLpRewardDebt = user.amount.mul(pool.accMultLpPerShare).div(1e12);
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
    function withdraw(uint256 _pid, uint256 _amount) public notPause {
        PoolInfo storage pool = poolInfo[_pid];
        if (isMultLP(address(pool.lpToken))) {
            withdrawMdxAndToken(_pid, _amount, msg.sender);
        } else {
            withdrawMdx(_pid, _amount, msg.sender);
        }
    }

    function withdrawMdxAndToken(uint256 _pid, uint256 _amount, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(user.amount >= _amount, "withdrawMdxAndToken: not good");
        updatePool(_pid);
        uint256 pendingAmount = user.amount.mul(pool.accMdxPerShare).div(1e12).sub(user.rewardDebt);
        if (pendingAmount > 0) {
            safeMdxTransfer(_user, pendingAmount);
        }
        if (_amount > 0) {
            uint256 beforeToken = IERC20(multLpToken).balanceOf(address(this));
            IMasterChefHeco(multLpChef).withdraw(poolCorrespond[_pid], _amount);
            uint256 afterToken = IERC20(multLpToken).balanceOf(address(this));
            pool.accMultLpPerShare = pool.accMultLpPerShare.add(afterToken.sub(beforeToken).mul(1e12).div(pool.totalAmount));
            uint256 tokenPending = user.amount.mul(pool.accMultLpPerShare).div(1e12).sub(user.multLpRewardDebt);
            if (tokenPending > 0) {
                IERC20(multLpToken).safeTransfer(_user, tokenPending);
            }
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            pool.lpToken.safeTransfer(_user, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMdxPerShare).div(1e12);
        user.multLpRewardDebt = user.amount.mul(pool.accMultLpPerShare).div(1e12);
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
    function emergencyWithdraw(uint256 _pid) public notPause {
        PoolInfo storage pool = poolInfo[_pid];
        if (isMultLP(address(pool.lpToken))) {
            emergencyWithdrawMdxAndToken(_pid, msg.sender);
        } else {
            emergencyWithdrawMdx(_pid, msg.sender);
        }
    }

    function emergencyWithdrawMdxAndToken(uint256 _pid, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 amount = user.amount;
        uint256 beforeToken = IERC20(multLpToken).balanceOf(address(this));
        IMasterChefHeco(multLpChef).withdraw(poolCorrespond[_pid], amount);
        uint256 afterToken = IERC20(multLpToken).balanceOf(address(this));
        pool.accMultLpPerShare = pool.accMultLpPerShare.add(afterToken.sub(beforeToken).mul(1e12).div(pool.totalAmount));
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

    // Update dev address by the previous dev.
    function dev(address _devAddress) public {
        require(msg.sender == devAddress, "dev: wut?");
        devAddress = _devAddress;
    }

    modifier notPause() {
        require(pause == true, "Mining has been suspended");
        _;
    }
}
