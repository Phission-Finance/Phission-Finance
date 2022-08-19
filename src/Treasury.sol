pragma solidity ^0.8.0;

import "forge-std/Test.sol";

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

contract Treasury is Test {
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

    function redeem(uint256 _amt) public {
        // => need to redeem all assets, as anything accrued right before merge would be stuck otherwise

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
        // PHI-WETH  ->   PHI & WETH
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

        // TODO: just hardcode this to 1000?
        // burnt PHIs-PHIw
        uint b0 = govPool.balanceOf(address(0));
        if (b0 > 0) {
            (uint res0, uint res1,) = govPool.getReserves();

            burntLP0 = b0 * b0 / res1;
            burntLP1 = b0 * b0 / res0;
        }
    }

    uint treasuryLPRewardBps = 100; // = 1%

    uint constant maxSlippage = 1000; // = 10%
    uint constant auctionDuration = 12 hours;
    uint constant warmUp = auctionDuration / 4;

    mapping(address => uint) convertersLp;
    mapping(address => uint) convertersLp2;

    function intendConvertToLp() public {
        try wethOracle.update() {} catch {}
        convertersLp[msg.sender] = block.timestamp;
    }

    function intendConvertToLp2() public {
        try lpOracle.update() {} catch {}
        convertersLp2[msg.sender] = block.timestamp;
    }

    // auction: expects pool to already have liquidity
    // pays 1% of lp tokens it receives to caller
    function convertToLp() public {
        require(!oracle.isExpired());

        uint elapsed = block.timestamp - convertersLp[msg.sender];
        require(elapsed >= warmUp && elapsed < auctionDuration, "not in window");

        splitEth();

        try wethOracle.update() {} catch {}
        (uint bal0,uint bal1) = (token0.balanceOf(address(this)), token1.balanceOf(address(this)));
        (uint res0, uint res1,) = pool.getReserves();
        if (!token0First) (res0,  res1) = (res1, res0);


        emit log_named_uint("bal0", bal0);
        emit log_named_uint("bal1", bal1);
        emit log_named_uint("res0", res0);
        emit log_named_uint("res1", res1);

        bool excessIn0 = bal0 * res1 > bal1 * res0;

        if (!excessIn0) (res0, res1, bal0, bal1) = (res1, res0, bal1, bal0);

        uint num = (4 * bal0 * res1 * 1000 / 997 + res0 * bal1 * (1000 - 997) ** 2 / 997 ** 2 + res0 * res1 * (1000 + 997) ** 2 / 997 ** 2);
        uint amtIn = (Math.sqrt((res0 * num) / (res1 + bal1)) - res0 * (1000 + 997) / 997) / 2;

        uint oracleAmtOut = wethOracle.consult(address(excessIn0 ? token0 : token1), amtIn);

        emit log_named_uint("oracleAmtOut", oracleAmtOut);

        require(oracleAmtOut != 0, "twap price = 0");

        uint minAmtOut = oracleAmtOut * (10000 - maxSlippage) / 10000;
        uint amtOut = UniswapV2Utils.getAmountOut(amtIn, res0, res1);

        require(amtOut >= minAmtOut, "rebalancing price not accepted");

        uint b00;
        uint b11;

        if (excessIn0) {
            token0.transfer(address(pool), amtIn);
            pool.swap(token0First ? 0 : amtOut, token0First ? amtOut : 0, address(this), "");
            (b00,  b11) = (bal0 - amtIn, bal1 + amtOut);
        } else {
            token1.transfer(address(pool), amtIn);
            pool.swap(token0First ? amtOut : 0, token0First ? 0 : amtOut, address(this), "");
            (b00,  b11) = (bal1 + amtOut, bal0 - amtIn);
        }

        (, , uint liquidity) = uniswapRouter.addLiquidity(address(token0), address(token1),
            b00, b11, 0, 0,
            address(this), type(uint).max);

        uint reward = liquidity * treasuryLPRewardBps / 10000;
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

        uint elapsed = block.timestamp - convertersLp2[msg.sender];
        require(elapsed >= warmUp && elapsed < auctionDuration, "not in window");

        uint lpBal = lpPool.balanceOf(address(this));
        if (lpBal > 0) lpSplit.mint(lpBal);

        try lpOracle.update() {} catch {}
        (uint balLp0,uint balLp1) = (lp0.balanceOf(address(this)), lp1.balanceOf(address(this)));
        (uint112 res0, uint112 res1,) = lpPool.getReserves();
        if (!lp0First) (res0,  res1) = (res1, res0);

        bool excessIn0 = balLp0 * res1 > balLp1 * res0;

        // TODO: implement

        revert("not impl");
    }
}
