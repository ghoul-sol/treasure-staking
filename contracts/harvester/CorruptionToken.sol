// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract CorruptionToken is ERC20, Ownable {
    constructor(string memory name, string memory symbol, address owner) ERC20(name, symbol) {
        transferOwnership(owner);
    }

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }
}
