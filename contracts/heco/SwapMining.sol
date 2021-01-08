pragma solidity >=0.5.0 <0.7.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../interface/IERC20.sol";
import "../library/SafeMath.sol";
import "../interface/IMdexFactory.sol";
import "../interface/IMdexPair.sol";
import "../interface/IMdx.sol";


contract SwapMining is Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _whitelist;

    //每个区块产出mdx的数量
    uint256 public mdxPerBlock;
    //开始区块
    uint256 public startBlock;
    //多少个区块开始减半
    uint256 public halvingPeriod = 1728000;
    //减半的周期
    uint256 public halvingTimes;
    //总权重
    uint256 public totalAllocPoint = 0;
    address public router;
    IMdexFactory public factory;
    IMdx public mdx;
    //计算价格的锚定代币
    address public targetToken;
    //pair对应的池子pid
    mapping(address => uint256) public pairOfPid;

    constructor(
        IMdx _mdx,
        IMdexFactory _factory,
        address _router,
        address _token,
        uint256 _mdxPerBlock,
        uint256 _startBlock
    ) public {
        mdx = _mdx;
        factory = _factory;
        router = _router;
        targetToken = _token;
        mdxPerBlock = _mdxPerBlock;
        startBlock = _startBlock;
    }

    struct UserInfo {
        uint256 quantity;   //用户当前金额
        uint256 blockNumber;    //上次交易的区块
    }

    struct PoolInfo {
        address pair;           //可以交易挖矿的交易对地址
        uint256 quantity;       //当前池子的交易量
        uint256 totalQuantity;  //历史总交易量
        uint256 allocPoint;     //当前池子的权重
        uint256 allocMdxAmount; //当前池子所拥有的mdx数量
        uint256 lastRewardBlock;//池子上次更新的区块
    }

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    //池子的数量
    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }


    //添加可以挖矿的交易对
    function addPair(uint256 _allocPoint, address _pair, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massMintPools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        pair : _pair,
        quantity : 0,
        totalQuantity : 0,
        allocPoint : _allocPoint,
        allocMdxAmount : 0,
        lastRewardBlock : lastRewardBlock
        }));
        pairOfPid[_pair] = poolLength() - 1;
    }

    //更新池子的权重
    function setPair(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massMintPools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    //设置每个区块产出mdx的数量
    function setMdxPerBlock(uint256 _newPerBlock) public onlyOwner {
        massMintPools();
        mdxPerBlock = _newPerBlock;
    }

    //添加白名单  只有在白名单的token 才可以添加交易挖矿
    function addWhitelist(address _addToken) public onlyOwner returns (bool) {
        require(_addToken != address(0), "SwapMining: token is the zero address");
        return EnumerableSet.add(_whitelist, _addToken);
    }

    function delWhitelist(address _delToken) public onlyOwner returns (bool) {
        require(_delToken != address(0), "SwapMining: token is the zero address");
        return EnumerableSet.remove(_whitelist, _delToken);
    }

    function getWhitelistLength() public view returns (uint256) {
        return EnumerableSet.length(_whitelist);
    }

    function isWhitelist(address _token) public view returns (bool) {
        return EnumerableSet.contains(_whitelist, _token);
    }

    function getWhitelist(uint256 _index) public view returns (address){
        require(_index <= getWhitelistLength() - 1, "SwapMining: index out of bounds");
        return EnumerableSet.at(_whitelist, _index);
    }

    //设置新的减半区块数量
    function setHalvingPeriod(uint256 _block) public onlyOwner {
        halvingPeriod = _block;
    }

    //设置新的减半周期
    function setHalvingTimes(uint256 _cycle) public onlyOwner {
        halvingTimes = _cycle;
    }

    function setRouter(address newRouter) public onlyOwner {
        require(newRouter != address(0), "SwapMining: new router is the zero address");
        router = newRouter;
    }

    function setFactory(IMdexFactory newFactory) public onlyOwner {
        require(address(newFactory) != address(0), "SwapMining: new factory is the zero address");
        factory = newFactory;
    }

    function setTargetToken(address _targetToken) public onlyOwner {
        require(_targetToken != address(0), "SwapMining: new targetToken is the zero address");
        require(isWhitelist(_targetToken), "SwapMining: illegal targetToken");
        targetToken = _targetToken;
    }

    //判断是否减半,在哪个周期
    function phase(uint256 blockNumber) public view returns (uint256) {
        if (halvingPeriod == 0) {
            return 0;
        }
        if (blockNumber > startBlock) {
            return (blockNumber.sub(startBlock).sub(1)).div(halvingPeriod);
        }
        return 0;
    }

    function phase() public view returns (uint256) {
        return phase(block.number);
    }

    //当前区块所获得的奖励
    function reward(uint256 blockNumber) public view returns (uint256) {
        uint256 _phase = phase(blockNumber);
        if (_phase > halvingTimes) {
            return 0;
        }
        return mdxPerBlock.div(2 ** _phase);
    }

    function reward() public view returns (uint256) {
        return reward(block.number);
    }

    //池子当前可以获取的奖励
    function getMdxReward(uint256 _lastRewardBlock) public view returns (uint256) {
        uint256 blockReward = 0;
        uint256 n = phase(_lastRewardBlock);
        uint256 m = phase(block.number);
        //如果经历了多个周期
        while (n < m) {
            n++;
            //获取最后一个周期的最后一个区块
            uint256 r = n.mul(halvingPeriod).add(startBlock);
            //获取之前周期的奖励
            blockReward = blockReward.add((r.sub(_lastRewardBlock)).mul(reward(r)));
            _lastRewardBlock = r;
        }
        blockReward = blockReward.add((block.number.sub(_lastRewardBlock)).mul(reward(block.number)));
        return blockReward;
    }

    //更新所有的池子 在更新权重和设置新的出块数量时候调用
    function massMintPools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            mint(pid);
        }
    }

    function mint(uint256 _pid) public returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return false;
        }
        uint256 blockReward = getMdxReward(pool.lastRewardBlock);
        if (blockReward <= 0) {
            return false;
        }
        //根据权重计算池子所获得的奖励
        uint256 mdxReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        mdx.mint(address(this), mdxReward);
        //增加当前池子拥有的代币数量
        pool.allocMdxAmount = pool.allocMdxAmount.add(mdxReward);
        pool.lastRewardBlock = block.number;
        return true;
    }

    //交易挖矿  只能由router调用
    function swap(address account, address input, address output, uint256 amount) public onlyRouter returns (bool) {
        require(account != address(0), "SwapMining: taker swap account is the zero address");
        require(input != address(0), "SwapMining: taker swap input is the zero address");
        require(output != address(0), "SwapMining: taker swap output is the zero address");

        if (poolLength() <= 0) {
            return false;
        }

        if (!isWhitelist(input) || !isWhitelist(output)) {
            return false;
        }

        //计算当前交易对的pair
        address pair = IMdexFactory(factory).pairFor(address(factory), input, output);

        PoolInfo storage pool = poolInfo[pairOfPid[pair]];
        //如果不存在或者权重为0则返回
        if (pool.pair != pair || pool.allocPoint <= 0) {
            return false;
        }

        uint256 price = getPrice(output, targetToken);
        if (price <= 0) {
            return false;
        }
        uint256 quantity = price.mul(amount).div(10 ** uint256(IERC20(targetToken).decimals()));

        mint(pairOfPid[pair]);

        pool.quantity = pool.quantity.add(quantity);
        pool.totalQuantity = pool.totalQuantity.add(quantity);
        UserInfo storage user = userInfo[pairOfPid[pair]][account];
        user.quantity = user.quantity.add(quantity);
        user.blockNumber = block.number;
        return true;
    }

    //用户提取所有的池子的交易奖励
    function takerWithdraw() public {
        uint256 userSub;
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][msg.sender];
            if (user.quantity > 0) {
                //用户资产大于零 更新池子获取最新可获得的奖励
                mint(pid);
                //用户在这个池子里所占有的奖励
                userSub = userSub.add(pool.allocMdxAmount.mul(user.quantity).div(pool.quantity));
                pool.quantity = pool.quantity.sub(user.quantity);
                pool.allocMdxAmount = pool.allocMdxAmount.sub(userSub);
                user.quantity = 0;
                user.blockNumber = block.number;
            }
        }
        if (userSub <= 0) {
            return;
        }
        mdx.transfer(msg.sender, userSub);
    }

    //获取用户在当前池子的奖励
    function getUserReward(uint256 _pid) public view returns (uint256, uint256, uint256){
        require(_pid <= poolInfo.length - 1, "SwapMining: Not find this pool");
        uint256 userSub;
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][msg.sender];
        if (user.quantity > 0) {
            uint256 blockReward = getMdxReward(pool.lastRewardBlock);
            uint256 mdxReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
            userSub = userSub.add((pool.allocMdxAmount.add(mdxReward)).mul(user.quantity).div(pool.quantity));
        }
        //pid, 用户所能获取的mdx, 用户交易的金额
        return (_pid, userSub, user.quantity);
    }

    //获取池子的详情
    function getPoolList(uint256 _pid) public view returns (uint256, address, address, uint256, uint256, uint256){
        require(_pid <= poolInfo.length - 1, "SwapMining: Not find this pool");
        PoolInfo memory pool = poolInfo[_pid];
        address token0 = IMdexPair(pool.pair).token0();
        address token1 = IMdexPair(pool.pair).token1();
        //pid,token0,token1,池子剩余奖励,池子总交易额
        return (_pid, token0, token1, pool.allocMdxAmount, pool.totalQuantity, pool.allocPoint);
    }

    modifier onlyRouter() {
        require(msg.sender == router, "SwapMining: caller is not the router");
        _;
    }

    function getPrice(address token, address anchorToken) public view returns (uint256) {
        uint256 price = 0;
        uint256 anchorDecimal = 10 ** uint256(IERC20(anchorToken).decimals());
        uint256 baseDecimal = 10 ** uint256(IERC20(token).decimals());
        if (anchorToken == token) {
            price = anchorDecimal;
        } else if (IMdexFactory(factory).getPair(token, anchorToken) != address(0)) {
            price = IMdexPair(IMdexFactory(factory).getPair(token, anchorToken)).price(token, baseDecimal);
        } else {
            uint256 length = getWhitelistLength();
            for (uint256 index = 0; index < length; index++) {
                address base = getWhitelist(index);
                if (IMdexFactory(factory).getPair(token, base) != address(0) && IMdexFactory(factory).getPair(base, anchorToken) != address(0)) {
                    uint256 decimal = 10 ** uint256(IERC20(base).decimals());
                    uint256 price0 = IMdexPair(IMdexFactory(factory).getPair(token, base)).price(token, baseDecimal);
                    uint256 price1 = IMdexPair(IMdexFactory(factory).getPair(base, anchorToken)).price(base, decimal);
                    price = price0.mul(price1).div(decimal);
                    break;
                }
            }
        }
        return price;
    }

}
