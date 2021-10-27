// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2;

library AddressesLib {
    function add(address[] storage self, address element) internal {
        if (!exists(self, element)) self.push(element);
    }

    function exists(address[] storage self, address element) internal view returns (bool) {
        for (uint256 i = 0; i < self.length; i++) {
            if (self[i] == element) {
                return true;
            }
        }
        return false;
    }
}
