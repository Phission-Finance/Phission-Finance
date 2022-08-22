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
    Split lpSplit;

    IERC20 token0;
    IERC20 token1;
    IERC20 lpToken0;
    IERC20 lpToken1;
    Treasury treasury;

    IERC20 gov;

    IWETH weth;

    bool token0First;
    bool lpToken0First;
    IUniswapV2Pair pool;
    IUniswapV2Pair lpPool;

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

        lpSplit = _splitFactory.splits(IERC20(address(pool)));
        (IERC20 _lpToken0, IERC20 _lpToken1) = lpSplit.futures();
        (lpToken0, lpToken1) = (_lpToken0, _lpToken1);

        lpPool = IUniswapV2Pair(_uniswapFactory.getPair(address(lpToken0), address(lpToken1)));
        lpToken0First = (address(lpToken0) == lpPool.token0());

        pool.approve(address(lpSplit), type(uint256).max);
        lpPool.approve(address(router), type(uint256).max);
        lpToken0.approve(address(router), type(uint256).max);
        lpToken1.approve(address(router), type(uint256).max);

        lpToken0.approve(address(lpPool), type(uint256).max);
        lpToken1.approve(address(lpPool), type(uint256).max);
        lpToken0.approve(address(lpSplit), type(uint256).max);
        lpToken1.approve(address(lpSplit), type(uint256).max);

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

    struct BuySellInput {
        uint256 _amt;
        uint256 _minAmtOut;
        bool _future0;
        IERC20 _inputToken;
        IERC20 _token0;
        IERC20 _token1;
        IUniswapV2Pair _pool;
        Split _split;
        bool _token0First;
    }

    struct SellLPInput {
        uint256 _amt;
        uint256 _minAmount;
        IUniswapV2Pair _pool;
        IERC20 _token0;
        IERC20 _token1;
        bool _token0First;
        IERC20 _inputToken;
        Split _split;
    }

    struct BuyLPInput {
        uint256 _amt;
        uint256 _minAmount;
        IERC20 _inputToken;
        Split _split;
        IUniswapV2Pair _pool;
        bool _token0First;
        IERC20 _token0;
        IERC20 _token1;
    }

    function _buy(BuySellInput memory input) internal returns (uint256) {
        uint256 feeAmt = (input._amt * feeBps) / 1e4;
        input._inputToken.transfer(address(treasury), feeAmt);

        uint256 inAmt = input._amt - feeAmt;

        input._split.mint(inAmt);

        (uint112 res0, uint112 res1,) = input._pool.getReserves();

        uint256 out;
        if (input._future0) {
            input._token1.transfer(address(input._pool), inAmt);

            // t1 in t0 out
            // if token0first => res0 => t0 reserves
            // token 1 reserves = token0First ? res1 : res0
            out = UniswapV2Utils.getAmountOut(inAmt, input._token0First ? res1 : res0, input._token0First ? res0 : res1);

            // token0out = input._token0First ? out:0
            input._pool.swap(input._token0First ? out : 0, input._token0First ? 0 : out, address(msg.sender), "");

            input._token0.transfer(address(msg.sender), inAmt);
        } else {
            input._token0.transfer(address(input._pool), inAmt);
            out = UniswapV2Utils.getAmountOut(inAmt, input._token0First ? res0 : res1, input._token0First ? res1 : res0);
            input._pool.swap(input._token0First ? 0 : out, input._token0First ? out : 0, address(msg.sender), "");
            input._token1.transfer(address(msg.sender), inAmt);
        }

        uint256 returned = inAmt + out;
        require(returned >= input._minAmtOut, "too little received");
        return returned;
    }

    function _sell(BuySellInput memory input) internal returns (uint256) {
        (input._future0 ? input._token0 : input._token1).transferFrom(msg.sender, address(this), input._amt);

        uint256 feeAmt = (input._amt * feeBps) / 1e4;
        (input._future0 ? input._token0 : input._token1).transfer(address(treasury), feeAmt);

        uint256 inAmt = input._amt - feeAmt;
        (uint256 res0, uint256 res1,) = input._pool.getReserves();
        (uint256 resIn, uint256 resOut) = input._future0 == input._token0First ? (res0, res1) : (res1, res0);

        uint256 num0 = (1000 * resIn) / 997 + inAmt + resOut;
        uint256 b = (num0 - Math.sqrt(num0 ** 2 - 4 * inAmt * resOut)) / 2;
        uint256 out = UniswapV2Utils.getAmountOut(inAmt - b, resIn, resOut);
        require(out >= input._minAmtOut, "too little received");

        if (input._future0) {
            input._token0.transfer(address(input._pool), inAmt - b);
            input._pool.swap(input._token0First ? 0 : out, input._token0First ? out : 0, address(this), "");
        } else {
            input._token1.transfer(address(input._pool), inAmt - b);
            input._pool.swap(input._token0First ? out : 0, input._token0First ? 0 : out, address(this), "");
        }

        // b - out = 1 unit of token being sold, not worth the gas to send the token dust
        input._split.burn(out);

        return out;
    }

    function _buyLP(BuyLPInput memory input) internal returns (uint256) {
        uint256 feeAmt = (input._amt * feeBps) / 1e4;
        input._inputToken.transfer(address(treasury), feeAmt);

        uint256 inAmt = input._amt - feeAmt;
        input._split.mint(inAmt);

        (uint256 res0, uint256 res1,) = input._pool.getReserves();

        if (!input._token0First) {
            (res0, res1) = (res1, res0);
        }
        bool excessIn0 = res1 >= res0;
        if (!excessIn0) {
            (res0, res1) = (res1, res0);
        }

        if (res0 == res1) {
            (,, uint256 returned) = router.addLiquidity(
                address(input._token0), address(input._token1), inAmt, inAmt, 0, 0, address(msg.sender), type(uint256).max
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
            input._token0.transfer(address(input._pool), amtIn);
            input._pool.swap(input._token0First ? 0 : amtOut, input._token0First ? amtOut : 0, address(this), "");

            (,, returned) = router.addLiquidity(
                address(input._token0),
                address(input._token1),
                inAmt - amtIn,
                inAmt + amtOut,
                0,
                0,
                address(msg.sender),
                type(uint256).max
            );
        } else {
            input._token1.transfer(address(input._pool), amtIn);
            input._pool.swap(input._token0First ? amtOut : 0, input._token0First ? 0 : amtOut, address(this), "");

            (,, returned) = router.addLiquidity(
                address(input._token0),
                address(input._token1),
                inAmt + amtOut,
                inAmt - amtIn,
                0,
                0,
                address(msg.sender),
                type(uint256).max
            );
        }

        require(returned > input._minAmount, "too little received");
        return returned;
    }

    function _sellLP(SellLPInput memory input) public returns (uint256) {
        // transfer LP2 tokens in
        input._pool.transferFrom(address(msg.sender), address(this), input._amt);

        uint256 feeAmt = (input._amt * feeBps) / 1e4;
        input._pool.transfer(address(treasury), feeAmt);

        uint256 inAmt = input._amt - feeAmt;

        (uint256 a0, uint256 a1) = router.removeLiquidity(
            address(input._token0),
            address(input._token1),
            inAmt, // a0, a1 are ordered input._token0(here) input._token1(here)
            0,
            0,
            address(this),
            type(uint256).max
        );

        (uint256 r0, uint256 r1,) = input._pool.getReserves();
        if (!input._token0First) {
            (r0, r1) = (r1, r0);
        }
        // r0,r1 are ordered input._token0(input._pool) input._token1(input._pool), swap if input._token0(input._pool) == input._token1(here)

        if (a0 == a1) {
            input._split.burn(a0);
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

        (excessIn0 ? input._token0 : input._token1).transfer(address(input._pool), x);
        uint256 out = UniswapV2Utils.getAmountOut(x, r1, r0);

        if (input._token0First) {
            input._pool.swap(excessIn0 ? 0 : out, excessIn0 ? out : 0, address(this), "");
        } else {
            input._pool.swap(excessIn0 ? out : 0, excessIn0 ? 0 : out, address(this), "");
        }

        uint256 res = a0 + out;
        require(res > input._minAmount, "too little received");

        input._split.burn(res);

        return res;
    }

    // ETH -> WETH{w,s}
    function buy(uint256 _amt, uint256 _minAmtOut, bool _future0) public payable returns (uint256) {
        if (msg.value > 0) {
            require(msg.value == _amt, "amt != msg.value");
            weth.deposit{value: msg.value}();
        } else {
            weth.transferFrom(msg.sender, address(this), _amt);
        }

        BuySellInput memory input = BuySellInput({
            _amt: _amt,
            _minAmtOut: _minAmtOut,
            _future0: _future0,
            _inputToken: weth,
            _token0: token0,
            _token1: token1,
            _pool: pool,
            _split: wethSplit,
            _token0First: token0First
        });

        return _buy(input);
    }

    function sell(uint256 _amt, uint256 _minAmtOut, bool _future0) public returns (uint256) {
        BuySellInput memory input = BuySellInput({
            _amt: _amt,
            _minAmtOut: _minAmtOut,
            _future0: _future0,
            _inputToken: weth,
            _token0: token0,
            _token1: token1,
            _pool: pool,
            _split: wethSplit,
            _token0First: token0First
        });
        uint256 out = _sell(input);

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

        BuyLPInput memory input = BuyLPInput({
            _amt: _amt,
            _minAmount: _minAmount,
            _inputToken: weth,
            _split: wethSplit,
            _pool: pool,
            _token0First: token0First,
            _token0: token0,
            _token1: token1
        });

        return _buyLP(input);
    }

    function sellLP(uint256 _amt, uint256 _minAmount) public returns (uint256) {
        SellLPInput memory input = SellLPInput({
            _amt: _amt,
            _minAmount: _minAmount,
            _pool: pool,
            _token0: token0,
            _token1: token1,
            _token0First: token0First,
            _inputToken: weth,
            _split: wethSplit
        });

        uint256 res = _sellLP(input);

        weth.withdraw(res);
        (bool success,) = msg.sender.call{value: res}("");
        require(success);

        return res;
    }

    function stakeLP(uint256 _amt, uint256 _minAmtOut, bool _future0) public payable returns (uint256) {
        // transfer the lp tokens in
        pool.transferFrom(msg.sender, address(this), _amt);

        BuySellInput memory input = BuySellInput({
            _amt: _amt,
            _minAmtOut: _minAmtOut,
            _future0: _future0,
            _inputToken: IERC20(address(pool)),
            _token0: lpToken0,
            _token1: lpToken1,
            _pool: lpPool,
            _split: lpSplit,
            _token0First: lpToken0First
        });

        return _buy(input);
    }

    // staked LP{s,w} -> LP
    function unstakeLP(uint256 _amt, uint256 _minAmtOut, bool _future0) public returns (uint256) {
        BuySellInput memory input = BuySellInput({
            _amt: _amt,
            _minAmtOut: _minAmtOut,
            _future0: _future0,
            _inputToken: IERC20(address(pool)),
            _token0: lpToken0,
            _token1: lpToken1,
            _pool: lpPool,
            _split: lpSplit,
            _token0First: lpToken0First
        });

        uint256 out = _sell(input);

        pool.transfer(msg.sender, out);

        return out;
    }

    // LP -> LP^2
    function stakeLP2(uint256 _amt, uint256 _minAmount) public payable returns (uint256) {
        // transfer lp tokens in
        pool.transferFrom(msg.sender, address(this), _amt);

        BuyLPInput memory input = BuyLPInput({
            _amt: _amt,
            _minAmount: _minAmount,
            _inputToken: IERC20(address(pool)),
            _split: lpSplit,
            _pool: lpPool,
            _token0First: lpToken0First,
            _token0: lpToken0,
            _token1: lpToken1
        });

        return _buyLP(input);
    }

    //  staked LP2 -> LP
    function unstakeLP2(uint256 _amt, uint256 _minAmount) public returns (uint256) {
        SellLPInput memory input = SellLPInput({
            _amt: _amt,
            _minAmount: _minAmount,
            _pool: lpPool,
            _token0: lpToken0,
            _token1: lpToken1,
            _token0First: lpToken0First,
            _inputToken: IERC20(address(pool)),
            _split: lpSplit
        });

        uint256 res = _sellLP(input);

        pool.transfer(msg.sender, res);

        return res;
    }

    //  redeemPHI()  after expiry redeems PHI{s,w}   => add redeemTo function in treasury
}
