pragma solidity ^0.8.0;

import "./interfaces/IOracle.sol";

contract ForkOracle is IOracle {
    uint256 constant MIN_RANDAO = type(uint64).max; // TODO: set to max uint64 for tests // live = 2**128
    uint256 public immutable deployChainId = block.chainid;
    uint256 public immutable deployTime = block.timestamp;

    function isPoS() public view returns (bool) {
        return block.difficulty >= MIN_RANDAO;
    }

    function isPoWFork() public view returns (bool) {
        return block.chainid != deployChainId;
    }

    function isExpired() public view returns (bool) {
        return isPoS() || isPoWFork() || block.timestamp - deployTime > 365 days;
    }
}
