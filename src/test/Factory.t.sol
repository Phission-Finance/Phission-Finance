pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../Oracle.sol";
import "../Split.sol";
import "./MockOracle.sol";

// TODO: test factory

contract SplitTest_fork is Test {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IOracle o;
    Split s;

    function setUp() public {
        o = IOracle(address(new MockOracle(false, true, false)));
        s = new Split(weth, o);
    }
}
