pragma solidity ^0.8.0;

interface IOracle {
    function isExpired() external view returns (bool);

    function isRedeemable(bool future0) external view returns (bool);
}
