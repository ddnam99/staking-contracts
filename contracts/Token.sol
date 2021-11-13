//SPDX-License-Identifier: MIT
pragma solidity >=0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor() ERC20("TOKEN TEST", "TOKEN") {
    }

    function mint(address beneficiary, uint256 amount) public {
        _mint(beneficiary, amount);
    }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }
}
