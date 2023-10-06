// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Utils {
    error ZeroAddressNotAllowed();
    error ZeroValueNotAllowed();

    function assembly_checkAddressNotZero(address _toCheck) public pure /* returns (bool success) */ {
        assembly {
            if iszero(_toCheck) {
                // Error signature: ZeroAddressNotAllowed()
                let signature := 0x8579befe00000000000000000000000000000000000000000000000000000000
                let size := 0x4 // The size of the error signature

                let ptr := mload(0x40) // Get the free memory pointer
                mstore(ptr, signature) // Store the error signature in memory
                revert(ptr, size) // Revert the transaction with the error signature
            }
        }

        // return true;
    }

    function assembly_checkValueNotZero(uint256 _value) public pure /* returns (bool) */ {
        assembly {
            if iszero(_value) {
                // Error signature: ZeroValueNotAllowed()
                let signature := 0x9cf8540c00000000000000000000000000000000000000000000000000000000
                let size := 0x4

                let ptr := mload(0x40) // Get the free memory pointer
                mstore(ptr, signature)
                revert(ptr, size) // Revert the transaction with the error signature
            }
        }

        // return true;
    }
}
