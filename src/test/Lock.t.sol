pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../Factory.sol";
import "./MockOracle.sol";

contract TestLock_fork is Test {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    MockOracle o;
    Lock l;

    function setUp() public {
        o = new MockOracle(false, true, false);
        l = new Lock(weth, o);

        weth.approve(address(l), type(uint256).max);
    }

    function test_lockIncrementsBalance() public {
        // arrange
        uint256 amount = 1 ether;
        deal(address(weth), address(this), amount);

        // act
        l.lock(amount);

        // assert
        assertEq(l.balances(address(this)), amount, "Should have incremented balance");
    }

    function test_lockSendsWethFromSenderToContract() public {
        // arrange
        uint256 amount = 2 ether;
        deal(address(weth), address(this), amount);
        uint256 lockAmount = 0.15 ether;

        // act
        l.lock(lockAmount);

        // assert
        assertEq(amount - weth.balanceOf(address(this)), lockAmount, "Should have sent weth from account");
        assertEq(weth.balanceOf(address(l)), lockAmount, "Should have sent weth to contract");
    }

    function test_itCannotLockIfOracleIsExpired() public {
        // arrange
        o.set(true, false, false);
        uint256 amount = 1 ether;
        deal(address(weth), address(this), amount);

        // act
        vm.expectRevert("Merge has already happened");
        l.lock(amount);
    }

    function test_unlockDecrementsBalance() public {
        // arrange
        uint256 amount = 1 ether;
        deal(address(weth), address(this), amount);
        l.lock(amount);
        o.set(true, false, false);
        uint256 unlockAmount = 0.05 ether;

        // act
        l.unlock(unlockAmount);

        // assert
        assertEq(l.balances(address(this)), amount - unlockAmount, "Should have decremented sender's balance");
    }

    function test_unlockTransfersWethBackToSenderFromContract() public {
        // arrange
        uint256 amount = 1 ether;
        deal(address(weth), address(this), amount);
        l.lock(amount);
        o.set(true, false, false);
        uint256 unlockAmount = 0.05 ether;

        // act
        l.unlock(unlockAmount);

        // assert
        assertEq(weth.balanceOf(address(this)), unlockAmount, "Should have sent weth to account");
        assertEq(weth.balanceOf(address(l)), amount - unlockAmount, "Should have sent weth from contract");
    }
}
