pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../GovToken.sol";

contract TestGovToken is Test {
    GovToken gov;

    function setUp() public {
        gov = new GovToken();
    }

    function test_itMintsTokens() public {
        // arrange
        uint256 mintAmount = 0x1337;
        address babe = address(0xbabe);

        // act
        gov.mint(address(0xbabe), mintAmount);

        // assert
        assertEq(gov.balanceOf(babe), mintAmount, "Should have incremented babe's balance");
        assertEq(gov.totalSupply(), mintAmount, "Should have incremented total supply");
    }

    function test_itCannotMintMoreThanMaxSupply() public {
        // arrange
        uint256 mintAmount = gov.MAX_SUPPLY() + 1;

        // act
        vm.expectRevert("Amount exceeds max supply");
        gov.mint(address(this), mintAmount);
    }

    function test_itCannotMintIfSenderIsNotOwner() public {
        // act
        vm.prank(address(0xbabe));
        vm.expectRevert("Ownable: caller is not the owner");
        gov.mint(address(this), 1);
    }

    function test_itMintsTokens(uint256 wad, address to) public {
        // arrange
        wad = wad % gov.MAX_SUPPLY();
        if (address(to) == address(0)) {
            to = address(0xbabe);
        }

        // act
        gov.mint(to, wad);

        // assert
        assertEq(gov.balanceOf(to), wad, "Should have incremented to's balance");
        assertEq(gov.totalSupply(), wad, "Should have incremented total totalSupply");
    }
}
