/**
 *Submitted for verification at BscScan.com on 2021-05-25
*/

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

pragma solidity 0.8.20;
 

contract StratSimple is Ownable, ReentrancyGuard, Pausable {

    using SafeERC20 for IERC20;

    address public wantAddress;
    address public JPOWAddress;
    address public WSBAddress;
    address public govAddress; // timelock contract
    address public feeReceiver;

    uint256 public lastEarnBlock = 0;
    uint256 public wantLockedTotal = 0;
    uint256 public sharesTotal = 0;

    uint256 public constant ONE_IN_BPS = 10000;

    uint256 public entranceFeeFactor = 30; // 0.3% entrance fee. set in BPS
    uint256 public constant entranceFeeFactorMax = 50; // 0.5% is the max entrance fee settable. set in BPS

    constructor(
        address _JPOWAddress,
        address _WSBAddress,
        address _feeReceiver,
        address _wantAddress
    ) {
        govAddress = msg.sender;
        JPOWAddress = _JPOWAddress;
        WSBAddress = _WSBAddress;
        feeReceiver = _feeReceiver;
        wantAddress = _wantAddress;
        transferOwnership(JPOWAddress);
    }

    modifier onlyGovernance() {
        require(msg.sender == govAddress, "!gov");
        _;
    }

    // Receives new deposits from user
    function deposit(address _userAddress, uint256 _wantAmt)
        public
        onlyOwner
        whenNotPaused
        returns (uint256)
    {
        IERC20(wantAddress).safeTransferFrom(
            address(msg.sender),
            address(this),
            _wantAmt
        );

        uint256 feeAmount = _wantAmt * (entranceFeeFactor) / (ONE_IN_BPS);
        IERC20(wantAddress).safeTransfer(feeReceiver, feeAmount);
        uint256 sharesAdded = _wantAmt - (feeAmount);

        sharesTotal = sharesTotal + (sharesAdded);
        wantLockedTotal = wantLockedTotal + (sharesAdded);

        return sharesAdded;
    }


    function withdraw(address _userAddress, uint256 _wantAmt)
        public
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        require(_wantAmt > 0, "_wantAmt <= 0");

        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }

        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }

        uint256 sharesRemoved = _wantAmt;
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        sharesTotal = sharesTotal - (sharesRemoved);
        wantLockedTotal = wantLockedTotal - (_wantAmt);

        IERC20(wantAddress).safeTransfer(JPOWAddress, _wantAmt);

        return sharesRemoved;
    }

    function pause() public onlyGovernance {
        _pause();
    }

    function unpause() external onlyGovernance {
        _unpause();
    }

    function setEntranceFeeFactor(uint256 _entranceFeeFactor) public onlyGovernance {
        require(_entranceFeeFactor <= entranceFeeFactorMax, "!safe - too high");
        entranceFeeFactor = _entranceFeeFactor;
    }

    function setGov(address _govAddress) public onlyGovernance {
        govAddress = _govAddress;
    }

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) public onlyGovernance {
        require(_token != wantAddress, "!safe");
        IERC20(_token).safeTransfer(_to, _amount);
    }
}