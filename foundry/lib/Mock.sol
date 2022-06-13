pragma solidity ^0.8.0;

import "forge-std/Vm.sol";

contract Mock {
    address constant HEVM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256('hevm cheat code')))));

    constructor(string memory _label) {
        Vm(HEVM_ADDRESS).label(address(this), _label);
    }
}
