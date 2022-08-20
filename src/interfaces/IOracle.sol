pragma solidity >=0.5.16;

interface IOracle {
    function isExpired() external view returns (bool);

    function isPoS() external view returns (bool);

    function isPoWFork() external view returns (bool);
}
