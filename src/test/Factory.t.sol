pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "../Oracle.sol";
import "../Split.sol";
import "../Factory.sol";
import "./MockOracle.sol";

// TODO: test factory

contract SplitFactoryTest_fork is Test {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IOracle o;
    Split s;
    SplitFactory sf;

    function setUp() public {
        o = IOracle(address(new MockOracle(false, true, false)));
        s = new Split(weth, o);
        sf = new SplitFactory(o);
    }

    function test_create() public {
        // act
        address split = address(sf.create(weth));

        // assert
        assertEq(address(sf.splits(weth)), split, "Should have created split for weth");
    }

    function test_getCreatesSplitIfItDoesntExist() public {
        // act
        address split = address(sf.get(weth));

        // assert
        assertEq(address(sf.splits(weth)), split, "Should have created split for weth if it doesnt exist");
    }

    function test_createLock() public {
        // act
        address lock = address(sf.createLock(weth));

        // assert
        assertEq(address(sf.locks(weth)), lock, "Should have created lock for weth");
    }

    function test_getLockCreatesLockIfItDoesntExist() public {
        // act
        address lock = address(sf.getLock(weth));

        // assert
        assertEq(address(sf.locks(weth)), lock, "Should have created lock for weth if it doesnt exist");
    }
}
