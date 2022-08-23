pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../Factory.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../lib/utils/IWETH.sol";
import "../../lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "../../lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../../lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract WethLp is Test {
    IUniswapV2Factory univ2fac = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Router02 univ2router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    IERC20 public t0;
    IERC20 public t1;

    IWETH weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    LP public lp;

    IUniswapV2Pair public pool;

    constructor(SplitFactory sf) payable {
        uint256 amt = msg.value;
        weth.deposit{value: amt}();

        Split s = sf.splits(weth);
        (t0, t1) = s.futures();

        weth.approve(address(s), type(uint256).max);
        s.mint(amt);

        lp = new LP(t0, t1);
        t0.transfer(address(lp), amt);
        t1.transfer(address(lp), amt);
        lp.add(amt / 4, amt / 4);

        pool = IUniswapV2Pair(univ2fac.getPair(address(t0), address(t1)));

        print_price();
    }

    function print_price() public {
        (uint112 res0, uint112 res1,) = pool.getReserves();
        emit log_named_uint("=== res0", res0);
        emit log_named_uint("=== res1", res1);
        emit log_named_uint("=== price 1/0 (bps)", 10000 * res1 / res0);
        emit log_named_uint("=== price 0/1 (bps)", 10000 * res0 / res1);
    }

    function trade(uint256 amt, bool buy) public {
        lp.trade(amt, buy);
    }

    function sendAllTo(address who) public {
        lp.sendAllTo(who);
    }

    function sendTo(address who, uint256 wad) public {
        lp.sendTo(who, wad);
    }
}

contract SplitLp is Test {
    IUniswapV2Factory univ2fac = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Router02 univ2router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    IERC20 token;
    Split public s;
    IERC20 public t0;
    IERC20 public t1;

    LP public lp;

    IUniswapV2Pair public pool;

    constructor(SplitFactory sf, IERC20 _token) {
        s = sf.get(_token);
        (t0, t1) = s.futures();
        token = _token;
    }

    function add(uint256 amt) public {
        token.approve(address(s), type(uint256).max);
        s.mint(amt);

        lp = new LP(t0, t1);
        t0.transfer(address(lp), amt);
        t1.transfer(address(lp), amt);
        lp.add(amt, amt);

        pool = IUniswapV2Pair(univ2fac.getPair(address(t0), address(t1)));
    }

    function trade(uint256 amt, bool buy) public {
        lp.trade(amt, buy);
    }

    function sendAllTo(address who) public {
        lp.sendAllTo(who);
    }

    function sendTo(address who, uint256 wad) public {
        lp.sendTo(who, wad);
    }
}

contract LP is Test {
    IUniswapV2Pair public pool;

    IUniswapV2Factory univ2fac = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Router02 univ2router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IERC20 public token0;
    IERC20 public token1;

    constructor(IERC20 _token0, IERC20 _token1) {
        (token0, token1) = (_token0, _token1);
        token0.approve(address(univ2router), type(uint256).max);
        token1.approve(address(univ2router), type(uint256).max);
    }

    function add(uint256 amt0, uint256 amt1) public {
        univ2router.addLiquidity(address(token0), address(token1), amt0, amt1, 0, 0, address(this), type(uint256).max);

        pool = IUniswapV2Pair(univ2fac.getPair(address(token0), address(token1)));

        emit log_named_uint("amt0", amt0);
        emit log_named_uint("amt1", amt1);
        emit log_named_uint(" pool.balanceOf", pool.balanceOf(address(this)));
        emit log_named_uint(" pool.totalSupply()", pool.totalSupply());
    }

    function remove() public {
        IUniswapV2Pair pair = IUniswapV2Pair(univ2fac.getPair(address(token0), address(token1)));
        uint256 liq = pair.balanceOf(address(this));

        pair.approve(address(univ2router), type(uint256).max);

        univ2router.removeLiquidity(address(token0), address(token1), liq, 0, 0, address(this), type(uint256).max);
    }

    function trade(uint256 amt, bool buy) public {
        address[] memory path = new address[](2);
        (path[0], path[1]) = buy ? (address(token0), address(token1)) : (address(token1), address(token0));

        univ2router.swapExactTokensForTokens(amt, 0, path, address(this), type(uint256).max);
    }

    function sendAllTo(address who) public {
        pool.transfer(who, pool.balanceOf(address(this)));
    }

    function sendTo(address who, uint256 wad) public {
        pool.transfer(who, wad);
    }
}
