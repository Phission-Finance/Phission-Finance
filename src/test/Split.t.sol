pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "../Oracle.sol";
import "../Split.sol";
import "../Factory.sol";
import "./MockOracle.sol";

contract SplitTest_fork is Test {
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    MockOracle o;
    Split s;

    function setUp() public {
        o = new MockOracle(false, true, false);
        s = new Split(weth, o);

        weth.approve(address(s), type(uint256).max);
    }

    function test_itInits() public {
        assertEq(address(s.oracle()), address(o), "Should have set oracle");
        assertEq(address(s.underlying()), address(weth), "Should have set weth as the underlying");
        assertTrue(address(s.future0()) != address(0), "Should have set future 0 token");
        assertTrue(address(s.future1()) != address(0), "Should have set future 1 token");
    }

    function test_itMints() public {
        // arrange
        uint256 amount = 10 ether;
        deal(address(weth), address(this), amount);
        uint256 balanceBefore = weth.balanceOf(address(this));
        uint256 contractBalanceBefore = weth.balanceOf(address(s));

        // act
        s.mint(amount);

        // assert
        assertEq(s.future0().balanceOf(address(this)), amount, "Should have minted future 0 tokens");
        assertEq(s.future1().balanceOf(address(this)), amount, "Should have minted future 1 tokens");
        assertEq(balanceBefore - weth.balanceOf(address(this)), amount, "Should have transferred amount from account");
        assertEq(
            weth.balanceOf(address(s)) - contractBalanceBefore, amount, "Should have transferred amount to contract"
        );
    }

    function test_itMintsTo() public {
        // arrange
        uint256 amount = 10 ether;
        deal(address(weth), address(this), amount);
        address to = address(0xbabe);
        uint256 balanceBefore = weth.balanceOf(address(this));
        uint256 contractBalanceBefore = weth.balanceOf(address(s));

        // act
        s.mintTo(to, amount);

        // assert
        assertEq(s.future0().balanceOf(to), amount, "Should have minted future 0 tokens to 'to'");
        assertEq(s.future1().balanceOf(to), amount, "Should have minted future 1 tokens to 'to'");
        assertEq(balanceBefore - weth.balanceOf(address(this)), amount, "Should have transferred amount from account");
        assertEq(
            weth.balanceOf(address(s)) - contractBalanceBefore, amount, "Should have transferred amount to contract"
        );
    }

    function test_itCannotMintIfOracleExpired() public {
        // arrange
        o.set(true, false, false);

        // act
        vm.expectRevert("Merge has already happened");
        s.mint(0);
    }

    function test_itCannotMintToIfOracleExpired() public {
        // arrange
        o.set(true, false, false);

        // act
        vm.expectRevert("Merge has already happened");
        s.mintTo(address(0), 0);
    }

    function test_itBurns() public {
        // arrange
        uint256 amount = 10 ether;
        deal(address(weth), address(this), amount);
        s.mint(amount);
        uint256 balanceBefore = weth.balanceOf(address(this));
        uint256 contractBalanceBefore = weth.balanceOf(address(s));
        uint256 f0BalanceBefore = s.future0().balanceOf(address(this));
        uint256 f1BalanceBefore = s.future1().balanceOf(address(this));
        uint256 burnAmount = 0.333 ether;

        // act
        s.burn(burnAmount);

        // assert
        assertEq(weth.balanceOf(address(this)) - balanceBefore, burnAmount, "Should have withdrawn eth to account");
        assertEq(
            contractBalanceBefore - weth.balanceOf(address(s)), burnAmount, "Should have withdrawn eth from contract"
        );
        assertEq(
            f0BalanceBefore - s.future0().balanceOf(address(this)),
            burnAmount,
            "Should have burned future 0 token from account"
        );
        assertEq(
            f1BalanceBefore - s.future1().balanceOf(address(this)),
            burnAmount,
            "Should have burned future 1 token from account"
        );
    }

    function test_itCannotBurnIfOracleIsExpired() public {
        // arrange
        o.set(true, false, false);

        // act
        vm.expectRevert("Merge has already happened");
        s.burn(0);
    }

    function test_itRedeemsFuture0Tokens() public {
        // arrange
        uint256 amount = 10 ether;
        deal(address(weth), address(this), amount);
        s.mint(amount);
        o.set(true, true, false);
        uint256 redeemAmount = 0.333 ether;
        uint256 balanceBefore = weth.balanceOf(address(this));
        uint256 contractBalanceBefore = weth.balanceOf(address(s));
        uint256 f0BalanceBefore = s.future0().balanceOf(address(this));

        // act
        s.redeem(redeemAmount);

        // assert
        assertEq(
            f0BalanceBefore - s.future0().balanceOf(address(this)),
            redeemAmount,
            "Should have burned future 0 tokens from account"
        );
        assertEq(weth.balanceOf(address(this)) - balanceBefore, redeemAmount, "Should have sent weth to account");
    }

    function test_itRedeemsFuture1Tokens() public {
        // arrange
        uint256 amount = 10 ether;
        deal(address(weth), address(this), amount);
        s.mint(amount);
        o.set(true, false, true);
        uint256 redeemAmount = 0.333 ether;
        uint256 balanceBefore = weth.balanceOf(address(this));
        uint256 contractBalanceBefore = weth.balanceOf(address(s));
        uint256 f1BalanceBefore = s.future1().balanceOf(address(this));

        // act
        s.redeem(redeemAmount);

        // assert
        assertEq(
            f1BalanceBefore - s.future1().balanceOf(address(this)),
            redeemAmount,
            "Should have burned future 1 tokens from account"
        );
        assertEq(weth.balanceOf(address(this)) - balanceBefore, redeemAmount, "Should have sent weth to account");
    }

    function test_itCannotRedeemIfOracleIsNotExpired() public {
        // arrange
        o.set(false, false, false);

        // act
        vm.expectRevert("Merge has not happened yet");
        s.redeem(0);
    }
}
