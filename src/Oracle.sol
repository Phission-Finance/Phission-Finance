pragma solidity ^0.8.0;

contract ForkOracle {
    bool expired = false;
    uint256 deployTime;

    uint256 MIN_RANDAO = 18446744073709551615; // TODO: set to max uint64 for tests // live = 2**128

    constructor() {
        deployTime = block.timestamp;
    }

    function setExpired() public {
        require((block.timestamp - deployTime > 365 * 24 * 60 * 60) || isExpired());
        expired = true;
    }

    function isExpired() public view returns (bool) {
        return expired || block.chainid != 1 || block.difficulty >= MIN_RANDAO;
    }

    function isRedeemable(bool isPos) public view returns (bool) {
        return isPos == (block.chainid == 1);
    }
}
