pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "./Split.sol";
import "./Factory.sol";
import "./GovToken.sol";
import "./IUniswapV2SlidingOracle.sol";

import "../lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "../lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../lib/utils/UniswapV2Utils.sol";
import "../lib/utils/Math.sol";
import "../lib/utils/IWETH.sol";
import "../lib/prb-math/contracts/PRBMath.sol";

contract Treasury is Test {
    IWETH weth;
    IOracle oracle;
    GovToken public gov;
    fERC20 gov0;
    fERC20 gov1;

    IUniswapV2Pair govPool;
    IUniswapV2Pair govEthPool;

    IUniswapV2SlidingOracle uniswapOracle;
    uint256 uniswapOracleWindowSize;

    Split wethSplit;
    fERC20 token0;
    fERC20 token1;
    IUniswapV2Pair pool;
    bool token0First;

    Split lpSplit;
    fERC20 lp0;
    fERC20 lp1;
    IUniswapV2Pair lpPool;
    bool lp0First;

    IUniswapV2Router02 uniswapRouter;

    constructor(
        SplitFactory _factory,
        IUniswapV2Factory _uniswapFactory,
        IUniswapV2Router02 _uniswapRouter,
        GovToken _gov,
        IUniswapV2SlidingOracle _uniswapOracle,
        IWETH _weth
    ) {
        oracle = _factory.oracle();
        weth = IWETH(_weth);

        wethSplit = _factory.splits(weth);
        (token0, token1) = wethSplit.futures();
        weth.approve(address(wethSplit), type(uint256).max);

        uniswapRouter = _uniswapRouter;

        _uniswapOracle.update(address(token0), address(token1));
        _uniswapOracle.update(address(lp0), address(lp1));
        uniswapOracleWindowSize = _uniswapOracle.windowSize();
        uniswapOracle = _uniswapOracle;

        pool = IUniswapV2Pair(_uniswapFactory.getPair(address(token0), address(token1)));
        token0.approve(address(_uniswapRouter), type(uint256).max);
        token1.approve(address(_uniswapRouter), type(uint256).max);
        token0First = address(token0) == pool.token0();

        lpSplit = _factory.splits(IERC20(address(pool)));
        (lp0, lp1) = lpSplit.futures();
        pool.approve(address(lpSplit), type(uint256).max);

        lpPool = IUniswapV2Pair(_uniswapFactory.getPair(address(lp0), address(lp1)));
        lp0.approve(address(_uniswapRouter), type(uint256).max);
        lp1.approve(address(_uniswapRouter), type(uint256).max);
        lp0.approve(address(lpSplit), type(uint256).max);
        lp1.approve(address(lpSplit), type(uint256).max);
        lp0First = address(lp0) == lpPool.token0();

        lpPool.approve(address(uniswapRouter), type(uint256).max);

        gov = _gov;
        Split govSplit = _factory.splits(IERC20(address(_gov)));
        (gov0, gov1) = govSplit.futures();

        // requires gov pool to exist
        govPool = IUniswapV2Pair(UniswapV2Utils.pairFor(address(_uniswapFactory), address(gov0), address(gov1)));
        gov0.approve(address(_uniswapRouter), type(uint256).max);
        gov1.approve(address(_uniswapRouter), type(uint256).max);

        govEthPool = IUniswapV2Pair(UniswapV2Utils.pairFor(address(_uniswapFactory), address(gov), address(weth)));
        gov.approve(address(_uniswapRouter), type(uint256).max);
        weth.approve(address(_uniswapRouter), type(uint256).max);
    }

    receive() external payable {}

    bool firstRedeem;

    function redeem(uint256 _amt) public {
        // => need to redeem all assets, as anything accrued right before merge would be stuck otherwise
        emit log_named_uint("_amt", _amt);

        emit log_named_uint("gov0.balanceOf(address(this))", gov0.balanceOf(address(this)));
        emit log_named_uint("gov1.balanceOf(address(this))", gov1.balanceOf(address(this)));
        emit log_named_uint("gov.balanceOf(address(this))", gov.balanceOf(address(this)));

        require(oracle.isExpired());
        bool redeemOn0 = oracle.isRedeemable(true);

        if (!firstRedeem) {
            firstRedeem = true;
            unwind(redeemOn0);
        }

        emit log_named_uint("gov0.balanceOf(address(this))", gov0.balanceOf(address(this)));
        emit log_named_uint("gov1.balanceOf(address(this))", gov1.balanceOf(address(this)));
        emit log_named_uint("gov.balanceOf(address(this))", gov.balanceOf(address(this)));

        uint256 total = gov.totalSupply() - gov.balanceOf(address(this));

        emit log_named_uint("total init", total);

        // need a function to calculate underlyings
        // burnt from each side because of gov-eth lp and govw/s lp

        if (redeemOn0) {
            total -= (gov0.balanceOf(address(this)) + burntLPGov0);
        } else {
            total -= (gov1.balanceOf(address(this)) + burntLPGov1);
        }

        emit log_named_uint("total", total);

        gov.transferFrom(msg.sender, address(this), _amt);

        emit log_named_uint("address(this).balance", address(this).balance);
        emit log_named_uint("total", total);

        uint256 returnETH = PRBMath.mulDiv(_amt, address(this).balance, total);
        emit log_named_uint("returnETH", returnETH);

        (bool success,) = msg.sender.call{value: returnETH}("");
        require(success);

        emit log_named_uint("address(this).balance", address(this).balance);
    }

    uint256 burntLPGov0;
    uint256 burntLPGov1;

    function unwind(bool redeemOn0) internal {
        // PHI-WETH  ->   PHI & WETH
        uint256 govEthLiq = govEthPool.balanceOf(address(this));
        if (govEthLiq > 0) {
            govEthPool.approve(address(uniswapRouter), type(uint256).max);
            uniswapRouter.removeLiquidity(
                address(gov), address(weth), govEthLiq, 0, 0, address(this), type(uint256).max
            );
        }

        // LP^2 -> LPs-LPw
        uint256 lpLiq = lpPool.balanceOf(address(this));
        if (lpLiq > 0) {
            lpPool.approve(address(uniswapRouter), type(uint256).max);
            uniswapRouter.removeLiquidity(address(lp0), address(lp1), lpLiq, 0, 0, address(this), type(uint256).max);
        }

        // LPs-LPw -> LP
        uint256 lpf = (redeemOn0 ? lp0 : lp1).balanceOf(address(this));
        if (lpf > 0) {
            (redeemOn0 ? lp0 : lp1).approve(address(lpSplit), type(uint256).max);
            lpSplit.redeem(lpf);
        }

        // LP -> WETHs/w
        uint256 liq = pool.balanceOf(address(this));
        if (liq > 0) {
            pool.approve(address(uniswapRouter), type(uint256).max);
            uniswapRouter.removeLiquidity(address(token0), address(token1), liq, 0, 0, address(this), type(uint256).max);
        }

        // PHIs-PHIw
        uint256 govLiq = govPool.balanceOf(address(this));
        if (govLiq > 0) {
            govPool.approve(address(uniswapRouter), type(uint256).max);
            uniswapRouter.removeLiquidity(address(gov0), address(gov1), govLiq, 0, 0, address(this), type(uint256).max);
        }

        // burnt PHIs-PHIw
        uint256 bsw0 = govPool.balanceOf(address(0));
        if (bsw0 > 0) {
            (uint256 res0, uint256 res1,) = govPool.getReserves();
            (uint256 bal0, uint256 bal1) =
                UniswapV2Utils.computeLiquidityValue(res0, res1, govPool.totalSupply(), bsw0, false, 0);

            bool token0First = govPool.token0() == address(gov0);
            burntLPGov0 = token0First ? bal0 : bal1;
            burntLPGov1 = token0First ? bal1 : bal0;

            emit log_named_uint("res0", res0);
            emit log_named_uint("res1", res1);
            emit log_named_uint("bsw0", bsw0);
            emit log_named_uint("burntLPGov0", burntLPGov0);
            emit log_named_uint("burntLPGov1", burntLPGov1);
        }

        uint256 b0 = govEthPool.balanceOf(address(0));
        if (b0 > 0) {
            (uint256 res0, uint256 res1,) = govEthPool.getReserves();
            (uint256 bal0, uint256 bal1) =
                UniswapV2Utils.computeLiquidityValue(res0, res1, govEthPool.totalSupply(), b0, false, 0);

            uint256 res = govEthPool.token0() == address(gov) ? bal0 : bal1;

            burntLPGov0 += res;
            burntLPGov1 += res;

            emit log_named_uint("res0", res0);
            emit log_named_uint("res1", res1);
            emit log_named_uint("b0", b0);
            emit log_named_uint("burntLPGov0", burntLPGov0);
            emit log_named_uint("burntLPGov1", burntLPGov1);
        }

        uint256 futAmt = (redeemOn0 ? token0 : token1).balanceOf(address(this));
        (redeemOn0 ? token0 : token1).approve(address(wethSplit), type(uint256).max);
        wethSplit.redeem(futAmt);

        // WETH -> ETH
        uint256 wethBal = weth.balanceOf(address(this));
        if (wethBal > 0) {
            weth.withdraw(wethBal);
        }
    }

    uint256 constant treasuryLPRewardBps = 100; // = 1%
    uint256 constant maxSlippage = 1000; // = 10%
    uint256 constant maxSlippageLP = 2000; // = 20%

    mapping(address => uint256) public convertersLp;

    function intendConvertToLp() public {
        uniswapOracle.update(address(token0), address(token1));
        uniswapOracle.update(address(lp0), address(lp1));
        convertersLp[msg.sender] = block.timestamp;
    }

    // keepers call to create LP tokens from contents
    // expects pool to already have liquidity
    // pays 1% of lp tokens it receives to caller
    function convertToLp() public {
        require(!oracle.isExpired());

        uint256 intended = convertersLp[msg.sender];
        uint256 elapsed = block.timestamp - intended;

        require(
            elapsed >= uniswapOracleWindowSize - 2 hours && elapsed <= uniswapOracleWindowSize + 2 hours, "not in window"
        );

        splitEth();

        uniswapOracle.update(address(token0), address(token1));
        uniswapOracle.update(address(lp0), address(lp1));

        (uint256 bal0, uint256 bal1) = (token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        (uint256 res0, uint256 res1,) = pool.getReserves();
        if (!token0First) {
            (res0, res1) = (res1, res0);
        }

        emit log_named_uint("bal0", bal0);
        emit log_named_uint("bal1", bal1);
        emit log_named_uint("res0", res0);
        emit log_named_uint("res1", res1);

        bool excessIn0 = bal0 * res1 > bal1 * res0;

        if (!excessIn0) {
            (res0, res1, bal0, bal1) = (res1, res0, bal1, bal0);
        }

        uint256 num = ((4 * bal0 * res1 * 1000) / 997 + (res0 * bal1 * 9) / 994009 + (res0 * res1 * 3988009) / 994009);

        uint256 amtIn = (Math.sqrt(PRBMath.mulDiv(res0, num, res1 + bal1)) - (res0 * (1000 + 997)) / 997) / 2;

        uint256 oracleAmtOut =
            uniswapOracle.consult(address(excessIn0 ? token0 : token1), amtIn, address(excessIn0 ? token1 : token0));

        require(oracleAmtOut != 0, "oracle price = 0");

        uint256 minAmtOut = (oracleAmtOut * (10000 - maxSlippage)) / 10000;
        uint256 amtOut = UniswapV2Utils.getAmountOut(amtIn, res0, res1);

        require(amtOut >= minAmtOut, "rebalancing price not accepted");

        uint256 b00;
        uint256 b11;

        if (excessIn0) {
            token0.transfer(address(pool), amtIn);
            pool.swap(token0First ? 0 : amtOut, token0First ? amtOut : 0, address(this), "");
            (b00, b11) = (bal0 - amtIn, bal1 + amtOut);
        } else {
            token1.transfer(address(pool), amtIn);
            pool.swap(token0First ? amtOut : 0, token0First ? 0 : amtOut, address(this), "");
            (b00, b11) = (bal1 + amtOut, bal0 - amtIn);
        }

        (,, uint256 liquidity) =
            uniswapRouter.addLiquidity(address(token0), address(token1), b00, b11, 0, 0, address(this), type(uint256).max);

        unwindLPs();

        uint256 reward = (liquidity * treasuryLPRewardBps) / 10000;
        pool.transfer(msg.sender, reward);
    }

    function splitEth() internal {
        uint256 ethBal = address(this).balance;
        if (ethBal > 0) {
            weth.deposit{value: ethBal}();
        }

        uint256 wethBal = weth.balanceOf(address(this));
        if (wethBal > 0) {
            wethSplit.mint(wethBal);
        }
    }

    function unwindLPs() internal {
        {
            uint256 bal2 = lpPool.balanceOf(address(this));
            emit log_named_uint("bal2", bal2);
            if (bal2 > 0) {
                uniswapRouter.removeLiquidity(address(lp0), address(lp1), bal2, 0, 0, address(this), type(uint256).max);
            }
        }

        (uint256 bal0, uint256 bal1) = (lp0.balanceOf(address(this)), lp1.balanceOf(address(this)));

        emit log_named_uint("bal0", bal0);
        emit log_named_uint("bal1", bal1);

        if (bal0 == bal1) {
            if (bal0 != 0) {
                lpSplit.burn(bal0);
            }
            return;
        }

        bool excessIn0 = bal0 > bal1;
        (uint256 res0, uint256 res1,) = lpPool.getReserves();

        emit log_named_uint("res0", res0);
        emit log_named_uint("res1", res1);

        if (!lp0First) {
            (res0, res1) = (res1, res0);
        }
        if (!excessIn0) {
            (res0, res1, bal0, bal1) = (res1, res0, bal1, bal0);
        }

        uint256 excess = bal0 - bal1;

        emit log_named_uint("excess", excess);
        emit log_named_uint("bal0", bal0);
        emit log_named_uint("bal1", bal1);
        emit log_named_uint("res0", res0);
        emit log_named_uint("res1", res1);

        uint256 num0 = (1000 * res0) / 997 + excess + res1;
        uint256 b = (num0 - Math.sqrt(num0 ** 2 - 4 * excess * res1)) / 2;
        uint256 out = UniswapV2Utils.getAmountOut(excess - b, res0, res1);
        emit log_named_uint("out", out);

        uint256 amtIn = excess - b;
        emit log_named_uint("amtIn", amtIn);

        {
            uint256 oracleAmtOut =
                uniswapOracle.consult(address(excessIn0 ? lp0 : lp1), amtIn, address(excessIn0 ? lp1 : lp0));
            emit log_named_uint("oracleAmtOut", oracleAmtOut);
            if (oracleAmtOut == 0) {
                return;
            }

            uint256 minAmtOut = (oracleAmtOut * (10000 - maxSlippageLP)) / 10000;
            emit log_named_uint("minAmtOut", minAmtOut);
            if (out < minAmtOut) {
                return;
            }
            if (out < amtIn / 2) {
                return;
            }
        }

        (excessIn0 ? lp0 : lp1).transfer(address(lpPool), amtIn);
        lpPool.swap(excessIn0 == lp0First ? 0 : out, excessIn0 == lp0First ? out : 0, address(this), "");

        emit log_named_uint("bal0 - amtIn", bal0 - amtIn);
        emit log_named_uint("bal1 + out", bal1 + out);

        lpSplit.burn(Math.min(bal1 + out, bal0 - amtIn));
    }
}
