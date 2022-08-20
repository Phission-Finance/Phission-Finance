// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../fERC20.sol";
import "./MockOracle.sol";
import "./LPUtils.sol";

contract fERC20Test_fork is Test {
    IWETH weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    MockOracle m;
    IOracle o;
    fERC20 fS;
    fERC20 fW;

    function setUp() public {
        m = new MockOracle(false, false, false);
        o = IOracle(address(m));
        fS = new fERC20(weth, o, true);
        fW = new fERC20(weth, o, false);
    }

    function test_fork_name() public {
        assertEq(fS.name(), "Wrapped Ether POS");
        assertEq(fS.symbol(), "WETHs");
    }

    function test_transfer() public {
        fS.mint(address(this), 100 ether);
        fW.mint(address(this), 100 ether);

        fS.approve(address(this), type(uint256).max);
        fW.approve(address(this), type(uint256).max);

        uint256 amt = 1 ether;
        address to = address(1);

        // both work for transfer and transferFrom before expiry

        fS.transfer(to, amt);
        require(fS.balanceOf(to) == amt);

        fS.transferFrom(address(this), to, amt);
        require(fS.balanceOf(to) == amt * 2);

        fW.transfer(to, amt);
        require(fW.balanceOf(to) == amt);

        fW.transferFrom(address(this), to, amt);
        require(fW.balanceOf(to) == amt * 2);

        m.set(true, false, true);
        // just pow future works for transfer and transferFrom after expiry

        to = address(2);
        fS.transfer(to, amt);
        require(fS.balanceOf(to) == 0);

        fS.transferFrom(address(this), to, amt);
        require(fS.balanceOf(to) == 0);

        fW.transfer(to, amt);
        require(fW.balanceOf(to) == amt);

        fW.transferFrom(address(this), to, amt);
        require(fW.balanceOf(to) == amt * 2);

        m.set(true, true, false);
        // just pos future works for transfer and transferFrom after expiry

        to = address(3);
        fS.transfer(to, amt);
        require(fS.balanceOf(to) == amt);

        fS.transferFrom(address(this), to, amt);
        require(fS.balanceOf(to) == amt * 2);

        fW.transfer(to, amt);
        require(fW.balanceOf(to) == 0);

        fW.transferFrom(address(this), to, amt);
        require(fW.balanceOf(to) == 0);
    }

    function test_fork_uniswapPool() public {
        // weth / fW
        weth.deposit{value: 100 ether}();
        fS.mint(address(this), 100 ether);

        IUniswapV2Router02 univ2router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        weth.approve(address(univ2router), type(uint256).max);
        fS.approve(address(univ2router), type(uint256).max);

        LP l = new LP(fS, weth);
        weth.transfer(address(l), 50 ether);
        fS.transfer(address(l), 50 ether);
        l.add(50 ether, 50 ether);

        address[] memory path = new address[](2);
        path[0] = address(fS);
        path[1] = address(weth);

        address[] memory pathRev = new address[](2);
        pathRev[0] = address(weth);
        pathRev[1] = address(fS);

        univ2router.swapExactTokensForTokens(5 ether, 0, path, address(this), type(uint256).max);
        univ2router.swapExactTokensForTokens(5 ether, 0, pathRev, address(this), type(uint256).max);

        m.set(true, false, true);

        try univ2router.swapExactTokensForTokens(5 ether, 0, path, address(this), type(uint256).max) {
            revert("should fail");
        } catch {}

        l.remove();
    }
}
