pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../Treasury.sol";
import "./LPUtils.sol";
import "./MockOracle.sol";
import "./MockUniswapV2SlidingOracle.sol";
import "./CheatCodes.sol";

contract TreasuryTest_fork is Test {
    Treasury treasury;
    GovToken gov;
    IOracle o;
    SplitFactory sf;
    Split s;
    fERC20 f0;
    fERC20 f1;

    WethLp lp;
    IUniswapV2Pair pool;

    MockUniswapV2SlidingOracle uniswapOracle;

    Split lpSplit;
    fERC20 lp0;
    fERC20 lp1;

    SplitLp govlp;
    SplitLp lpLp;

    IWETH weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2Factory univ2fac = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Router02 univ2router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function setUp() public {
        emit log_string("ssss1");

        o = IOracle(address(new MockOracle(false, true, false)));
        sf = new SplitFactory(o);
        s = sf.create(weth);
        (f0, f1) = s.futures();

        emit log_named_uint("ssss2", address(this).balance);

        lp = new WethLp{value : 40 ether}(sf);
        emit log_string("ssss");

        pool = IUniswapV2Pair(univ2fac.getPair(address(f0), address(f1)));

        gov = new GovToken();

        gov.mint(address(this), 10 ether);

        govlp = new SplitLp(sf, gov);
        gov.transfer(address(govlp), 10 ether);
        govlp.add(10 ether);

        univ2fac.createPair(address(gov), address(weth));

        lpSplit = sf.create(IERC20(address(pool)));
        lpLp = new SplitLp(sf, IERC20(address(pool)));
        (lp0, lp1) = lpSplit.futures();

        lp.sendTo(address(lpLp), 1 ether);
        lpLp.add(1 ether);

        uniswapOracle = new MockUniswapV2SlidingOracle(address(univ2fac), 6 hours, 6);
        require(address(uniswapOracle) != address(0));

        treasury = new Treasury(sf, univ2fac, univ2router, gov, uniswapOracle, weth);
        govlp.sendAllTo(address(treasury));

        weth.deposit{value: 20 ether}();
        weth.approve(address(s), type(uint256).max);
        s.mint(20 ether);
    }

    receive() external payable {}

    // REDEEM
    function failTest_redeem() public {
        f0.transfer(address(treasury), 1 ether);
        f1.transfer(address(treasury), 1 ether);
        gov.mint(address(this), 1 ether);

        uint256 bal0 = f0.balanceOf(address(this));
        uint256 bal1 = f1.balanceOf(address(this));

        gov.approve(address(treasury), type(uint256).max);
        treasury.redeem(1 ether);
    }

    function test_redeem(bool token0, uint256 treasuryTokens) public {
        MockOracle(address(o)).set(false, token0, !token0);

        uint256 trAmt0 = 3 ether;
        uint256 trAmt1 = 2 ether;

        f0.transfer(address(treasury), trAmt0);
        f1.transfer(address(treasury), trAmt1);

        gov.mint(address(treasury), treasuryTokens % (gov.MAX_SUPPLY() - gov.totalSupply()));
        gov.mint(address(this), 1 ether);
        gov.mint(address(1), 1 ether);

        uint256 bal = address(this).balance;

        gov.approve(address(treasury), type(uint256).max);

        MockOracle(address(o)).set(true, token0, !token0);

        uint256 ethBal = address(this).balance;
        treasury.redeem(1 ether);

        require(address(this).balance - bal == (token0 ? trAmt0 : trAmt1) / 2, "rev 1");
    }

    function test_redeem_allAssets(bool token0) public {
        uint256 excessPhiFuts;

        MockOracle(address(o)).set(false, token0, !token0);

        f0.transfer(address(treasury), 1 ether);

        gov.mint(address(treasury), 0.5 ether);

        LP govEthLp = new LP(gov, weth);
        gov.mint(address(govEthLp), 1 ether);
        weth.deposit{value: 3 ether}();
        weth.transfer(address(treasury), 1 ether);
        address(treasury).call{value: 1 ether}("");

        weth.transfer(address(govEthLp), 2 ether);
        govEthLp.add(1 ether, 2 ether);
        govEthLp.sendAllTo(address(treasury));

        lpLp.sendTo(address(treasury), 0.1 ether);

        lp.sendTo(address(this), 1 ether);
        pool.approve(address(lpSplit), type(uint256).max);
        lpSplit.mint(1 ether);
        lp0.transfer(address(treasury), 1 ether);

        gov.mint(address(this), 1 ether);
        gov.approve(address(treasury), type(uint256).max);

        MockOracle(address(o)).set(true, token0, !token0);

        emit log_named_uint("address(treasury).balance", address(treasury).balance);

        uint256 ethBal = address(this).balance;
        treasury.redeem(1 ether);

        emit log_named_uint("lpLp.pool().balanceOf(address(treasury))", lpLp.pool().balanceOf(address(treasury)));
        emit log_named_uint("govlp.pool().balanceOf(address(treasury))", govlp.pool().balanceOf(address(treasury)));
        emit log_named_uint(
            "govEthLp.pool().balanceOf(address(treasury))", govEthLp.pool().balanceOf(address(treasury))
            );
        emit log_named_uint("lp.pool().balanceOf(address(treasury))", lp.pool().balanceOf(address(treasury)));
        emit log_named_uint("weth.balanceOf(address(treasury))", weth.balanceOf(address(treasury)));
        emit log_named_uint("address(treasury).balance", address(treasury).balance);

        require(lpLp.pool().balanceOf(address(treasury)) == 0, "lpLp.pool().balanceOf(address(treasury)) != 0");
        require(govlp.pool().balanceOf(address(treasury)) == 0, "govlp.pool().balanceOf(address(treasury)) != 0");
        require(govEthLp.pool().balanceOf(address(treasury)) == 0, "govEthLp.pool().balanceOf(address(treasury)) != 0");
        require(lp.pool().balanceOf(address(treasury)) == 0, "lp.pool().balanceOf(address(treasury)) != 0");
        require(weth.balanceOf(address(treasury)) == 0, "weth.balanceOf(address(treasury)) != 0");
        require(address(treasury).balance == 0, "address(treasury).balance != 0");
    }

    function approxEq(uint256 a, uint256 b) internal returns (bool) {
        emit log_named_uint("approxEq  a", a);
        emit log_named_uint("approxEq  b", b);

        uint256 prec = 1e10;
        return a == b || ((a > b ? a - b : b - a) * prec) / (a + b) == 0;
    }

    function test_convertToLp_failsoutofwindow(bool token0) public {
        MockOracle(address(o)).set(false, token0, !token0);

        (uint256 trAmt0, uint256 trAmt1) = token0 ? (3 ether, 2 ether) : (2 ether, 3 ether);

        f0.transfer(address(treasury), trAmt0);
        f1.transfer(address(treasury), trAmt1);

        try treasury.convertToLp() {
            revert("should fail out of window");
        } catch {}
    }

    // TO LP
    function test_convertToLp(bool token0, bool isImbalanced, bool imbalanceDirection) public {
        MockOracle(address(o)).set(false, token0, !token0);

        if (isImbalanced) {
            lp.trade(10 ether, imbalanceDirection);
        }

        emit log_string("updated prices:");
        lp.print_price();

        (uint256 trAmt0, uint256 trAmt1) = token0 ? (1e16, 1e15) : (1e15, 1e16);

        f0.transfer(address(treasury), trAmt0);
        f1.transfer(address(treasury), trAmt1);

        treasury.intendConvertToLp();
        vm.warp(block.timestamp + 8 hours);

        (uint256 res0, uint256 res1,) = lp.pool().getReserves();

        uint256 tbal0Before = f0.balanceOf(address(treasury));
        uint256 tbal1Before = f1.balanceOf(address(treasury));
        uint256 lbalBefore = pool.balanceOf(address(this));
        uint256 ltbalBefore = pool.balanceOf(address(treasury));

        uniswapOracle.set(lp.pool().token0(), lp.pool().token1(), (res1 << 112) / res0, (res0 << 112) / res1);

        treasury.convertToLp();

        uint256 tbal0After = f0.balanceOf(address(treasury));
        uint256 tbal1After = f1.balanceOf(address(treasury));
        uint256 lbalAfter = pool.balanceOf(address(this));
        uint256 ltbalAfter = pool.balanceOf(address(treasury));

        emit log_named_uint("tbal0Before", tbal0Before);
        emit log_named_uint("tbal1Before", tbal1Before);
        emit log_named_uint("ltbalBefore", ltbalBefore);
        emit log_named_uint("lbalBefore", lbalBefore);
        emit log_named_uint("tbal0After", tbal0After);
        emit log_named_uint("tbal1After", tbal1After);
        emit log_named_uint("ltbalAfter", ltbalAfter);
        emit log_named_uint("lbalAfter", lbalAfter);

        // TODO: reduce dust in check after using PRBmath
        require(tbal0After <= 10, "rev 0");
        require(tbal1After <= 10, "rev 1");
        require(ltbalBefore < ltbalAfter, "rev 2");
        require(lbalBefore < lbalAfter, "rev 3");
    }

    // todo: more tests on this
    function test_convertToLpWithLP2sw(
        bool token0,
        bool isImbalanced,
        bool imbalanceDirection,
        bool lpTokn0,
        bool lpImbalance
    )
        public
    {
        MockOracle(address(o)).set(false, token0, !token0);

        if (isImbalanced) {
            lp.trade(10 ether, imbalanceDirection);
        }

        emit log_string("updated prices:");
        lp.print_price();

        (uint256 trAmt0, uint256 trAmt1) = token0 ? (1e16, 1e15) : (1e15, 1e16);

        f0.transfer(address(treasury), trAmt0);
        f1.transfer(address(treasury), trAmt1);

        emit log_string(">>");

        lp.sendTo(address(this), 2 ether);
        emit log_string(">>");
        pool.approve(address(lpSplit), type(uint256).max);
        emit log_string(">>");
        lpSplit.mint(2 ether);
        emit log_string(">>");
        (lpTokn0 ? lp0 : lp1).transfer(address(treasury), 0.01 ether);
        emit log_string(">>");

        lpLp.sendTo(address(treasury), 0.5 ether);
        emit log_string(">>");

        treasury.intendConvertToLp();
        vm.warp(block.timestamp + 8 hours);

        emit log_string(">>");

        uint256 tbal0Before = f0.balanceOf(address(treasury));
        uint256 tbal1Before = f1.balanceOf(address(treasury));
        uint256 lbalBefore = pool.balanceOf(address(this));
        uint256 ltbalBefore = pool.balanceOf(address(treasury));

        (uint256 res0, uint256 res1,) = lp.pool().getReserves();
        uniswapOracle.set(lp.pool().token0(), lp.pool().token1(), (res1 << 112) / res0, (res0 << 112) / res1);

        (uint256 reslp0, uint256 reslp1,) = lpLp.pool().getReserves();
        uniswapOracle.set(
            lpLp.pool().token0(), lpLp.pool().token1(), (reslp1 << 112) / reslp0, (reslp0 << 112) / reslp1
        );

        treasury.convertToLp();

        uint256 tbal0After = f0.balanceOf(address(treasury));
        uint256 tbal1After = f1.balanceOf(address(treasury));
        uint256 lbalAfter = pool.balanceOf(address(this));
        uint256 ltbalAfter = pool.balanceOf(address(treasury));

        uint256 tlp2balAfter = lpLp.pool().balanceOf(address(treasury));
        uint256 tlp0balAfter = lp0.balanceOf(address(treasury));
        uint256 tlp1balAfter = lp1.balanceOf(address(treasury));

        emit log_named_uint("tbal0Before", tbal0Before);
        emit log_named_uint("tbal1Before", tbal1Before);
        emit log_named_uint("ltbalBefore", ltbalBefore);
        emit log_named_uint("lbalBefore", lbalBefore);
        emit log_named_uint("tbal0After", tbal0After);
        emit log_named_uint("tbal1After", tbal1After);
        emit log_named_uint("ltbalAfter", ltbalAfter);
        emit log_named_uint("lbalAfter", lbalAfter);

        emit log_named_uint("tlp2balAfter", tlp2balAfter);
        emit log_named_uint("tlp0balAfter", tlp0balAfter);
        emit log_named_uint("tlp1balAfter", tlp1balAfter);

        require(tbal0After <= 10, "rev 0");
        require(tbal1After <= 10, "rev 1");
        require(ltbalBefore < ltbalAfter, "rev 2");
        require(lbalBefore < lbalAfter, "rev 3");

        require(tlp2balAfter == 0, "tlp2balAfter == 0");
        require(tlp0balAfter == 0, "tlp0balAfter == 0");
        require(tlp1balAfter == 0, "tlp1balAfter == 0");
    }

    function test_convertToLp_failsSlippage(bool token0, bool isImbalanced, bool imbalanceDirection) public {
        MockOracle(address(o)).set(false, token0, !token0);

        if (isImbalanced) {
            lp.trade(10 ether, imbalanceDirection);
        }

        emit log_string("updated prices:");
        lp.print_price();

        (uint256 trAmt0, uint256 trAmt1) = token0 ? (uint256(10e18), uint256(1e15)) : (uint256(1e15), uint256(10e18));

        f0.transfer(address(treasury), trAmt0);
        f1.transfer(address(treasury), trAmt1);

        treasury.intendConvertToLp();
        vm.warp(block.timestamp + 8 hours);

        (uint256 res0, uint256 res1,) = lp.pool().getReserves();

        uint256 tbal0Before = f0.balanceOf(address(treasury));
        uint256 tbal1Before = f1.balanceOf(address(treasury));
        uint256 lbalBefore = pool.balanceOf(address(this));
        uint256 ltbalBefore = pool.balanceOf(address(treasury));

        uniswapOracle.set(lp.pool().token0(), lp.pool().token1(), (res1 << 112) / res0, (res0 << 112) / res1);

        try treasury.convertToLp() {
            revert("should fail slippage too high");
        } catch {}
    }

    function test_convertToLp_failsPriceMoved(bool token0, bool isImbalanced, bool imbalanceDirection) public {
        MockOracle(address(o)).set(false, token0, !token0);

        if (isImbalanced) {
            lp.trade(10 ether, imbalanceDirection);
        }

        emit log_string("updated prices:");
        lp.print_price();

        // token0 == true => need to sell token 0 to rebalance
        (uint256 trAmt0, uint256 trAmt1) = token0 ? (uint256(1e17), uint256(1e10)) : (uint256(1e10), uint256(1e17));

        f0.transfer(address(treasury), trAmt0);
        f1.transfer(address(treasury), trAmt1);

        treasury.intendConvertToLp();
        vm.warp(block.timestamp + 8 hours);

        (uint256 res0, uint256 res1,) = lp.pool().getReserves();

        uniswapOracle.set(lp.pool().token0(), lp.pool().token1(), (res1 << 112) / res0, (res0 << 112) / res1);

        emit log_named_uint("res0", res0);
        emit log_named_uint("res1", res1);

        // move pool away from oracle price
        // need to sell token{0,1}, so make token{1,0} more expensive to fail it
        lp.trade(10 ether, token0);

        (res0, res1,) = lp.pool().getReserves();
        emit log_named_uint("res0", res0);
        emit log_named_uint("res1", res1);
        emit log_named_uint("avg0 should be", (res1 << 112) / res0);
        emit log_named_uint("avg1 should be", (res0 << 112) / res1);

        try treasury.convertToLp() {
            revert("should fail oracle price too far");
        } catch {}
    }
}
