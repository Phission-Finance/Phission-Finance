pragma solidity ^0.8.0;

import "../interfaces/IUniswapV2Oracle.sol";

contract MockUniswapV2Oracle is IUniswapV2Oracle {
    address public t0;
    address public t1;

    uint224 public avg0;
    uint224 public avg1;

    constructor(address _t0, address _t1, uint _ret0, uint _ret1) {
        t0 = _t0;
        t1 = _t1;
        set(_ret0, _ret1);
    }

    function set(uint _ret0, uint _ret1) public {
        avg0 = uint224(_ret0);
        avg1 = uint224(_ret1);
    }

    function update() public {}

    function consult(address token, uint amountIn) external view returns (uint) {
        return (amountIn * (token == t0 ? avg0 : avg1)) >> 112;
    }
}
