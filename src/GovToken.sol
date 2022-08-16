pragma solidity ^0.8.0;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract GovToken is ERC20 {
    address owner;

    constructor() ERC20("Phission Token", "PHI") {
        owner = msg.sender;
    }

    modifier isOwner() {
        require(msg.sender == owner);
        _;
    }

    function mint(address to, uint256 wad) public isOwner() {
        _mint(to, wad);
    }

    function burn(address from, uint256 wad) public isOwner() {
        _burn(from, wad);
    }
}
