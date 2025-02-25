//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

// import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {TokenPool} from "lib/ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// /root/foundry/07-foundry-cross-chain-rebase/lib/ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol

contract RebaseTokenPool is TokenPool {
    // constructor(IERC20 _token, address[] memory _allowlist, address _rmnProxy, address _router) TokenPool( _token, _allowlist, _rmnProxy, _router){

    // }
    constructor(IERC20 _token, address[] memory _allowlist, address _rmnProxy, address _router) TokenPool(_token, _allowlist, _rmnProxy, _router){

    }



}
