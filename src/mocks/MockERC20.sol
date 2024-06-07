// SPDX-License-Identifier: None

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {


	constructor() ERC20("STABULL", "STB") {
		_mint(msg.sender, 10000000 ether);
	}

	function mint(address to, uint256 amount) external {
		_mint(to, amount);
	}

	function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}