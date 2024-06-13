// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title Authorizable
 * @dev Contract module which provides a basic authorization control mechanism, 
 * where there is an account (an owner) that can grant exclusive access to 
 * specific functions to authorised accounts.
 */
contract Authorizable is Ownable2Step {
    error UnAuthorised();

    mapping(address => bool) private authorised;

    /**
     * @dev Modifier to make a function callable only by authorised accounts.
     */
    modifier onlyAuthorised() {
        if (!isAuthorised(msg.sender)) {
            revert UnAuthorised();
        }
        _;
    }

    /**
     * @dev Adds an address to the list of authorised accounts.
     * Can only be called by the current owner.
     * @param _toAdd The address to add to the authorised list.
     */
    function addAuthorised(address _toAdd) public onlyOwner {
        require(_toAdd != address(0), "Zero Address inserted");
        authorised[_toAdd] = true;
    }

    /**
     * @dev Removes an address from the list of authorised accounts.
     * Can only be called by the current owner.
     * @param _toRemove The address to remove from the authorised list.
     */
    function removeAuthorised(address _toRemove) public onlyOwner {
        require(_toRemove != msg.sender, "Owner cannot be removed");
        authorised[_toRemove] = false;
    }

    /**
     * @dev Checks if an address is authorised.
     * @param _authAdd The address to check.
     * @return _isAuth True if the address is authorised, false otherwise.
     */
    function isAuthorised(address _authAdd) public view returns (bool _isAuth) {
        _isAuth = (authorised[_authAdd] || owner() == _authAdd);
    }
}
