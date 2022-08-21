pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "./MockOracle.sol";
import "../Factory.sol";
import "../GovToken.sol";
import "./LpUtils.sol";

interface IStakingRewards {
    function totalSupply() external view returns (uint256);

    function stake(uint256 amount) external;

    function getReward() external;

    function setRewardsDuration(uint256 _rewardsDuration) external;

    function notifyRewardAmount(uint256 reward) external;

    function sweepLeftovers() external;
}

contract StakingTest_fork is Test {
    IWETH weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IStakingRewards staking;
    SplitFactory sf;
    MockOracle mockOracle;
    GovToken gov;
    // TODO: use correct token
    GovToken stakeToken;

    function setUp() public {
        mockOracle = new MockOracle(false, true, false);
        sf = new SplitFactory(mockOracle);
        sf.create(weth);
        gov = new GovToken();
        stakeToken = new GovToken();

        address rewardToken = address(gov);

        staking = IStakingRewards(
            deployCode(
                "Staking.sol:Staking",
                abi.encode(
                    mockOracle,
                    address(this),
                    address(this),
                    rewardToken,
                    address(stakeToken)
                )
            )
        );

        uint256 rewardsAmount = 5 ether;
        deal(address(gov), address(this), rewardsAmount);
        gov.transfer(address(staking), rewardsAmount);
        staking.notifyRewardAmount(rewardsAmount);
    }

    function testStart_stake() public {
        emit log_named_uint("total supply", staking.totalSupply());
        deal(address(stakeToken), address(this), 1 ether);

        stakeToken.approve(address(staking), 1 ether);
        staking.stake(1 ether);
        emit log_named_uint("total supply", staking.totalSupply());

        vm.startPrank(address(123), address(123));
        deal(address(stakeToken), address(123), 1 ether);
        stakeToken.approve(address(staking), 1 ether);
        staking.stake(1 ether);

        vm.stopPrank();

        emit log_named_uint("total supply", staking.totalSupply());

        skip(5 days);

        console.log(
            "rewards bal after 5 days",
            gov.balanceOf(address(staking))
        );

        staking.getReward();

        vm.startPrank(address(123), address(123));
        staking.getReward();
        vm.stopPrank();

        console.log(
            "rewards after claiming rewards after 5 days",
            gov.balanceOf(address(staking))
        );

        mockOracle.set(true, true, true);
        staking.sweepLeftovers();
        console.log(
            "rewards after claiming rewards after 5 days",
            gov.balanceOf(address(staking))
        );
        assertTrue(gov.balanceOf(address(staking)) == 0, "dust remaining!");
    }

    receive() external payable {}
}
