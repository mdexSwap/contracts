pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';


contract TeamTimeLock {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20 public token;
    uint constant  public PERIOD = 30 days;
    uint constant  public CYCLE_TIMES = 24;
    uint public fixedQuantity;  // Monthly rewards are fixed
    uint public startTime;
    uint public delay;
    uint public cycle;      // cycle already received
    uint public hasReward;  // Rewards already withdrawn
    address public beneficiary;
    string public introduce;

    event WithDraw(address indexed operator, address indexed to, uint amount);

    constructor(
        address _beneficiary,
        address _token,
        uint _fixedQuantity,
        uint _startTime,
        uint _delay,
        string memory _introduce
    ) public {
        require(_beneficiary != address(0) && _token != address(0), "TimeLock: zero address");
        require(_fixedQuantity > 0, "TimeLock: fixedQuantity is zero");
        beneficiary = _beneficiary;
        token = IERC20(_token);
        fixedQuantity = _fixedQuantity;
        delay = _delay;
        startTime = _startTime.add(_delay);
        introduce = _introduce;
    }


    function getBalance() public view returns (uint) {
        return token.balanceOf(address(this));
    }

    function getReward() public view returns (uint) {
        // Has ended or not started
        if (cycle >= CYCLE_TIMES || block.timestamp <= startTime) {
            return 0;
        }
        uint pCycle = (block.timestamp.sub(startTime)).div(PERIOD);
        if (pCycle >= CYCLE_TIMES) {
            return token.balanceOf(address(this));
        }
        return pCycle.sub(cycle).mul(fixedQuantity);
    }

    function withDraw() external {
        uint reward = getReward();
        require(reward > 0, "TimeLock: no reward");
        uint pCycle = (block.timestamp.sub(startTime)).div(PERIOD);
        cycle = pCycle >= CYCLE_TIMES ? CYCLE_TIMES : pCycle;
        hasReward = hasReward.add(reward);
        token.safeTransfer(beneficiary, reward);
        emit WithDraw(msg.sender, beneficiary, reward);
    }

    // Update beneficiary address by the previous beneficiary.
    function setBeneficiary(address _newBeneficiary) public {
        require(msg.sender == beneficiary, "Not beneficiary");
        beneficiary = _newBeneficiary;
    }
}
