pragma solidity ^0.8.0;


import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./Oracle.sol";
import "./interfaces/IOracle.sol";

contract Lock {
    IERC20 public underlying;
    IOracle public oracle;


    constructor(IERC20 _underlying, IOracle _oracle){
        underlying = _underlying;
        oracle = _oracle;
    }

    mapping(address => uint) balances;

    function lock(uint amt) public {
        require(!oracle.isExpired());

        underlying.transferFrom(msg.sender, address(this), amt);
        balances[msg.sender] += amt;
    }

    function unlock(uint amt) public {
        require(oracle.isExpired());

        balances[msg.sender] -= amt;
        underlying.transfer(msg.sender, amt);
    }
}
