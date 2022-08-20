pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./fERC20.sol";
import "./Oracle.sol";

struct Futures {
    fERC20 PoW;
    fERC20 PoS;
}

/// @dev this can split both weth and the LP token
contract Split {
    Futures private _futures;
    IERC20 public underlying;
    IOracle public oracle;

    constructor(IERC20 _underlying, IOracle _oracle) {
        require(!_oracle.isExpired());
        oracle = _oracle;
        underlying = _underlying;
        _futures.PoS = new fERC20(_underlying, oracle, true);
        _futures.PoW = new fERC20(_underlying, oracle, false);
    }

    function futures() public view returns(Futures memory) {
        return _futures;
    }

    function mint(uint256 _wad) public {
        _futures.PoS.mint(msg.sender, _wad);
        _futures.PoW.mint(msg.sender, _wad);
        underlying.transferFrom(msg.sender, address(this), _wad);
    }

    function mintTo(address _who, uint256 _wad) public {
        _futures.PoS.mint(_who, _wad);
        _futures.PoW.mint(_who, _wad);
        underlying.transferFrom(msg.sender, address(this), _wad);
    }

    function burn(uint256 _wad) public {
        require(!oracle.isExpired());

        _futures.PoS.burn(msg.sender, _wad);
        _futures.PoW.burn(msg.sender, _wad);
        underlying.transfer(msg.sender, _wad);
    }

    function redeem(uint256 _wad) public {
        // the token checks that the oracle has expired
        if (_futures.PoS.isRedeemable()) {
            _futures.PoS.burn(msg.sender, _wad);
        }
        if (_futures.PoW.isRedeemable()) {
            _futures.PoW.burn(msg.sender, _wad);
        }

        underlying.transfer(msg.sender, _wad);
    }
}
