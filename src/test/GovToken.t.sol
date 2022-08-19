pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../GovToken.sol";

contract TestGovToken is Test {
    GovToken gov;

    function setUp() public {
        gov = new GovToken();
    }

    // TODO: write tests
}
