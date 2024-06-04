//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract Authorizable is Ownable2Step {

    error UnAuthorized();

    mapping(address => bool) private authorized;

    modifier onlyAuthorized() {
        if(!authorized[msg.sender] ||  owner() != msg.sender) revert UnAuthorized();
        _;
    }
    
    function isAuthorised(address _authAdd) public view returns(bool _isAuth){
        _isAuth = (authorized[_authAdd] ||  owner() == _authAdd) ;
    }

    function addAuthorized(address _toAdd) onlyOwner public {
        require(_toAdd != address(0));
        authorized[_toAdd] = true;
    }

    function removeAuthorized(address _toRemove) onlyOwner public {
        require(_toRemove != msg.sender);
        authorized[_toRemove] = false;
    }

}