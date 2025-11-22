// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DefiStableCoin is ERC20, Ownable {
    error DefiStableCoin__MustBeMoreThanZero();
    error DefiStableCoin__InsufficientBalance();
    error DefiStableCoin__InvalidAddress();

    constructor(string memory name_, string memory symbol_, address _sender) ERC20(name_, symbol_) Ownable(_sender) {}

    function burn(address _user, uint256 _amount) public onlyOwner {
        if (_amount <= 0) {
            revert DefiStableCoin__MustBeMoreThanZero();
        }
        _burn(_user, _amount);
    }

    function mint(address _to, uint256 _amount) public onlyOwner returns (bool success) {
        if (_to == address(0)) {
            revert DefiStableCoin__InvalidAddress();
        }
        if (_amount <= 0) {
            revert DefiStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        success = true;
    }
}
