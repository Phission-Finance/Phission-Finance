pragma solidity ^0.5.16;

import "./StakingRewards.sol";
import "./interfaces/IOracle.sol";

contract Staking is StakingRewards {
    IOracle public oracle;
    
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
    }

    function sweepLeftovers() external {
        require(oracle.isExpired());
        // uint256 rew = totalSupply().mul(rewardPerToken());
        uint256 leftover = periodFinish.sub(block.timestamp).mul(rewardRate);
        rewardsToken.safeTransfer(owner, leftover);
    }
}
