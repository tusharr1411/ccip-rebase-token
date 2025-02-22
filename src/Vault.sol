//SPDX-License-Identifier:MIT

pragma solidity ^0.8.27;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    /////////////////////////////////////////////////////////////////
    //                     Gloabal Variables                       //
    /////////////////////////////////////////////////////////////////
    IRebaseToken private immutable i_rebaseToken;

    /////////////////////////////////////////////////////////////////
    //                          Errors                             //
    /////////////////////////////////////////////////////////////////
    error Vault__BalanceIsTooLow(uint256 balance);
    error Vault__ReedemFailed();

    /////////////////////////////////////////////////////////////////
    //                          Events                             //
    /////////////////////////////////////////////////////////////////
    event Deposited(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);

    /////////////////////////////////////////////////////////////////
    //                       constructor                           //
    /////////////////////////////////////////////////////////////////
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /////////////////////////////////////////////////////////////////
    //                 public/external functions                   //
    /////////////////////////////////////////////////////////////////

    /**
     * @notice Allows users to deposit ETH into the vauld and mint RebaseTokens in retruns
     *
     */
    function deposit() external payable {
        i_rebaseToken.mint(msg.sender, msg.value);

        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice Allows users to redeem their Rebase tokens for ETH
     * @param _amount the amount of rebase tokens to redeem
     */
    function redeem(uint256 _amount) external {
        uint256 userBalance = i_rebaseToken.balanceOf(msg.sender);

        if (_amount == type(uint256).max) {
            _amount = userBalance;
        }
        require(userBalance >= _amount, Vault__BalanceIsTooLow(userBalance));
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        require(success, Vault__ReedemFailed());
        emit Redeemed(msg.sender, _amount);
    }

    /////////////////////////////////////////////////////////////////
    //               getters and view functions                    //
    /////////////////////////////////////////////////////////////////

    function getRedabseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
