pragma solidity ^0.5.16;

import "./StakingRewards.sol";
import "./interfaces/IOracle.sol";

import "../lib/forge-std/src/console.sol";

contract Staking is StakingRewards {
    IOracle public oracle;
    bool public leftoversSwept;

    constructor(
        IOracle _oracle,
        address _owner,
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken
    )
    public
    StakingRewards(_owner, _rewardsDistribution, _rewardsToken, _stakingToken)
    {
        oracle = _oracle;
        stake(1);
        // stake 1 wei to track dust
    }

    function sweepLeftovers() internal {
        require(oracle.isExpired());

        uint leftover = periodFinish.sub(block.timestamp).mul(rewardRate);
        uint dust = earned(address(this));

        rewardsToken.safeTransfer(owner, leftover + dust);
        leftoversSwept = true;
    }

    function exitAndSweep() external {
        if (!leftoversSwept) sweepLeftovers();

        withdraw(balanceOf(msg.sender));
        getReward();
    }
}
