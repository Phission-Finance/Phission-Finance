pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "./Factory.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../lib/utils/Math.sol";
import "../lib/utils/IWETH.sol";
import "../lib/utils/UniswapV2Utils.sol";
import "./Treasury.sol";

// TODO: use PRB muldiv to reduce rounding errors

contract Zap {
    SplitFactory splitFactory;
    IUniswapV2Router02 router;

    Split wethSplit;

    IERC20 token0;
    IERC20 token1;
    Treasury treasury;

    IERC20 gov;

    IWETH weth;

    bool token0First;
    IUniswapV2Pair pool;

    constructor(
        IUniswapV2Factory _uniswapFactory,
        IUniswapV2Router02 _uniswapRouter,
        SplitFactory _splitFactory,
        Treasury _treasury,
        IWETH _weth
    ) {
        splitFactory = _splitFactory;
        router = _uniswapRouter;
        weth = _weth;

        wethSplit = _splitFactory.splits(weth);
        (IERC20 _token0, IERC20 _token1) = wethSplit.futures();
        (token0, token1) = (_token0, _token1);

        weth.approve(address(wethSplit), type(uint256).max);
        token0.approve(address(wethSplit), type(uint256).max);
        token1.approve(address(wethSplit), type(uint256).max);

        treasury = _treasury;
        gov = treasury.gov();

        pool = IUniswapV2Pair(_uniswapFactory.getPair(address(token0), address(token1)));
        token0First = (address(token0) == pool.token0());

        pool.approve(address(router), type(uint256).max);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);

        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
    }

    fallback() external payable {}

    uint256 feeBps = 25; // = 0.25%

    // mint burn and redeem for eth functions
    function mint() external payable {
        require(msg.value > 0);
        weth.deposit{value: msg.value}();
        wethSplit.mintTo(msg.sender, msg.value);
    }

    function burn(uint256 _amt) public {
        token0.transferFrom(msg.sender, address(this), _amt);
        token1.transferFrom(msg.sender, address(this), _amt);
        wethSplit.burn(_amt);
        weth.withdraw(_amt);

        (bool success,) = msg.sender.call{value: _amt}("");
        require(success);
    }

    function redeem(bool _token0, uint256 _amt) public {
        (_token0 ? token0 : token1).transferFrom(msg.sender, address(this), _amt);
        wethSplit.redeem(_amt);
        weth.withdraw(_amt);

        (bool success,) = msg.sender.call{value: _amt}("");
        require(success);
    }

    function buy(uint256 _amt, uint256 _minAmtOut, bool _future0) public payable returns (uint256) {
        if (msg.value > 0) {
            require(msg.value == _amt, "amt != msg.value");
            weth.deposit{value: msg.value}();
        } else {
            weth.transferFrom(msg.sender, address(this), _amt);
        }

        uint256 feeAmt = (_amt * feeBps) / 1e4;
        weth.transfer(address(treasury), feeAmt);

        uint256 inAmt = _amt - feeAmt;

        wethSplit.mint(inAmt);

        (uint112 res0, uint112 res1,) = pool.getReserves();

        uint256 out;
        if (_future0) {
            token1.transfer(address(pool), inAmt);

            // t1 in t0 out
            // if token0first => res0 => t0 reserves
            // token 1 reserves = token0First ? res1 : res0
            out = UniswapV2Utils.getAmountOut(inAmt, token0First ? res1 : res0, token0First ? res0 : res1);

            // token0out = token0First ? out:0
            pool.swap(token0First ? out : 0, token0First ? 0 : out, address(msg.sender), "");

            token0.transfer(address(msg.sender), inAmt);
        } else {
            token0.transfer(address(pool), inAmt);
            out = UniswapV2Utils.getAmountOut(inAmt, token0First ? res0 : res1, token0First ? res1 : res0);
            pool.swap(token0First ? 0 : out, token0First ? out : 0, address(msg.sender), "");
            token1.transfer(address(msg.sender), inAmt);
        }

        uint256 returned = inAmt + out;
        require(returned >= _minAmtOut, "too little received");
        return returned;
    }

    function sell(uint256 _amt, uint256 _minAmtOut, bool _future0) public returns (uint256) {
        (_future0 ? token0 : token1).transferFrom(msg.sender, address(this), _amt);

        uint256 feeAmt = (_amt * feeBps) / 1e4;
        (_future0 ? token0 : token1).transfer(address(treasury), feeAmt);

        uint256 inAmt = _amt - feeAmt;
        (uint256 res0, uint256 res1,) = pool.getReserves();
        (uint256 resIn, uint256 resOut) = _future0 == token0First ? (res0, res1) : (res1, res0);

        uint256 num0 = (1000 * resIn) / 997 + inAmt + resOut;
        uint256 b = (num0 - Math.sqrt(num0 ** 2 - 4 * inAmt * resOut)) / 2;
        uint256 out = UniswapV2Utils.getAmountOut(inAmt - b, resIn, resOut);
        require(out >= _minAmtOut, "too little received");

        if (_future0) {
            token0.transfer(address(pool), inAmt - b);
            pool.swap(token0First ? 0 : out, token0First ? out : 0, address(this), "");
        } else {
            token1.transfer(address(pool), inAmt - b);
            pool.swap(token0First ? out : 0, token0First ? 0 : out, address(this), "");
        }

        // b - out = 1 unit of token being sold, not worth the gas to send the token dust
        wethSplit.burn(out);
        weth.withdraw(out);

        (bool success,) = msg.sender.call{value: out}("");
        require(success);

        return out;
    }

    function buyLP(uint256 _amt, uint256 _minAmount) public payable returns (uint256) {
        if (msg.value > 0) {
            require(msg.value == _amt, "amt != msg.value");
            weth.deposit{value: msg.value}();
        } else {
            weth.transferFrom(msg.sender, address(this), _amt);
        }

        uint256 feeAmt = (_amt * feeBps) / 1e4;
        weth.transfer(address(treasury), feeAmt);

        uint256 inAmt = _amt - feeAmt;
        wethSplit.mint(inAmt);

        (uint256 res0, uint256 res1,) = pool.getReserves();

        if (!token0First) {
            (res0, res1) = (res1, res0);
        }
        bool excessIn0 = res1 >= res0;
        if (!excessIn0) {
            (res0, res1) = (res1, res0);
        }

        if (res0 == res1) {
            (,, uint256 returned) = router.addLiquidity(
                address(token0), address(token1), inAmt, inAmt, 0, 0, address(msg.sender), type(uint256).max
            );
            return returned;
        }

        uint256 amtIn = (
            Math.sqrt(
                (
                    res0
                        * (
                            (4 * inAmt * res1 * 1000) / 997 + (res0 * inAmt * (1000 - 997) ** 2) / 997 ** 2
                                + (res0 * res1 * (1000 + 997) ** 2) / 997 ** 2
                        )
                ) / (res1 + inAmt)
            ) - (res0 * (1000 + 997)) / 997
        ) / 2;
        uint256 amtOut = UniswapV2Utils.getAmountOut(amtIn, res0, res1);

        uint256 returned;
        if (excessIn0) {
            token0.transfer(address(pool), amtIn);
            pool.swap(token0First ? 0 : amtOut, token0First ? amtOut : 0, address(this), "");

            (,, returned) = router.addLiquidity(
                address(token0),
                address(token1),
                inAmt - amtIn,
                inAmt + amtOut,
                0,
                0,
                address(msg.sender),
                type(uint256).max
            );
        } else {
            token1.transfer(address(pool), amtIn);
            pool.swap(token0First ? amtOut : 0, token0First ? 0 : amtOut, address(this), "");

            (,, returned) = router.addLiquidity(
                address(token0),
                address(token1),
                inAmt + amtOut,
                inAmt - amtIn,
                0,
                0,
                address(msg.sender),
                type(uint256).max
            );
        }

        require(returned > _minAmount, "too little received");
        return returned;
    }

    function sellLP(uint256 _amt, uint256 _minAmount) public returns (uint256) {
        pool.transferFrom(address(msg.sender), address(this), _amt);

        uint256 feeAmt = (_amt * feeBps) / 1e4;
        pool.transfer(address(treasury), feeAmt);

        uint256 inAmt = _amt - feeAmt;

        (uint256 a0, uint256 a1) = router.removeLiquidity(
            address(token0),
            address(token1),
            inAmt, // a0, a1 are ordered token0(here) token1(here)
            0,
            0,
            address(this),
            type(uint256).max
        );

        (uint256 r0, uint256 r1,) = pool.getReserves();
        if (!token0First) {
            (r0, r1) = (r1, r0);
        }
        // r0,r1 are ordered token0(pool) token1(pool), swap if token0(pool) == token1(here)

        if (a0 == a1) {
            wethSplit.burn(a0);
            weth.withdraw(a0);
            (bool success,) = msg.sender.call{value: a0}("");
            require(success);
            return a0;
        }

        bool excessIn0 = a0 > a1;
        if (excessIn0) {
            (a0, a1, r0, r1) = (a1, a0, r1, r0);
        }

        uint256 a_ = a1 ** 2;
        uint256 b_ = a1 * r0 + (1000 * a1 * r1) / 997 + a0 * a1 - a1 ** 2;
        uint256 c2_ = (1000 * a1 * r1) / 997 - (a0 * 1000 * r1) / 997;
        uint256 x = (a1 * (Math.sqrt(b_ ** 2 + 4 * a_ * c2_) - b_)) / (2 * a_);

        (excessIn0 ? token0 : token1).transfer(address(pool), x);
        uint256 out = UniswapV2Utils.getAmountOut(x, r1, r0);

        if (token0First) {
            pool.swap(excessIn0 ? 0 : out, excessIn0 ? out : 0, address(this), "");
        } else {
            pool.swap(excessIn0 ? out : 0, excessIn0 ? 0 : out, address(this), "");
        }

        uint256 res = a0 + out;
        require(res > _minAmount, "too little received");

        wethSplit.burn(res);
        weth.withdraw(res);
        (bool success,) = msg.sender.call{value: res}("");
        require(success);

        return res;
    }

    //  function stakeLP()    LP -> staked LP{s,w}
    //  function unstakeLP()  staked LP{s,w} -> LP

    //  function stakeLP2()   LP -> staked LP2
    //  function unstakeLP2() staked LP2 -> LP

    //  redeemPHI()  after expiry redeems PHI{s,w}   => add redeemTo function in treasury
}
