pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../Oracle.sol";

contract ForkOracleTest is Test {
    ForkOracle oracle;

    function setUp() public {
        oracle = new ForkOracle();
    }

    function test_isExpired() public {
        require(!oracle.isExpired());
    }

    function test_pos_isExpired() public {
        require(oracle.isExpired());
    }

    function test_pow_isExpired() public {
        require(oracle.isExpired());
    }

    function test_pos_redeemable() public {
        require(oracle.isPoS() && oracle.isExpired());
    }

    function test_pow_redeemable() public {
        require(oracle.isPoWFork() && oracle.isExpired());
    }
}
