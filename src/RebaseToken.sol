//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Rebase Token
 * @author tusharr1411
 * @notice This is gonna be a cross chanin rebase token that incentivises users to stake into a vault
 * @notice the interest rate in this contract can only decreases over the time
 * @notice Each each user will have their own interest rate which will be the global interest rate at the time of deposite
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    /////////////////////////////////////////////////////////////////
    //                  Gloabal Variables                          //
    /////////////////////////////////////////////////////////////////
    uint256 private constant PRECISION_FACTOR = 1e18; // as 18 decimals in token
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    uint256 private s_globalInterestRate;
    mapping(address => uint256) private s_usersInterestRate;
    mapping(address => uint256) private s_userlastUpdatedTimestamp;

    /////////////////////////////////////////////////////////////////
    //                          Errors                             //
    /////////////////////////////////////////////////////////////////
    error RebaseToken__CanNotIncreaseInterestRate(uint256 oldInterestRate, uint256 newInterestRate);

    /////////////////////////////////////////////////////////////////
    //                          Events                             //
    /////////////////////////////////////////////////////////////////
    event InterestRateChanged(uint256 oldInterestRate, uint256 newInterestRate);

    /////////////////////////////////////////////////////////////////
    //                          constructor                        //
    /////////////////////////////////////////////////////////////////

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {
        s_globalInterestRate = 5e10; // 0.05e8 percent
    }

    /////////////////////////////////////////////////////////////////
    //                public/external functions                    //
    /////////////////////////////////////////////////////////////////
    function grantMintAndBurnRole(address _address) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _address);
    }

    /**
     * @notice updates the s_globalInterestRate
     * @param _newInterestRate new interest rate
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        require(
            _newInterestRate < s_globalInterestRate,
            RebaseToken__CanNotIncreaseInterestRate(s_globalInterestRate, _newInterestRate)
        );

        emit InterestRateChanged(s_globalInterestRate, _newInterestRate);
        s_globalInterestRate = _newInterestRate;
    }

    /**
     *
     * @param _to address to mint tokens
     * @param _amount amount of tokens to mint
     * @param _userInterestRate interestRate of the user for minted tokens
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) public onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_usersInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) public onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    function transfer(address _to, uint256 _amount) public override returns (bool) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_to);
        //@audit anyone can have the maximum interest rate if they get tokens transfered from a high interest rate account
        if (balanceOf(_to) == 0) {
            // Update the users interest rate only if they have not yet got one (or they tranferred/burned all their tokens). Otherwise people could force others to have lower interest.
            s_usersInterestRate[_to] = s_usersInterestRate[msg.sender];
        }
        return super.transfer(_to, _amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _mintAccruedInterest(_to);
        //@audit anyone can have the maximum interest rate if they get tokens transfered from a high interest rate account
        if (balanceOf(_to) == 0) {
            // Update the users interest rate only if they have not yet got one (or they tranferred/burned all their tokens). Otherwise people could force others to have lower interest.
            s_usersInterestRate[_to] = s_usersInterestRate[msg.sender];
        }
        return super.transferFrom(_from, _to, _amount);
    }

    /////////////////////////////////////////////////////////////////
    //                      Internal functions                     //
    /////////////////////////////////////////////////////////////////
    /**
     * @dev accumulates the accrued interest of the user to the principal balance. This function mints the users accrued interest since they last transferred or bridged tokens.
     * @param _user the address of the user for which the interest is being minted
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user); // this is with interest
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;
        _mint(_user, balanceIncrease);
        s_userlastUpdatedTimestamp[_user] = block.timestamp;
    }

    /**
     * @dev returns the interest accrued since the last update of the user's balance - aka since the last time the interest accrued was minted to the user.
     * @return linearInterest the interest accrued since the last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // PrincipleAmount +  PrincipleAmount * userInterestRate * time elapsed
        // PrincipleAmount( 1 + userInterestRate * time elapsed)

        uint256 timeElapsed = block.timestamp - s_userlastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + s_usersInterestRate[_user] * timeElapsed;
    }

    /////////////////////////////////////////////////////////////////
    //                  getters and view functions                 //
    /////////////////////////////////////////////////////////////////
    function balanceOf(address _user) public view override returns (uint256) {
        if (super.balanceOf(_user) == 0) return 0;
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    function getGlobalInterestRate() public view returns (uint256) {
        return s_globalInterestRate;
    }

    function getUserInterestRate(address user) external view returns (uint256) {
        return s_usersInterestRate[user];
    }

    function getUsetLastUpdateTimeStamp(address _user) external view returns (uint256) {
        return s_userlastUpdatedTimestamp[_user];
    }
}
