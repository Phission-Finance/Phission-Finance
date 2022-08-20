pragma solidity ^0.5.16;

import "../lib/synthetix/contracts/StakingRewards.sol";
import "./interfaces/IOracle.sol";

contract Staking is StakingRewards {
    constructor(
        IOracle _oracle,
        address _owner,
        address _rewardsDistribution,
        address _rewardsToken,
        address _stakingToken
    )
        public
        StakingRewards(_owner, _rewardsDistribution, _rewardsToken, _stakingToken)
    {}
}
