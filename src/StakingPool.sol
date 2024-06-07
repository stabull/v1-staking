// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

pragma solidity 0.8.20;


contract StakingPool is Ownable, ReentrancyGuard, Pausable {

    using SafeERC20 for IERC20;

    error ZeroAddressInserted();
    error ZeroAmountInserted();
    error StakingTokenTransfer();
    error FeeLimitExceeded();
    error onlyGovernanceAuthorized();

    address public tokenAddress;
    address public stakingFactoryAddress;
    address public rewardTokenAddress;
    address public govAddress; // timelock contract
    address public feeReceiver;

    uint256 public lastEarnBlock = 0;
    uint256 public tokenLockedTotal = 0;
    uint256 public sharesTotal = 0;

    uint256 public constant ONE_IN_BPS = 10000;

    uint256 public entranceFeeFactor = 30; // 0.3% entrance fee. set in BPS
    uint256 public constant entranceFeeFactorMax = 50; // 0.5% is the max entrance fee settable. set in BPS

    uint256 public exitFeeFactor = 30; // 0.3% exit fee. set in BPS
    uint256 public constant exitFeeFactorMax = 50; // 0.5% is the max exit fee settable. set in BPS
    uint256 public constant WITHDRAW_FEE_PERIOD = 72 hours; //amount of time that a user must wait after a deposit to not be charged the exit fee

    mapping(address => uint256) public lastUserDepositTime;

    modifier zeroAddressCheck(address _address) {
        if (_address == address(0)) {
            revert ZeroAddressInserted();
        }
        _;
    }

    modifier zeroAmountCheck(uint256 amount) {
        if (amount == 0) {
            revert ZeroAmountInserted();
        }
        _;
    }

    modifier onlyGovernance() {
        if(msg.sender != govAddress)  revert onlyGovernanceAuthorized();
        _;
    }

    /// @dev Initializes the StakingPool with essential parameters.
    /// @param _stakingFactoryAddress Address of the StakingFactory contract.
    /// @param _rewardTokenAddress Address of the reward token.
    /// @param _feeReceiver Address to receive staking fees.
    /// @param _tokenAddress Address of the token to be staked.
    constructor(
        address _stakingFactoryAddress,
        address _rewardTokenAddress,
        address _feeReceiver,
        address _tokenAddress
    ) zeroAddressCheck(_stakingFactoryAddress) 
        zeroAddressCheck(_rewardTokenAddress) 
        zeroAddressCheck(_feeReceiver) 
        zeroAddressCheck(_tokenAddress)
    {
        govAddress = msg.sender;
        stakingFactoryAddress = _stakingFactoryAddress;
        rewardTokenAddress = _rewardTokenAddress;
        feeReceiver = _feeReceiver;
        tokenAddress = _tokenAddress;
        transferOwnership(stakingFactoryAddress);
    }

    /// @notice Allows a user to deposit tokens for staking.
    /// @dev Only callable by the owner (StakingFactory).
    /// @param _userAddress Address of the user depositing tokens.
    /// @param _tokenAmt Amount of tokens to be deposited.
    /// @return sharesAdded Amount of shares added to the user's balance.
    function deposit( address _userAddress,uint256 _tokenAmt)
        public
        onlyOwner
        whenNotPaused
        zeroAmountCheck(_tokenAmt)
        zeroAddressCheck(_userAddress)
        returns (uint256)
    {
        IERC20(tokenAddress).safeTransferFrom(
            address(msg.sender),
            address(this),
            _tokenAmt
        );

        uint256 feeAmount = _tokenAmt * (entranceFeeFactor) / (ONE_IN_BPS);
        IERC20(tokenAddress).safeTransfer(feeReceiver, feeAmount);
        uint256 sharesAdded = _tokenAmt - (feeAmount);

        sharesTotal = sharesTotal + (sharesAdded);
        tokenLockedTotal = tokenLockedTotal + (sharesAdded);

        lastUserDepositTime[_userAddress] = block.timestamp;

        return sharesAdded;
    }

    /// @notice Allows a user to withdraw their staked tokens.
    /// @dev Only callable by the owner (StakingFactory).
    /// @param _userAddress Address of the user withdrawing tokens.
    /// @param _tokenAmt Amount of tokens to be withdrawn.
    /// @return tokenAmt Amount of tokens actually withdrawn (may be less than requested).
    function withdraw(address _userAddress,uint256 _tokenAmt)
        public
        onlyOwner
        nonReentrant
        zeroAddressCheck(_userAddress)
        returns (uint256)
    {
        uint256 tokenAmt = IERC20(tokenAddress).balanceOf(address(this));
        if (_tokenAmt > tokenAmt) {
            _tokenAmt = tokenAmt;
        }

        if (tokenLockedTotal < _tokenAmt) {
            _tokenAmt = tokenLockedTotal;
        }

        uint256 sharesRemoved = _tokenAmt;
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        sharesTotal = sharesTotal - (sharesRemoved);
        tokenLockedTotal = tokenLockedTotal - (_tokenAmt);

          uint256 feeAmount = _tokenAmt * (exitFeeFactor)/(ONE_IN_BPS);
        //user only pays fee if they have a recent last deposit
        if(lastUserDepositTime[_userAddress]+(WITHDRAW_FEE_PERIOD) >= block.timestamp) {
            IERC20(tokenAddress).safeTransfer(feeReceiver, feeAmount);
            IERC20(tokenAddress).safeTransfer(stakingFactoryAddress, _tokenAmt - feeAmount);
        }else{
         IERC20(tokenAddress).safeTransfer(stakingFactoryAddress, _tokenAmt );
        }

        return _tokenAmt;
    }

    /// @notice Pauses the StakingPool contract, preventing deposits.
    /// @dev Only callable by governance.
    function pause() public onlyGovernance {
        _pause();
    }

    /// @notice Unpauses the StakingPool contract, allowing deposits.
    /// @dev Only callable by governance.
    function unpause() external onlyGovernance {
        _unpause();
    }

    /// @notice Sets the entrance fee factor for new deposits.
    /// @dev Only callable by governance. 
    /// @param _entranceFeeFactor The new entrance fee factor in basis points (BPS).
    function setEntranceFeeFactor(uint256 _entranceFeeFactor) public onlyGovernance {
        if (_entranceFeeFactor > entranceFeeFactorMax) revert FeeLimitExceeded();
        entranceFeeFactor = _entranceFeeFactor;
    }

    /// @notice Sets the exit fee factor for withdrawals.
    /// @dev Only callable by governance.
    /// @param _exitFeeFactor The new exit fee factor in basis points (BPS).
    function setExitFeeFactor(uint256 _exitFeeFactor) public onlyGovernance {
        if (_exitFeeFactor > exitFeeFactorMax) revert FeeLimitExceeded();
        exitFeeFactor = _exitFeeFactor;
    }

    /// @notice Changes the governance address.
    /// @dev Only callable by the current governance address.
    /// @param _govAddress The new governance address.
    function setGov(address _govAddress) public onlyGovernance zeroAddressCheck(_govAddress){
        govAddress = _govAddress;
    }


    /// @notice Changes the fee receiver address.
    /// @dev Only callable by the governance address.
    /// @param _feeReceiver The new fee receiver address.
    function setFeeReceiver(
        address _feeReceiver
    ) public onlyGovernance zeroAddressCheck(_feeReceiver) {
        feeReceiver = _feeReceiver;
    }

    /// @notice Allows recovery of tokens accidentally sent to the contract (excluding the staking token).
    /// @dev Only callable by governance.
    /// @param _token Address of the stuck token.
    /// @param _amount Amount of tokens to recover.
    /// @param _to Address to send the recovered tokens to.
    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    )
        public
        onlyGovernance
        zeroAddressCheck(_token)
        zeroAddressCheck(_to)
        zeroAmountCheck(_amount)
    {
        if (_token == tokenAddress) revert StakingTokenTransfer();
        IERC20(_token).safeTransfer(_to, _amount);
    }
}