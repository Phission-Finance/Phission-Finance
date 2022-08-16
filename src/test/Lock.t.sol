pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../Factory.sol";
import "./MockOracle.sol";

// TODO: test lock

contract TestLock is Test {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    MockOracle o;
    Lock s;

    function setUp() public {
        o = new MockOracle(false, true, false);
        s = new Lock(weth, o);
    }

    function test_fork_lock() public {

    }
}
