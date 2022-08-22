pragma solidity ^0.8.0;

import "../lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

interface IUniswapV2SlidingOracle {
    struct Observation {
        uint timestamp;
        uint price0Cumulative;
        uint price1Cumulative;
    }

    function factory() external returns (address);

    function windowSize() external returns (uint);

    function granularity() external returns (uint8);

    function periodSize() external returns (uint);

    function observationIndexOf(uint timestamp) external view returns (uint8 index);

    function update(address tokenA, address tokenB) external;

    function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut);
}
