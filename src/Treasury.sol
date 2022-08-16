pragma solidity ^0.8.0;

import "./Split.sol";
import "./Factory.sol";
import "./GovToken.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "../lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../lib/utils/UniswapV2Utils.sol";
import "../lib/utils/Math.sol";
import "../lib/utils/IWETH.sol";
import "./interfaces/IUniswapV2Oracle.sol";

contract Treasury /* is Test*/ {
    IWETH weth;
    IOracle oracle;
    GovToken public gov;
    fERC20 gov0;
    fERC20 gov1;
    IUniswapV2Pair govPool;


    Split wethSplit;
    fERC20 token0;
    fERC20 token1;
    IUniswapV2Pair pool;
    bool token0First;
    IUniswapV2Oracle wethOracle;

    Split lpSplit;
    fERC20 lp0;
    fERC20 lp1;
    IUniswapV2Pair lpPool;
    bool lp0First;
    IUniswapV2Oracle lpOracle;

    IUniswapV2Pair govEthPool;


    IUniswapV2Router02  uniswapRouter;


    constructor(SplitFactory _factory, IUniswapV2Factory _uniswapFactory, IUniswapV2Router02 _uniswapRouter, GovToken _gov, IUniswapV2Oracle _wethOracle, IUniswapV2Oracle _lpOracle, IWETH _weth) {
        oracle = _factory.oracle();
        weth = IWETH(_weth);

        wethSplit = _factory.splits(weth);
        (token0, token1) = wethSplit.futures();
        weth.approve(address(wethSplit), type(uint).max);

        uniswapRouter = _uniswapRouter;

        wethOracle = _wethOracle;
        try wethOracle.update() {} catch {}

        pool = IUniswapV2Pair(_uniswapFactory.getPair(address(token0), address(token1)));
        token0.approve(address(_uniswapRouter), type(uint).max);
        token1.approve(address(_uniswapRouter), type(uint).max);
        token0First = address(token0) == pool.token0();

        lpSplit = _factory.splits(IERC20(address(pool)));
        (lp0, lp1) = lpSplit.futures();
        pool.approve(address(lpSplit), type(uint).max);

        lpOracle = _lpOracle;
        try lpOracle.update() {} catch {}

        lpPool = IUniswapV2Pair(_uniswapFactory.getPair(address(lp0), address(lp1)));
        lp0.approve(address(_uniswapRouter), type(uint).max);
        lp1.approve(address(_uniswapRouter), type(uint).max);
        lp0First = address(lp0) == pool.token0();

        gov = _gov;
        Split govSplit = _factory.splits(IERC20(address(_gov)));
        (gov0, gov1) = govSplit.futures();

        // requires gov pool to exist
        govPool = IUniswapV2Pair(UniswapV2Utils.pairFor(address(_uniswapFactory), address(gov0), address(gov1)));
        gov0.approve(address(_uniswapRouter), type(uint).max);
        gov1.approve(address(_uniswapRouter), type(uint).max);

        govEthPool = IUniswapV2Pair(UniswapV2Utils.pairFor(address(_uniswapFactory), address(gov), address(weth)));
        gov.approve(address(_uniswapRouter), type(uint).max);
        weth.approve(address(_uniswapRouter), type(uint).max);
    }

    bool firstRedeem;

    // redeem specific side?
    function redeem(uint256 _amt) public {
        require(oracle.isExpired());
        bool redeemOn0 = oracle.isRedeemable(true);

        if (!firstRedeem) {
            firstRedeem = true;
            redeemLPs(redeemOn0);
        }

        uint total = gov.totalSupply() - gov.balanceOf(address(this));
        uint total0 = total - gov0.balanceOf(address(this)) - burntLP0;
        uint total1 = total - gov1.balanceOf(address(this)) - burntLP1;

        gov.transferFrom(msg.sender, address(this), _amt);

        token0.transfer(msg.sender, _amt * token0.balanceOf(address(this)) / total0);
        token1.transfer(msg.sender, _amt * token1.balanceOf(address(this)) / total1);
    }

    uint burntLP0;
    uint burntLP1;

    // call to create LP tokens from contents, and the excess goes to the caller of the contract
    // fill with the token it's lacking from the ratio
    // flash loan,

    // => LP   caller gets a cut of LP amt outputted, fees accrue in the token missing
    // => LP^2 caller gets a cut of LP amt outputted, fees accrue in the token missing



    function redeemLPs(bool redeemOn0) internal {
        // PHI-WETH
        uint govEthLiq = govEthPool.balanceOf(address(this));
        if (govEthLiq > 0) {
            govEthPool.approve(address(uniswapRouter), type(uint).max);
            uniswapRouter.removeLiquidity(address(gov), address(weth),
                govEthLiq,
                0, 0, address(this), type(uint).max);
        }

        // ETH & WETH -> WETHs & WETHw
        splitEth();

        // LPs-LPw
        uint lpLiq = lpPool.balanceOf(address(this));
        if (lpLiq > 0) {
            lpPool.approve(address(uniswapRouter), type(uint).max);
            uniswapRouter.removeLiquidity(address(lp0), address(lp1),
                lpLiq,
                0, 0, address(this), type(uint).max);
        }

        // redeem excess lps/lpw for lp
        uint lpf = redeemOn0 ? lp0.balanceOf(address(this)) : lp1.balanceOf(address(this));
        if (lpf > 0) {
            (redeemOn0 ? lp0 : lp1).approve(address(lpSplit), type(uint).max);
            lpSplit.redeem(lpf);
        }

        // WETHs-WETHw
        uint liq = pool.balanceOf(address(this));
        if (liq > 0) {
            pool.approve(address(uniswapRouter), type(uint).max);
            uniswapRouter.removeLiquidity(address(token0), address(token1),
                liq,
                0, 0, address(this), type(uint).max);
        }

        // PHIs-PHIw
        uint govLiq = govPool.balanceOf(address(this));
        if (govLiq > 0) {
            govPool.approve(address(uniswapRouter), type(uint).max);
            uniswapRouter.removeLiquidity(address(gov0), address(gov1),
                govLiq,
                0, 0, address(this), type(uint).max);
        }

        // burnt PHIs-PHIw
        uint b0 = govPool.balanceOf(address(0));
        if (b0 > 0) {
            (uint res0, uint res1,) = govPool.getReserves();

            burntLP0 = b0 * b0 / res1;
            burntLP1 = b0 * b0 / res0;
        }
    }

    uint treasuryLPRewardBps = 100; // = 1%

    uint constant maxDiscount = 5000; // bps 5000 = 50%
    uint constant auctionDuration = 12 hours;

    mapping(address => uint) convertersLp;
    mapping(address => uint) convertersLpLp;

    function intendConvertToLp() public {
        try wethOracle.update() {} catch {}
        convertersLp[msg.sender] = block.timestamp;
    }

    function intendConvertToLpLp() public {
        try lpOracle.update() {} catch {}
        convertersLpLp[msg.sender] = block.timestamp;
    }

    // auction: expects pool to already have liquidity
    // pays 1% of lp tokens it receives to caller
    function convertToLp() public {
        require(!oracle.isExpired());

        uint elapsed = block.timestamp - convertersLp[msg.sender];
        require(elapsed >= auctionDuration / 4 && elapsed < auctionDuration, "not in window");

        splitEth();

        try wethOracle.update() {} catch {}
        (uint balF0,uint balF1) = (token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        (uint balR0, uint balR1,) = pool.getReserves();
        if (!token0First) (balR0,  balR1) = (balR1, balR0);


//        emit log_named_uint("balF0", balF0);
//        emit log_named_uint("balF1", balF1);
//        emit log_named_uint("balR0", balR0);
//        emit log_named_uint("balR1", balR1);


        bool excessIn0 = balF0 * balR1 > balF1 * balR0;

        // TODO: impl for !excessIn0 <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        //        require(excessIn0, "!excessIn0");
        if (!excessIn0) (balR0, balR1, balF0, balF1) = (balR1, balR0, balF1, balF0);

        //        uint nb = balR0 * (balF1 + 1000 * balR1 / 997 + balR1) - balF0 * balR1;
        //        uint ac = (balF0 * balR1 - balF1 * balR0) * balR0 * 1000 / 997 * balR1;
        //        uint amtIn = (Math.sqrt(nb * nb + 4 * ac) - nb) / 2 / balR1;



//        emit log_string("point0");
//        uint nb = (balR0 * 1000 / 997 + balR1 * (balF1 + balR0) / (balF1 + balR1)) / 2;
//        emit log_named_uint("nb", nb);
//        emit log_string("point1");
//        uint amtIn;
        //        bool bal0gt1 = balF0 > balF1;
        //        if (bal0gt1) {
        //            emit log_string("point2a");
        //
        //            uint ac = balR1 * balR0 * 1000 / 997 * (balF0 - balF1) / 4 / (balF1 + balR1);
        //            emit log_named_uint("ac", ac);
        //            emit log_string("point3a");
        //            amtIn = (Math.sqrt(nb * nb + 4 * ac) - nb);
        //        } else {
        //            emit log_string("point2b");
        //            uint ac = balR1 * balR0 * 1000 / 997 * (balF1 - balF0) / 4 / (balF1 + balR1);
        //            emit log_named_uint("ac", ac);
        //            //            uint ac = balR1 * balR0 * (balF1 - balF0) * (balF1 + balR1); // / 4 / (balF1 + balR1)**2
        //            emit log_string("point3b");
        //            amtIn = (nb + Math.sqrt(nb * nb - 4 * ac));
        //        }

        uint amtIn = (Math.sqrt((balR0 * (4 * balF0 * balR1 * 1000 / 997 + balR0 * balF1 * (1000 - 997) ** 2 / 997 ** 2 + balR0 * balR1 * (1000 + 997) ** 2 / 997 ** 2)) / (balR1 + balF1)) - balR0 * (1000 + 997) / 997) / 2;

//        emit log_named_uint("wethOracle.consult(address(excessIn0 ? token1 : token0), amtIn)", wethOracle.consult(address(excessIn0 ? token1 : token0), amtIn));
//        emit log_named_uint("wethOracle.consult(address(!excessIn0 ? token1 : token0), amtIn)", wethOracle.consult(address(!excessIn0 ? token1 : token0), amtIn));
//
//        emit log_named_uint("amtIn", amtIn);

        uint twapPrice = wethOracle.consult(address(excessIn0 ? token1 : token0), amtIn);
        require(twapPrice != 0, "twap price = 0");

        uint minAmtOut = twapPrice * (10000 - 500) / 10000;
        // 5% slippage on twap price

        uint amtOut = UniswapV2Utils.getAmountOut(amtIn, balR0, balR1);

//        emit log_named_uint("minAmtOut", minAmtOut);
//        emit log_named_uint("twapPrice", twapPrice);
//        emit log_named_uint("amtOut", amtOut);


        require(amtOut > minAmtOut, "rebalancing price not accepted");

        (excessIn0 ? token0 : token1).transfer(address(pool), amtIn);
        if (excessIn0) {
            pool.swap(token0First ? 0 : amtOut, token0First ? amtOut : 0, address(this), "");
        } else {
            pool.swap(token0First ? amtOut : 0, token0First ? 0 : amtOut, address(this), "");
        }

        (uint b00, uint b11) = excessIn0 ? (balF0 - amtIn, balF1 + amtOut) : (balF1 + amtOut, balF0 - amtIn);

//        emit log_named_uint("b00", b00);
//        emit log_named_uint("b11", b11);

//        emit log_named_uint("b0", token0.balanceOf(address(this)));
//        emit log_named_uint("b1", token1.balanceOf(address(this)));

        uint balLp0 = pool.balanceOf(address(this));
        uniswapRouter.addLiquidity(address(token0), address(token1),
            b00, b11, 0, 0,
            address(this), type(uint).max);

        uint reward = (pool.balanceOf(address(this)) - balLp0) * treasuryLPRewardBps / 10000;
        pool.transfer(msg.sender, reward);
    }

    function splitEth() internal {
        uint ethBal = address(this).balance;
        if (ethBal > 0) weth.deposit{value : ethBal}();

        uint wethBal = weth.balanceOf(address(this));
        if (wethBal > 0) wethSplit.mint(wethBal);
    }


    function convertToLp2() public {
        require(!oracle.isExpired());

        uint elapsed = block.timestamp - convertersLp[msg.sender];
        require(elapsed >= auctionDuration / 4 && elapsed < auctionDuration, "not in window");

        uint lpBal = lpPool.balanceOf(address(this));
        if (lpBal > 0) lpSplit.mint(lpBal);

        try lpOracle.update() {} catch {}
        (uint balLp0,uint balLp1) = (lp0.balanceOf(address(this)), lp1.balanceOf(address(this)));
        (uint112 balR0, uint112 balR1,) = lpPool.getReserves();
        if (!lp0First) (balR0,  balR1) = (balR1, balR0);

        bool excessIn0 = balLp0 * balR1 > balLp1 * balR0;

        // TODO: implement

        revert("not impl");
    }
}
