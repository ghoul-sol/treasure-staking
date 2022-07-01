pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/Test.sol";

contract TestUtils is Test {
    function getAccessControlErrorMsg(address _addr, bytes32 _role) public pure returns (bytes memory errorMsg) {
        errorMsg = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(uint160(_addr), 20),
            " is missing role ",
            Strings.toHexString(uint256(_role), 32)
        );
    }

    function assertMatrixEq(uint256[][] memory _matrix1, uint256[][] memory _matrix2) public {
        for (uint256 i = 0; i < _matrix1.length; i++) {
            for (uint256 j = 0; j < _matrix1[i].length; j++) {
                assertEq(_matrix1[i][j], _matrix2[i][j]);
            }
        }
    }

    function assertAddressArrayEq(address[] memory array1, address[] memory array2) public {
        for (uint256 i = 0; i < array1.length; i++) {
            assertEq(array1[i], array2[i]);
        }
    }

    function assertUint256ArrayEq(uint256[] memory array1, uint256[] memory array2) public {
        for (uint256 i = 0; i < array1.length; i++) {
            assertEq(array1[i], array2[i]);
        }
    }
}
