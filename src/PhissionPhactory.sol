pragma solidity ^0.8.0;

import "./Treasury.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract PhissionPhactory {
    SplitFactory public sf;
    Split public split;
    IERC20 public weth;
    Treasury public treasury;
    IOracle public oracle;


    constructor(IOracle _oracle, IERC20 _weth) {
        oracle = _oracle;
        weth = _weth;
        sf = new SplitFactory(_oracle);
        // split = sf.get()
        // TODO: move lock logic to lock team allocation here

    }
}
