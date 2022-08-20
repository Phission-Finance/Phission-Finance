pragma solidity ^0.8.0;

import "../interfaces/IOracle.sol";

contract MockOracle is IOracle {
    bool ret0;
    bool ret1;
    bool ret2;

    address public owner;

    constructor(bool _ret0, bool _ret1, bool _ret2) {
        owner = msg.sender;
        set(_ret0, _ret1, _ret2);
    }

    function set(bool _ret0, bool _ret1, bool _ret2) public {
        ret0 = _ret0;
        ret1 = _ret1;
        ret2 = _ret2;
        require(owner == msg.sender);
    }

    function isExpired() public view returns (bool) {
        return ret0;
    }

    function isPoS() public view returns (bool) {
        return ret1;
    }

    function isPoWFork() public view returns (bool) {
        return ret2;
    }
}
