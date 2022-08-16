pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../Zap.sol";
import "./MockOracle.sol";
import "./LPUtils.sol";
import "./MockUniswapV2Oracle.sol";
import "../../lib/utils/IWETH.sol";

contract ZapTest_fork is Test {
    Zap z;
    Treasury treasury;
    GovToken gov;
    IOracle o;

    Split s;
    fERC20 f0;
    fERC20 f1;

    WethLp lp;
    Split sLp;

    IWETH weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2Factory univ2fac = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Router02 univ2router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);


    fallback() external payable {
    }

    function setUp() public {
        o = IOracle(address(new MockOracle(false, true, false)));
        SplitFactory sf = new SplitFactory(o);
        s = sf.create(weth);
        (f0, f1) = s.futures();

        lp = new WethLp{value : 40 ether}(sf);

        sLp = sf.create(IERC20(address(lp.pool())));
        SplitLp lpLp = new SplitLp(sf, IERC20(address(lp.pool())));
        lp.pool().approve(address(lpLp), type(uint).max);

        lp.sendTo(address(lpLp), 1 ether);
        lpLp.add(1 ether);


        MockUniswapV2Oracle wethOracle = new MockUniswapV2Oracle(f0, f1, 0, 0);
        MockUniswapV2Oracle lpOracle = new MockUniswapV2Oracle(lpLp.t0(), lpLp.t1(), 0, 0);


        gov = new GovToken();
        sf.create(IERC20(address(gov)));

        treasury = new Treasury(sf, univ2fac, univ2router, gov, wethOracle, lpOracle, weth);
        //        gov = treasury.gov();

        weth.deposit{value : 10 ether}();
        weth.approve(address(s), type(uint).max);

        uint gas = gasleft();
        s.mint(8 ether);
        emit log_named_uint("SPLIT::MINT() gas usage", gas - gasleft());

        z = new Zap(univ2fac, univ2router, sf, Treasury(treasury), weth);
    }

    function test_fork_mint() public {
        emit log_named_uint("balance)", address(this).balance);
        emit log_named_uint("f0 this", f0.balanceOf(address(this)));
        emit log_named_uint("f1 this", f1.balanceOf(address(this)));
        emit log_named_uint("f0 treasury", f0.balanceOf(address(treasury)));
        emit log_named_uint("f1 treasury", f1.balanceOf(address(treasury)));

        uint gas = gasleft();
        //        (bool success, ) = address(z).call{value: 1 ether}("");
        //        require(success);
        z.mint{value : 1 ether}();
        emit log_named_uint("ZAP::MINT() gas usage", gas - gasleft());

        emit log_named_uint("balance)", address(this).balance);
        emit log_named_uint("f0 this", f0.balanceOf(address(this)));
        emit log_named_uint("f1 this", f1.balanceOf(address(this)));
        emit log_named_uint("f0 treasury", f0.balanceOf(address(treasury)));
        emit log_named_uint("f1 treasury", f1.balanceOf(address(treasury)));
    }

    function test_fork_buy(bool token0) public {
        emit log_string("=== === BUY");

        //                token0 = true;

        //        (token0? f0 : f1).transfer(address(treasury), 1 ether);
        f0.transfer(address(treasury), 1 ether);

        uint balanceBefore = address(this).balance;
        uint f0thisBefore = f0.balanceOf(address(this));
        uint f1thisBefore = f1.balanceOf(address(this));
        uint f0treasuryBefore = f0.balanceOf(address(treasury));
        uint f1treasuryBefore = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceBefore);
        emit log_named_uint("f0this", f0thisBefore);
        emit log_named_uint("f1this", f1thisBefore);
        emit log_named_uint("f0treasury", f0treasuryBefore);
        emit log_named_uint("f1treasury", f1treasuryBefore);

        uint gas = gasleft();
        //        z.buy{value : 1 ether}(1 ether, 0, token0);
        z.buy{value : 0.01 ether}(0.01 ether, 0, token0);
        emit log_named_uint("ZAP::BUY(fee before) gas usage", gas - gasleft());

        uint balanceAfter = address(this).balance;
        uint f0thisAfter = f0.balanceOf(address(this));
        uint f1thisAfter = f1.balanceOf(address(this));
        uint f0treasuryAfter = f0.balanceOf(address(treasury));
        uint f1treasuryAfter = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceAfter);
        emit log_named_uint("f0this", f0thisAfter);
        emit log_named_uint("f1this", f1thisAfter);
        emit log_named_uint("f0treasury", f0treasuryAfter);
        emit log_named_uint("f1treasury", f1treasuryAfter);

        // if (token0)
        //      require(f0thisAfter > f0thisBefore);
        // else
        //      require(f1thisAfter > f1thisBefore);
        require(token0 ? f0thisAfter > f0thisBefore : f0thisAfter == f0thisBefore, "error 1");
        require(token0 ? f1thisAfter == f1thisBefore : f1thisAfter > f1thisBefore, "error 2");
        require(balanceBefore - balanceAfter == 0.01 ether, "error 3");

    }

    function test_fork_sell(bool token0) public {
        emit log_string("=== === SELL");

        (token0 ? f0 : f1).transfer(address(treasury), 1 ether);
        uint tokenBought = (token0 ? f0 : f1).balanceOf(address(this));

        z.buy{value : 1 ether}(1 ether, 0, token0);

        tokenBought = (token0 ? f0 : f1).balanceOf(address(this)) - tokenBought;

        uint balanceBefore = address(this).balance;
        uint f0thisBefore = f0.balanceOf(address(this));
        uint f1thisBefore = f1.balanceOf(address(this));
        uint f0treasuryBefore = f0.balanceOf(address(treasury));
        uint f1treasuryBefore = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceBefore);
        emit log_named_uint("f0this", f0thisBefore);
        emit log_named_uint("f1this", f1thisBefore);
        emit log_named_uint("f0treasury", f0treasuryBefore);
        emit log_named_uint("f1treasury", f1treasuryBefore);

        (token0 ? f0 : f1).approve(address(z), type(uint).max);
        uint gas = gasleft();
        z.sell(tokenBought, 0, token0);
        emit log_named_uint("ZAP::SELL() gas usage", gas - gasleft());

        uint balanceAfter = address(this).balance;
        uint f0thisAfter = f0.balanceOf(address(this));
        uint f1thisAfter = f1.balanceOf(address(this));
        uint f0treasuryAfter = f0.balanceOf(address(treasury));
        uint f1treasuryAfter = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceAfter);
        emit log_named_uint("f0this", f0thisAfter);
        emit log_named_uint("f1this", f1thisAfter);
        emit log_named_uint("f0treasury", f0treasuryAfter);
        emit log_named_uint("f1treasury", f1treasuryAfter);


        require((token0 ? (f0thisBefore - f0thisAfter) : (f1thisBefore - f1thisAfter)) == tokenBought, "error 1");
        require(token0 ? (f1thisBefore == f1thisAfter) : (f0thisBefore == f0thisAfter), "error 2");
        require(balanceAfter > balanceBefore, "error 3");
    }

    function test_fork_buyLP(bool token0) public {
        emit log_string("=== === BUY LP");

        uint balanceBefore = address(this).balance;
        uint f0thisBefore = f0.balanceOf(address(this));
        uint f1thisBefore = f1.balanceOf(address(this));
        uint lpthisBefore = lp.pool().balanceOf(address(this));

        uint f0treasuryBefore = f0.balanceOf(address(treasury));
        uint f1treasuryBefore = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceBefore);
        emit log_named_uint("f0this", f0thisBefore);
        emit log_named_uint("f1this", f1thisBefore);
        emit log_named_uint("lpthisBefore", lpthisBefore);
        emit log_named_uint("f0treasury", f0treasuryBefore);
        emit log_named_uint("f1treasury", f1treasuryBefore);

        uint gas = gasleft();
        z.buyLP{value : 0.01 ether}(0.01 ether, 0);
        emit log_named_uint("ZAP::BUYLP() gas usage", gas - gasleft());

        uint balanceAfter = address(this).balance;
        uint f0thisAfter = f0.balanceOf(address(this));
        uint f1thisAfter = f1.balanceOf(address(this));
        uint lpthisAfter = lp.pool().balanceOf(address(this));

        uint f0treasuryAfter = f0.balanceOf(address(treasury));
        uint f1treasuryAfter = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceAfter);
        emit log_named_uint("f0this", f0thisAfter);
        emit log_named_uint("f1this", f1thisAfter);
        emit log_named_uint("lpthisAfter", lpthisAfter);
        emit log_named_uint("f0treasury", f0treasuryAfter);
        emit log_named_uint("f1treasury", f1treasuryAfter);

        require(lpthisAfter > lpthisBefore, "error 1");
        require(f0thisAfter == f0thisBefore && f1thisAfter == f1thisBefore, "error 2");
        require(balanceBefore - balanceAfter == 0.01 ether, "error 3");
    }

    function test_fork_sellLP(bool token0) public {
        emit log_string("=== === SELL LP");

        // TODO: implement
        return;

        uint balanceBefore = address(this).balance;
        uint f0thisBefore = f0.balanceOf(address(this));
        uint f1thisBefore = f1.balanceOf(address(this));
        uint lpthisBefore = lp.pool().balanceOf(address(this));

        uint f0treasuryBefore = f0.balanceOf(address(treasury));
        uint f1treasuryBefore = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceBefore);
        emit log_named_uint("f0this", f0thisBefore);
        emit log_named_uint("f1this", f1thisBefore);
        emit log_named_uint("lpthisBefore", lpthisBefore);
        emit log_named_uint("f0treasury", f0treasuryBefore);
        emit log_named_uint("f1treasury", f1treasuryBefore);

        uint gas = gasleft();
        z.sellLP(0.01 ether, 0);
        emit log_named_uint("ZAP::BUYLP() gas usage", gas - gasleft());

        uint balanceAfter = address(this).balance;
        uint f0thisAfter = f0.balanceOf(address(this));
        uint f1thisAfter = f1.balanceOf(address(this));
        uint lpthisAfter = lp.pool().balanceOf(address(this));

        uint f0treasuryAfter = f0.balanceOf(address(treasury));
        uint f1treasuryAfter = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceAfter);
        emit log_named_uint("f0this", f0thisAfter);
        emit log_named_uint("f1this", f1thisAfter);
        emit log_named_uint("lpthisAfter", lpthisAfter);
        emit log_named_uint("f0treasury", f0treasuryAfter);
        emit log_named_uint("f1treasury", f1treasuryAfter);

        require(lpthisAfter > lpthisBefore, "error 1");
        require(f0thisAfter == f0thisBefore && f1thisAfter == f1thisBefore, "error 2");
        require(balanceBefore - balanceAfter == 0.01 ether, "error 3");
    }

}
