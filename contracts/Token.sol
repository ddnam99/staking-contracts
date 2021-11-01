//SPDX-License-Identifier: MIT
pragma solidity >=0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract Token is ERC20, AccessControl {
    constructor() ERC20("Token test", "TOKEN") {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Error: ADMIN role required");
        _;
    }

    function mint(address beneficiary, uint256 amount) public onlyAdmin {
        _mint(beneficiary, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
