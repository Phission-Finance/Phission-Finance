pragma solidity ^0.8.0;

import "./Factory.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "../lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../lib/utils/Math.sol";
import "../lib/utils/IWETH.sol";
import "../lib/utils/UniswapV2Utils.sol";
import "./Treasury.sol";

contract Zap /*is Test*/ {
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

    constructor(IUniswapV2Factory _uniswapFactory, IUniswapV2Router02 _uniswapRouter, SplitFactory _splitFactory, Treasury _treasury, IWETH _weth) {
        splitFactory = _splitFactory;
        router = _uniswapRouter;
        weth = _weth;

        wethSplit = _splitFactory.splits(weth);
        (IERC20 _token0, IERC20 _token1) = wethSplit.futures();
        (token0, token1) = (_token0, _token1);

        weth.approve(address(wethSplit), type(uint256).max);

        treasury = _treasury;
        gov = treasury.gov();

        pool = IUniswapV2Pair(_uniswapFactory.getPair(address(token0), address(token1)));
        token0First = (address(token0) == pool.token0());

        pool.approve(address(router), type(uint).max);
        token0.approve(address(router), type(uint).max);
        token1.approve(address(router), type(uint).max);

        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        token0.approve(address(wethSplit), type(uint256).max);
        token1.approve(address(wethSplit), type(uint256).max);
    }

    fallback() external payable {}

    uint feeBps = 10; // = 0.1%

    // mint burn and redeem for eth functions, charge a small fee?
    function mint() external payable {
        require(msg.value > 0);
        weth.deposit{value : msg.value}();
        wethSplit.mintTo(msg.sender, msg.value); // will not work with testnet version
    }

    function testnet_mint() external payable {
        require(msg.value > 0);
        weth.deposit{value : msg.value}();
        wethSplit.mint(msg.value); //
        token0.transfer(msg.sender, msg.value);
        token1.transfer(msg.sender, msg.value);
    }

    function burn(uint _amt) public {
        revert();
        // TODO:
    }

    function redeem(uint _amt) public {
        revert();
        // TODO:
    }

    function buy(uint _amt, uint _minAmtOut, bool _future0) public payable {
        if (msg.value > 0) {
            require(msg.value == _amt, "amt != msg.value");
            weth.deposit{value : msg.value}();
        } else {
            weth.transferFrom(msg.sender, address(this), _amt);
        }

        uint feeAmt = _amt * feeBps / 1e4;
        weth.transfer(address(treasury), feeAmt);

        uint inAmt = _amt - feeAmt;

        wethSplit.mint(inAmt);

        (uint112 res0, uint112 res1,) = pool.getReserves();

        //        emit log_named_uint(">>res0", res0);
        //        emit log_named_uint(">>res1", res1);
        uint out;
        if (_future0) {
            //            (uint112 resIn, uint112 resOut) = token0First ? (res0, res1) : (res1, res0);
            token1.transfer(address(pool), inAmt);

            // t1 in t0 out
            // if token0first => res0 => t0 reserves
            // token 1 reserves = token0First ? res1 : res0
            out = UniswapV2Utils.getAmountOut(inAmt, token0First ? res1 : res0, token0First ? res0 : res1);

            // token0out = token0First ? out:0
            pool.swap(token0First ? out : 0, token0First ? 0 : out, address(msg.sender), "");

            token0.transfer(address(msg.sender), inAmt);
        } else {
            //            (uint112 resIn, uint112 resOut) = token0First ? (res1, res0) : (res0, res1);
            token0.transfer(address(pool), inAmt);

            out = UniswapV2Utils.getAmountOut(inAmt, token0First ? res0 : res1, token0First ? res1 : res0);

            //            pool.swap(token0First ? 0 : out, token0First ? out : 0, address(msg.sender), "");
            pool.swap(token0First ? 0 : out, token0First ? out : 0, address(msg.sender), "");

            token1.transfer(address(msg.sender), inAmt);
        }

        require(out >= _minAmtOut, "too little received");
    }


    function sell(uint _amt, uint _minAmtOut, bool _future0) public {
        (_future0 ? token0 : token1).transferFrom(msg.sender, address(this), _amt);

        uint feeAmt = _amt * feeBps / 1e4;
        (_future0 ? token0 : token1).transfer(address(treasury), feeAmt);

        uint inAmt = _amt - feeAmt;
        uint out;

        (uint res0, uint res1,) = pool.getReserves();
        if (_future0) {
            (uint resIn, uint resOut) = token0First ? (res0, res1) : (res1, res0);

            uint b = (1000 * resIn / 997 + inAmt + resOut - Math.sqrt((1000 * resIn / 997 + inAmt + resOut) ** 2 - 4 * inAmt * resOut)) / 2;
            out = UniswapV2Utils.getAmountOut(inAmt - b, resIn, resOut);
            token0.transfer(address(pool), inAmt - b);
            pool.swap(token0First ? 0 : out, token0First ? out : 0, address(this), "");
        } else {
            (uint resIn, uint resOut) = token0First ? (res1, res0) : (res0, res1);

            uint b = (1000 * resIn / 997 + inAmt + resOut - Math.sqrt((1000 * resIn / 997 + inAmt + resOut) ** 2 - 4 * inAmt * resOut)) / 2;
            out = UniswapV2Utils.getAmountOut(inAmt - b, resIn, resOut);
            token1.transfer(address(pool), inAmt - b);
            pool.swap(token0First ? out : 0, token0First ? 0 : out, address(this), "");
        }

        require(out >= _minAmtOut, "too little received");

        wethSplit.burn(out);
        weth.withdraw(weth.balanceOf(address(this)));
        address(msg.sender).call{value : address(this).balance}("");
    }

    /*
         TODO: charge flat fee on input amount
    */

    function buyLP(uint _amt, uint _minAmount) public payable {
        if (msg.value > 0) {
            require(msg.value == _amt, "amt != msg.value");
            weth.deposit{value : msg.value}();
        } else {
            weth.transferFrom(msg.sender, address(this), _amt);
        }

        uint feeAmt = _amt * feeBps / 1e4;
        weth.transfer(address(treasury), feeAmt);

        uint inAmt = _amt - feeAmt;
        wethSplit.mint(inAmt);

        (uint res0, uint res1,) = pool.getReserves();

        //        emit log_named_uint("res0", res0);
        //        emit log_named_uint("res1", res1);

        if (!token0First) (res0, res1) = (res1, res0);
        bool excessIn0 = res1 >= res0;
        if (!excessIn0) (res0, res1) = (res1, res0);

        // uintamtIn=(Math.sqrt((balR0 * (4 * balF0 * balR1 * 1000 / 997 + balR0 * balF1 * (1000 - 997) ** 2 / 997 ** 2 + balR0 * balR1 * (1000 + 997) ** 2 / 997 ** 2)) / (balR1 + balF1)) - balR0 * (1000 + 997) / 997) / 2;
        uint amtIn = (Math.sqrt((res0 * (4 * inAmt * res1 * 1000 / 997 + res0 * inAmt * (1000 - 997) ** 2 / 997 ** 2 + res0 * res1 * (1000 + 997) ** 2 / 997 ** 2)) / (res1 + inAmt)) - res0 * (1000 + 997) / 997) / 2;

        uint amtOut = UniswapV2Utils.getAmountOut(amtIn, res0, res1);
        require(amtOut > _minAmount, "too little received");

        //        emit log_named_uint("inAmt", inAmt);

        //        emit log_named_uint("amtIn", amtIn);
        //        emit log_named_uint("amtOut", amtOut);


        if (excessIn0) {
            token0.transfer(address(pool), amtIn);
            pool.swap(token0First ? 0 : amtOut, token0First ? amtOut : 0, address(this), "");

            //            emit log_named_uint("token0::this", token0.balanceOf(address(this)));
            //            emit log_named_uint("token1::this", token1.balanceOf(address(this)));

            router.addLiquidity(address(token0), address(token1),
                inAmt - amtIn, inAmt + amtOut, 0, 0,
                address(msg.sender), type(uint).max);
        } else {
            token1.transfer(address(pool), amtIn);
            pool.swap(token0First ? amtOut : 0, token0First ? 0 : amtOut, address(this), "");

            //            emit log_named_uint("token0::this", token0.balanceOf(address(this)));
            //            emit log_named_uint("token1::this", token1.balanceOf(address(this)));

            router.addLiquidity(address(token0), address(token1),
                inAmt + amtOut, inAmt - amtIn, 0, 0,
                address(msg.sender), type(uint).max);
        }

    }

    function sellLP(uint _amt, uint _minAmount) public {
        pool.transferFrom(address(msg.sender), address(this), _amt);

        uint feeAmt = _amt * feeBps / 1e4;
        pool.transfer(address(treasury), feeAmt);

        uint inAmt = _amt - feeAmt;

        (uint amount0, uint amount1) = router.removeLiquidity(address(token0), address(token1), inAmt,
            0,
            0,
            address(this),
            type(uint).max
        );


        revert("not implemented");
    }


    //  function stakeLP()    LP -> staked LP{s,w}
    //  function unstakeLP()  staked LP{s,w} -> LP

    //  function stakeLP2()   LP -> staked LP2
    //  function unstakeLP2() staked LP2 -> LP

    //  function tradeGov()

    //  gives fees to treasury based on uni pool split
}

