pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "./MockOracle.sol";
import "../Factory.sol";
import "../GovToken.sol";
import "./LpUtils.sol";

interface IStaking {
    function totalSupply() external view returns (uint256);

    function stake(uint256 amount) external;

    function getReward() external;

    function setRewardsDuration(uint256 _rewardsDuration) external;

    function notifyRewardAmount(uint256 reward) external;

    function exitAndSweep() external;
}

contract StakingTest_fork is Test {
    IWETH weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IStaking staking;
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

        uint8 nonce = 5;

        address predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), address(this), bytes1(nonce))))));

        deal(address(stakeToken), address(this), 1);
        stakeToken.approve(predicted, type(uint256).max);

        staking = IStaking(
            deployCode(
                "Staking.sol:Staking", abi.encode(mockOracle, address(this), address(this), rewardToken, address(stakeToken))
            )
        );

        uint256 rewardsAmount = 5 ether;
        deal(address(gov), address(this), rewardsAmount);
        gov.transfer(address(staking), rewardsAmount);
        staking.notifyRewardAmount(rewardsAmount);
    }

    function testStart_stake(bool beforeSweep, uint256 delay1, uint256 delay2, uint256 delay3) public {
        emit log_named_uint("total supply", staking.totalSupply());
        deal(address(stakeToken), address(this), 1 ether);

        skip(delay1 % (1 days));

        stakeToken.approve(address(staking), 1 ether);
        staking.stake(1 ether);
        emit log_named_uint("total supply", staking.totalSupply());

        uint256 a = delay2 % (2 days);

        skip(1 days + a);

        vm.startPrank(address(123), address(123));

        deal(address(stakeToken), address(123), 1 ether);
        stakeToken.approve(address(staking), 1 ether);
        staking.stake(1 ether);

        vm.stopPrank();

        emit log_named_uint("total supply", staking.totalSupply());

        skip(3 days - a);

        mockOracle.set(true, true, true);

        if (beforeSweep) {
            vm.startPrank(address(123), address(123));
            staking.getReward();
            vm.stopPrank();
        }

        staking.exitAndSweep();

        if (!beforeSweep) {
            skip(delay3 % (1 days));

            vm.startPrank(address(123), address(123));
            staking.getReward();
            vm.stopPrank();
        }

        console.log("rewards left", gov.balanceOf(address(staking)));

        require(gov.balanceOf(address(staking)) < 1e6, "too much dust left");
    }

    receive() external payable {}
}
