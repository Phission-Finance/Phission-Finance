pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "./MockOracle.sol";
import "../Factory.sol";
import "../GovToken.sol";
import "./LpUtils.sol";

interface IStaking {
    function totalSupply() external view returns (uint256);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    function setRewardsDuration(uint256 _rewardsDuration) external;

    function notifyRewardAmount(uint256 reward) external;

    function exitAndSweep() external;
}

// TODO:
//      CANT USE THIS, NEED TO PLAN REWARDS TO STOP AT A CERTAIN TIME
//      POST MERGE, NEED TO ALSO MAKE TREASURY NOT REDEEM BEFORE THEN

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


    mapping(address => uint) stakers;

    function userStake(uint id, uint amt) internal {
        address user = address(uint160(uint256(keccak256(abi.encode(id)))));
        deal(address(stakeToken), user, amt);

        vm.startPrank(user, user);
        stakeToken.approve(address(staking), amt);
        staking.stake(amt);
        vm.stopPrank();

        stakers[user] += amt;
    }

    function userUnstake(uint id, bool withdraw, bool claim, bool exitAndSweep) internal {
        address user = address(uint160(uint256(keccak256(abi.encode(id)))));

        vm.startPrank(user, user);
        if (withdraw) {
            staking.withdraw(stakers[user]);
        }
        if (claim) {
            staking.getReward();
        }
        if (exitAndSweep) {
            staking.exitAndSweep();
        }
        vm.stopPrank();

        stakers[user] = 0;
    }

    function test_sweepFailsBeforeExpire() public {
        deal(address(stakeToken), address(this), 1 ether);
        skip(1 days);

        stakeToken.approve(address(staking), 1 ether);
        staking.stake(1 ether);
        skip(2 days);

        try staking.exitAndSweep() {revert("should fail");} catch {}
    }

    // leftovers = 496031746495844
    function test_manystakers_1(bool beforeSweep, uint256 seed) public {
        if (seed == 0 ||
            seed % 1 hours < 1 minutes
        ) return;

        uint endTime = block.timestamp + 7 days;

        skip(seed % (1 hours));

        console.log("a. time left", endTime - block.timestamp);

        uint users = 20;

        for (uint i = 0; i < users; i++) {
            userStake(i, 1 ether);
            skip(seed % (2 hours));
        }

        console.log("b. time left", endTime - block.timestamp);

        skip(seed % (2 days));

        console.log("EXPIRED");

        // expire oracle
        mockOracle.set(true, true, true);

        console.log("c. time left", endTime - block.timestamp);

        skip(seed % (2 days));

        console.log("d. time left", endTime - block.timestamp);

        for (uint i = 0; i < users; i++) {
            uint rand = uint(blockhash(block.number));
            bool sweep = i == (rand % users);
            userUnstake(i,
                !sweep,
                !sweep && rand % 3 == 0,
                sweep);
            skip(seed % (2 hours));
        }

        // remove all rewards
        for (uint i = 0; i < users; i++) {
            userUnstake(i,
                false,
                true,
                false);
            skip(seed % (2 hours));
        }

        console.log("rewards left", gov.balanceOf(address(staking)));

        console.log("time left", endTime - block.timestamp);

        //  seed with   1 =>    leftovers = 8267196231271
        //  seed with  1E =>    leftovers = 30924246495826

        require(gov.balanceOf(address(staking)) < 1e6, "too much dust left");
    }


    function non0rand(uint seed, uint max) internal returns (uint) {
        uint rand = seed % max;
        while (rand == 0) {rand = uint(keccak256(abi.encode(seed))) % max;}
        return rand;
    }

    // leftovers = 21056547619509784
    function test_manystakers_2(bool beforeSweep, uint256 seed) public {
        uint endTime = block.timestamp + 7 days;
        skip(non0rand(seed, 1 hours));

        uint users = 20;

        for (uint i = 0; i < users; i++) {
            userStake(i, 1 ether);
            skip(non0rand(seed, 2 hours));
        }

        console.log("a. time left", endTime - block.timestamp);


        skip(non0rand(seed, 2 days));

        console.log("b. time left", endTime - block.timestamp);

        // expire oracle
        mockOracle.set(true, true, true);
        console.log("EXPIRED");

        skip(non0rand(seed, 1 days));

        console.log("c. time left", endTime - block.timestamp);

        skip(non0rand(seed, 1 days));

        console.log("d. time left", endTime - block.timestamp);

        for (uint i = 0; i < users; i++) {
            uint rand = uint(blockhash(block.number));
            bool sweep = i == (rand % users);
            userUnstake(i,
                !sweep,
                !sweep && rand % 3 == 0,
                sweep);
            skip(non0rand(seed, 2 hours));
        }

        // remove all rewards
        for (uint i = 0; i < users; i++) {
            userUnstake(i,
                false,
                true,
                false);
            skip(non0rand(seed, 2 hours));
        }

        console.log("rewards left", gov.balanceOf(address(staking)));

        console.log("endTime, timestamp", endTime, block.timestamp);

        require(gov.balanceOf(address(staking)) < 1e6, "too much dust left");
    }


    receive() external payable {}
}
