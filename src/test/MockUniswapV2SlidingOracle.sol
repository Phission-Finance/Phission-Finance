pragma solidity ^0.8.0;

import "../IUniswapV2SlidingOracle.sol";
import "forge-std/Test.sol";

contract MockUniswapV2SlidingOracle is IUniswapV2SlidingOracle, Test {
    mapping(bytes32 => uint224)  public avg; // pair hash to avg price,

    uint public updated = 0;

    address public factory;
    uint public windowSize;
    uint8 public granularity;
    uint public periodSize;

    constructor(address factory_, uint windowSize_, uint8 granularity_) {
        factory = factory_;
        windowSize = windowSize_;
        granularity = granularity_;
        periodSize = windowSize_ / granularity_;
    }

    function set(address _token0, address _token1, uint256 _ret0, uint256 _ret1) public {
        emit log_string("MOCK_UNISWAP_ORACLE::set");
        emit log_named_address("_token0", _token0);
        emit log_named_address("_token1", _token1);
        require(_token1 != _token0, "[[[[[[]]]]]]");

        emit log_named_bytes32("_token0, _token1", keccak256(abi.encode(_token0, _token1)));
        emit log_named_bytes32("_token1, _token0", keccak256(abi.encode(_token1, _token0)));
        emit log_named_uint("ret0", _ret0);
        emit log_named_uint("ret1", _ret1);

        avg[keccak256(abi.encode(_token0, _token1))] = uint224(_ret0);
        avg[keccak256(abi.encode(_token1, _token0))] = uint224(_ret1);
    }

    function observationIndexOf(uint timestamp) public view returns (uint8 index) {
        uint epochPeriod = timestamp / periodSize;
        return uint8(epochPeriod % granularity);
    }

    function update(address _token0, address _token1) public {
        updated++;
    }

    function consult(address _token0, uint256 _amountIn, address _token1) external view returns (uint256) {
        return (_amountIn * avg[keccak256(abi.encode(_token0, _token1))]) >> 112;
    }
}
