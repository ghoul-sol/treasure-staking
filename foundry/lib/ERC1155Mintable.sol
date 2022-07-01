pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol';

contract ERC1155Mintable is ERC1155("//uri"), ERC1155Burnable {
    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount, bytes(""));
    }
}
