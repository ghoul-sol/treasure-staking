pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20("n", "s") {
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
