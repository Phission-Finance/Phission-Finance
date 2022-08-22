pragma solidity =0.6.6;

import "forge-std/Test.sol";
import "../UniswapV2SlidingOracle.sol";
import '../../lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

contract UniswapSlidingWindowOracleTest_fork is Test {
    UniswapV2SlidingOracle oracle;
    IUniswapV2Factory univ2fac = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        // window = 6hours
        // gran = 6
    }

    mapping(uint => uint)  isValid;

    function test_fork_valid_price_loop_1() public {
        return;

        uint bn = block.number;
        uint TOTAL = 3200;

        uint fromDelay = 2 hours;
        uint toDelay = 12 hours;
        uint intervalDelay = 10 minutes;

        for (uint delay = fromDelay; delay <= toDelay; delay += intervalDelay) isValid[delay] = 1;

        for (uint i = 0; i <= TOTAL; i += 50) {
            vm.rollFork(bn - i);

            oracle = new UniswapV2SlidingOracle(univ2fac);

            uint ts = block.timestamp;
            IUniswapV2Pair(univ2fac.getPair(weth, usdc)).sync();
            oracle.update(weth, usdc);

            for (uint delay = fromDelay; delay <= toDelay; delay += intervalDelay) {
                uint jitter = uint(blockhash(block.number)) % (intervalDelay);
                vm.warp(ts + delay - intervalDelay / 2);

                IUniswapV2Pair(univ2fac.getPair(weth, usdc)).sync();
                oracle.update(weth, usdc);

                uint jitter2 = uint(blockhash(block.number - 1)) % (intervalDelay);
                vm.warp(ts + delay * 2 + jitter2 - intervalDelay / 2);

                try oracle.consult(weth, 1 ether, usdc) returns (uint price) {
                    isValid[delay] *= 1;
                } catch {
                    isValid[delay] *= 0;
                }
            }
        }

        for (uint delay = fromDelay; delay <= toDelay; delay += intervalDelay) if (isValid[delay] == 1) console.log(">>>", delay);

        /*
            => calling update on an oracle twice before convertToLP works for delays between
            > 9000 2.5h
            > 18000 5h

            => with pseudo random jitter on top of delay
            > 12600    3.5h
            > 17400    4.8h
        */
    }


}
