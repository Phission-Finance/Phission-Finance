pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "../Zap.sol";
import "./MockOracle.sol";
import "./LPUtils.sol";
import "./MockUniswapV2SlidingOracle.sol";
import "../../lib/utils/IWETH.sol";

contract ZapTest_fork is Test {
    Zap z;
    Treasury treasury;
    GovToken gov;
    IOracle o;

    MockUniswapV2SlidingOracle uniswapOracle;

    Split s;
    fERC20 f0;
    fERC20 f1;

    WethLp lp;
    Split sLp;

    IWETH weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV2Factory univ2fac = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    IUniswapV2Router02 univ2router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    fallback() external payable {}

    function setUp() public {
        o = IOracle(address(new MockOracle(false, true, false)));
        SplitFactory sf = new SplitFactory(o);
        s = sf.create(weth);
        (f0, f1) = s.futures();

        lp = new WethLp{value : 40 ether}(sf);

        sLp = sf.create(IERC20(address(lp.pool())));
        SplitLp lpLp = new SplitLp(sf, IERC20(address(lp.pool())));
        lp.pool().approve(address(lpLp), type(uint256).max);

        lp.sendTo(address(lpLp), 1 ether);
        lpLp.add(1 ether);

        uniswapOracle = new MockUniswapV2SlidingOracle(address(univ2fac), 6 hours, 6);
        require(address(uniswapOracle) != address(0));

        gov = new GovToken();
        sf.create(IERC20(address(gov)));

        treasury = new Treasury(sf, univ2fac, univ2router, gov, uniswapOracle, weth);
        //        gov = treasury.gov();

        weth.deposit{value : 10 ether}();
        weth.approve(address(s), type(uint256).max);

        uint256 gas = gasleft();
        s.mint(8 ether);
        emit log_named_uint("SPLIT::MINT() gas usage", gas - gasleft());

        z = new Zap(univ2fac, univ2router, sf, Treasury(treasury), weth);
    }

    function test_fork_mint(uint256 amt) public {
        uint256 balEthBefore = address(this).balance;
        amt = amt % balEthBefore;
        if (amt == 0) {
            return;
        }

        uint256 bal0Before = f0.balanceOf(address(this));
        uint256 bal1Before = f1.balanceOf(address(this));

        uint256 gas = gasleft();
        z.mint{value : amt}();
        emit log_named_uint("ZAP::MINT() gas usage", gas - gasleft());

        uint256 balEthAfter = address(this).balance;
        uint256 bal0After = f0.balanceOf(address(this));
        uint256 bal1After = f1.balanceOf(address(this));

        emit log_named_uint("balEthBefore", balEthBefore);
        emit log_named_uint("bal0After", bal0After);
        emit log_named_uint("bal1After", bal1After);
        emit log_named_uint("balEthAfter", balEthAfter);
        emit log_named_uint("bal0Before", bal0Before);
        emit log_named_uint("bal1Before", bal1Before);

        require(balEthBefore - balEthAfter == amt, "balEthBefore - balEthAfter != amt");
        require(bal0After - bal0Before == amt, "bal0After - bal0Before != amt");
        require(bal1After - bal1Before == amt, "bal1After - bal1Before != amt");
    }

    function test_fork_burn(uint256 amt) public {
        uint256 balEthBefore = address(this).balance;
        amt = amt % balEthBefore;
        if (amt == 0) {
            return;
        }

        z.mint{value : amt}();

        balEthBefore = address(this).balance;
        uint256 bal0Before = f0.balanceOf(address(this));
        uint256 bal1Before = f1.balanceOf(address(this));

        f0.approve(address(z), type(uint256).max);
        f1.approve(address(z), type(uint256).max);

        uint256 gas = gasleft();
        z.burn(amt);
        emit log_named_uint("ZAP::BURN() gas usage", gas - gasleft());

        uint256 balEthAfter = address(this).balance;
        uint256 bal0After = f0.balanceOf(address(this));
        uint256 bal1After = f1.balanceOf(address(this));

        emit log_named_uint("balEthBefore", balEthBefore);
        emit log_named_uint("bal0After", bal0After);
        emit log_named_uint("bal1After", bal1After);
        emit log_named_uint("balEthAfter", balEthAfter);
        emit log_named_uint("bal0Before", bal0Before);
        emit log_named_uint("bal1Before", bal1Before);

        require(balEthAfter - balEthBefore == amt, "balEthAfter - balEthBefore != amt");
        require(bal0Before - bal0After == amt, "bal0Before - bal0After != amt");
        require(bal1Before - bal1After == amt, "bal1Before - bal1After != amt");
    }

    function test_fork_redeem(bool tok0, uint256 amt) public {
        uint256 balEthBefore = address(this).balance;
        amt = amt % balEthBefore;
        if (amt == 0) {
            return;
        }

        z.mint{value : amt}();

        balEthBefore = address(this).balance;
        uint256 bal0Before = f0.balanceOf(address(this));
        uint256 bal1Before = f1.balanceOf(address(this));

        MockOracle(address(o)).set(true, tok0, !tok0);

        (tok0 ? f0 : f1).approve(address(z), type(uint256).max);

        uint256 gas = gasleft();
        z.redeem(tok0, amt);
        emit log_named_uint("ZAP::REDEEM() gas usage", gas - gasleft());

        uint256 balEthAfter = address(this).balance;
        uint256 bal0After = f0.balanceOf(address(this));
        uint256 bal1After = f1.balanceOf(address(this));

        require(balEthAfter - balEthBefore == amt, "balEthAfter - balEthBefore == amt");
        if (tok0) {
            require(bal0Before - bal0After == amt, "bal0Before - bal0After == amt");
        } else {
            require(bal1Before - bal1After == amt, "bal1Before - bal1After == amt");
        }
    }

    function checkZapBalances() internal {
        uint256 balE = address(z).balance;
        uint256 balF0 = f0.balanceOf(address(z));
        uint256 balF1 = f1.balanceOf(address(z));
        uint256 balLp = lp.pool().balanceOf(address(z));

        emit log_named_uint("residual balE", balE);
        emit log_named_uint("residual balF0", balF0);
        emit log_named_uint("residual balF1", balF1);
        emit log_named_uint("residual balLp", balLp);

        require(balE <= 1, "residual balE");
        require(balF0 <= 1, "residual balF0");
        require(balF1 <= 1, "residual balF1");
        require(balLp <= 1, "residual balLp");
    }

    function test_fork_buy(bool token0, bool isImbalanced, bool imbalanceDirection) public {
        emit log_string("=== === BUY");

        if (isImbalanced) {
            lp.trade(10 ether, imbalanceDirection);
        }

        //                token0 = true;

        //        (token0? f0 : f1).transfer(address(treasury), 1 ether);
        f0.transfer(address(treasury), 1 ether);

        uint256 balanceBefore = address(this).balance;
        uint256 f0thisBefore = f0.balanceOf(address(this));
        uint256 f1thisBefore = f1.balanceOf(address(this));
        uint256 f0treasuryBefore = f0.balanceOf(address(treasury));
        uint256 f1treasuryBefore = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceBefore);
        emit log_named_uint("f0this", f0thisBefore);
        emit log_named_uint("f1this", f1thisBefore);
        emit log_named_uint("f0treasury", f0treasuryBefore);
        emit log_named_uint("f1treasury", f1treasuryBefore);

        uint256 gas = gasleft();
        //        z.buy{value : 1 ether}(1 ether, 0, token0);
        uint256 returnedValue = z.buy{value : 0.01 ether}(0.01 ether, 0, token0);
        emit log_named_uint("ZAP::BUY(fee before) gas usage", gas - gasleft());

        uint256 balanceAfter = address(this).balance;
        uint256 f0thisAfter = f0.balanceOf(address(this));
        uint256 f1thisAfter = f1.balanceOf(address(this));
        uint256 f0treasuryAfter = f0.balanceOf(address(treasury));
        uint256 f1treasuryAfter = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceAfter);
        emit log_named_uint("f0this", f0thisAfter);
        emit log_named_uint("f1this", f1thisAfter);
        emit log_named_uint("f0treasury", f0treasuryAfter);
        emit log_named_uint("f1treasury", f1treasuryAfter);

        require(token0 ? f0thisAfter > f0thisBefore : f0thisAfter == f0thisBefore, "error 1");
        require(token0 ? f1thisAfter == f1thisBefore : f1thisAfter > f1thisBefore, "error 2");
        require(balanceBefore - balanceAfter == 0.01 ether, "error 3");

        require(
            (token0 ? (f0thisAfter - f0thisBefore) : (f1thisAfter - f1thisBefore)) == returnedValue,
            "buy return value not correct"
        );
        checkZapBalances();
    }

    function test_fork_sell(bool token0, bool isImbalanced, bool imbalanceDirection) public {
        emit log_string("=== === SELL");

        if (isImbalanced) {
            lp.trade(10 ether, imbalanceDirection);
        }

        (token0 ? f0 : f1).transfer(address(treasury), 1 ether);
        uint256 tokenBought = (token0 ? f0 : f1).balanceOf(address(this));

        z.buy{value : 1 ether}(1 ether, 0, token0);

        tokenBought = (token0 ? f0 : f1).balanceOf(address(this)) - tokenBought;

        uint256 balanceBefore = address(this).balance;
        uint256 f0thisBefore = f0.balanceOf(address(this));
        uint256 f1thisBefore = f1.balanceOf(address(this));
        uint256 f0treasuryBefore = f0.balanceOf(address(treasury));
        uint256 f1treasuryBefore = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceBefore);
        emit log_named_uint("f0this", f0thisBefore);
        emit log_named_uint("f1this", f1thisBefore);
        emit log_named_uint("f0treasury", f0treasuryBefore);
        emit log_named_uint("f1treasury", f1treasuryBefore);

        (token0 ? f0 : f1).approve(address(z), type(uint256).max);
        uint256 gas = gasleft();
        uint256 returnedValue = z.sell(tokenBought, 0, token0);
        emit log_named_uint("ZAP::SELL() gas usage", gas - gasleft());

        uint256 balanceAfter = address(this).balance;
        uint256 f0thisAfter = f0.balanceOf(address(this));
        uint256 f1thisAfter = f1.balanceOf(address(this));
        uint256 f0treasuryAfter = f0.balanceOf(address(treasury));
        uint256 f1treasuryAfter = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceAfter);
        emit log_named_uint("f0this", f0thisAfter);
        emit log_named_uint("f1this", f1thisAfter);
        emit log_named_uint("f0treasury", f0treasuryAfter);
        emit log_named_uint("f1treasury", f1treasuryAfter);

        if (token0) {
            require(f0thisBefore - f0thisAfter == tokenBought, "error 1");
            require(f1thisBefore == f1thisAfter, "error 2");
        } else {
            require(f1thisBefore - f1thisAfter == tokenBought, "error 1");
            require(f0thisBefore == f0thisAfter, "error 2");
        }
        require(balanceAfter - balanceBefore > 0.8 ether && balanceAfter - balanceBefore < 1 ether, "error 3");

        emit log_named_uint("returnedValue", returnedValue);
        emit log_named_uint("balanceAfter - balanceBefore", balanceAfter - balanceBefore);

        require(returnedValue == balanceAfter - balanceBefore, "sell return value incorrect");

        checkZapBalances();
    }

    // TODO: test min amount out

    function test_fork_buyLP(bool token0, bool isImbalanced, bool imbalanceDirection) public {
        emit log_string("=== === BUY LP");

        if (isImbalanced) {
            lp.trade(10 ether, imbalanceDirection);
        }

        uint256 balanceBefore = address(this).balance;
        uint256 f0thisBefore = f0.balanceOf(address(this));
        uint256 f1thisBefore = f1.balanceOf(address(this));
        uint256 lpthisBefore = lp.pool().balanceOf(address(this));

        uint256 f0treasuryBefore = f0.balanceOf(address(treasury));
        uint256 f1treasuryBefore = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceBefore);
        emit log_named_uint("f0this", f0thisBefore);
        emit log_named_uint("f1this", f1thisBefore);
        emit log_named_uint("lpthisBefore", lpthisBefore);
        emit log_named_uint("f0treasury", f0treasuryBefore);
        emit log_named_uint("f1treasury", f1treasuryBefore);

        uint256 gas = gasleft();
        uint256 returnedValue = z.buyLP{value : 1 ether}(1 ether, 0);
        emit log_named_uint("ZAP::BUYLP() gas usage", gas - gasleft());

        uint256 balanceAfter = address(this).balance;
        uint256 f0thisAfter = f0.balanceOf(address(this));
        uint256 f1thisAfter = f1.balanceOf(address(this));
        uint256 lpthisAfter = lp.pool().balanceOf(address(this));

        uint256 f0treasuryAfter = f0.balanceOf(address(treasury));
        uint256 f1treasuryAfter = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceAfter);
        emit log_named_uint("f0this", f0thisAfter);
        emit log_named_uint("f1this", f1thisAfter);
        emit log_named_uint("lpthisAfter", lpthisAfter);
        emit log_named_uint("f0treasury", f0treasuryAfter);
        emit log_named_uint("f1treasury", f1treasuryAfter);

        require(lpthisAfter > lpthisBefore, "error 1");
        require(f0thisAfter == f0thisBefore && f1thisAfter == f1thisBefore, "error 2");
        require(balanceBefore - balanceAfter == 1 ether, "error 3");

        require(returnedValue == lpthisAfter - lpthisBefore, "buy LP return value incorrect");
        checkZapBalances();
    }

    // todo: fuzz tests with trade size, pool reserve amounts
    function test_fork_sellLP(bool token0, bool isImbalanced, bool imbalanceDirection) public {
        emit log_string("=== === SELL LP");

        if (isImbalanced) {
            lp.trade(10 ether, imbalanceDirection);
        }

        z.buyLP{value : 1 ether}(1 ether, 0);

        uint256 balanceBefore = address(this).balance;
        uint256 f0thisBefore = f0.balanceOf(address(this));
        uint256 f1thisBefore = f1.balanceOf(address(this));
        uint256 lpthisBefore = lp.pool().balanceOf(address(this));

        uint256 f0treasuryBefore = f0.balanceOf(address(treasury));
        uint256 f1treasuryBefore = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceBefore);
        emit log_named_uint("f0this", f0thisBefore);
        emit log_named_uint("f1this", f1thisBefore);
        emit log_named_uint("lpthisBefore", lpthisBefore);
        emit log_named_uint("f0treasury", f0treasuryBefore);
        emit log_named_uint("f1treasury", f1treasuryBefore);

        lp.pool().approve(address(z), type(uint256).max);

        uint256 gas = gasleft();
        uint256 returnedValue = z.sellLP(lpthisBefore, 0);
        emit log_named_uint("ZAP::SELLLP() gas usage", gas - gasleft());

        uint256 balanceAfter = address(this).balance;
        uint256 f0thisAfter = f0.balanceOf(address(this));
        uint256 f1thisAfter = f1.balanceOf(address(this));
        uint256 lpthisAfter = lp.pool().balanceOf(address(this));

        uint256 f0treasuryAfter = f0.balanceOf(address(treasury));
        uint256 f1treasuryAfter = f1.balanceOf(address(treasury));

        emit log_named_uint("balance", balanceAfter);
        emit log_named_uint("f0this", f0thisAfter);
        emit log_named_uint("f1this", f1thisAfter);
        emit log_named_uint("lpthisAfter", lpthisAfter);
        emit log_named_uint("f0treasury", f0treasuryAfter);
        emit log_named_uint("f1treasury", f1treasuryAfter);

        emit log_named_uint("balanceAfter - balanceBefore", balanceAfter - balanceBefore);

        require(lpthisAfter < lpthisBefore, "error 1");
        require(f0thisAfter == f0thisBefore && f1thisAfter == f1thisBefore, "error 2");
        require(balanceAfter - balanceBefore > 0.8 ether && balanceAfter - balanceBefore < 1 ether, "error 3");

        checkZapBalances();
    }
}
