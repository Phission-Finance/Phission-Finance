pragma solidity ^0.8.0;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./Split.sol";
import "./Oracle.sol";
import "./interfaces/IOracle.sol";

enum FutureType {
    PoS,
    PoW
}

function suffix(string memory str, bool isPos, bool name) pure returns (string memory) {
    return
        name
        ? string(abi.encodePacked(str, isPos ? " POS" : " POW"))
        : string(abi.encodePacked(str, isPos ? "s" : "w"));
}

contract fERC20 is ERC20 {
    
    FutureType public immutable futureType;
    address public owner;
    IOracle public oracle;

    constructor(IERC20 _underlying, IOracle _oracle, bool isPos)
        ERC20(
            suffix(ERC20(address(_underlying)).name(), isPos, true),
            suffix(ERC20(address(_underlying)).symbol(), isPos, false)
        )
    {
        owner = msg.sender;
        futureType = isPos ? FutureType.PoS: FutureType.PoW;
        oracle = _oracle;
    }

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    function mint(address to, uint256 wad) public isOwner {
        _mint(to, wad);
    }

    function burn(address from, uint256 wad) public isOwner {
        _burn(from, wad);
    }

    function isRedeemable() public returns (bool) {
        bool redeemable = futureType == FutureType.PoS ? oracle.isPoS() : oracle.isPoWFork();
        return redeemable && oracle.isExpired();
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (to != address(0) && !isRedeemable()) {
            unchecked {
                _burn(to, amount);
            }
        }
    }
}
