pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721Mintable is ERC721("n", "s") {
    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}
