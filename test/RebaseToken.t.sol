//SPDX-License-Identifier:MIT

pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken, Ownable} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    uint256 public SEND_VALUE = 1e5; //

    function setUp() external {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    /////////////////////////////////////////////////////////////////
    //                        Vault Tests                       //
    /////////////////////////////////////////////////////////////////
    function test_UsersCanNotSetInterestRate(uint256 newInterestRate) public {
        // Update the interest rate
        vm.startPrank(user);
        vm.expectPartialRevert(bytes4(Ownable.OwnableUnauthorizedAccount.selector));
        rebaseToken.setInterestRate(newInterestRate);
        vm.stopPrank();
    }

    function test_OwnerCanSetInterestRate(uint256 newInterestRate) public {
        // bound the interest rate to be less than the current interest rate
        newInterestRate = bound(newInterestRate, 0, rebaseToken.getGlobalInterestRate() - 1);
        // Update the interest rate
        vm.startPrank(owner);
        rebaseToken.setInterestRate(newInterestRate);
        uint256 interestRate = rebaseToken.getGlobalInterestRate();
        assertEq(interestRate, newInterestRate);
        vm.stopPrank();

        // check that if someone deposits, this is their new interest rate
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        vm.stopPrank();
        assertEq(userInterestRate, newInterestRate);
    }

    function test_InterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getGlobalInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__CanNotIncreaseInterestRate.selector));
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getGlobalInterestRate(), initialInterestRate);
    }

    // Rebase token functions
    function test_CannotCallMint(uint256 _amount) public {
        _amount = bound(_amount, 1e3, type(uint96).max);
        vm.deal(user, _amount);
        // Deposit funds
        vm.startPrank(user);
        uint256 interestRate = rebaseToken.getGlobalInterestRate();
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.mint(user, _amount);
        vm.stopPrank();
    }

    function test_CannotCallBurn(uint256 _amount) public {
        // Deposit funds
        _amount = bound(_amount, 1e5, type(uint96).max);
        vm.deal(user, _amount);

        vm.startPrank(user);
        vault.deposit{value: _amount}();

        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user, _amount);
        vm.stopPrank();
    }

    function test_Deposit(uint256 _amount) public {
        _amount = bound(_amount, 1e3, type(uint96).max);
        vm.deal(user, _amount);
        vm.prank(user);
        vault.deposit{value: _amount}();
    }

    function test_DepositLiner(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);
        vm.deal(user, _amount);

        vm.startPrank(user);
        vault.deposit{value: _amount}();

        uint256 startingBalance = rebaseToken.balanceOf(user);
        assertEq(startingBalance, _amount);

        vm.warp(block.timestamp + 1 days);
        uint256 midBalance = rebaseToken.balanceOf(user);
        uint256 firstIncrement = midBalance - startingBalance;
        assertGt(rebaseToken.balanceOf(user), startingBalance);

        vm.warp(block.timestamp + 1 days);
        uint256 secondIncrement = rebaseToken.balanceOf(user) - midBalance;
        assertApproxEqAbs(firstIncrement, secondIncrement, 1);
    }

    function test_GetPrincipleAmount() public {
        uint256 amount = 1e5;
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 principleAmount = rebaseToken.principalBalanceOf(user);
        assertEq(principleAmount, amount);

        // check that the principle amount is the same after some time has passed
        vm.warp(block.timestamp + 1 days);
        uint256 principleAmountAfterWarp = rebaseToken.principalBalanceOf(user);
        assertEq(principleAmountAfterWarp, amount);
    }

    function test_RedeemStraightAway(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);
        vm.deal(user, _amount);

        vm.startPrank(user);
        vault.deposit{value: _amount}();

        uint256 startingBalance = rebaseToken.balanceOf(user);
        assertEq(startingBalance, _amount);

        vault.redeem(type(uint256).max);

        assertEq(user.balance, _amount); //ETH balance
        assertEq(rebaseToken.balanceOf(user), 0); // rebase token balance
    }

    function test_RedeemAfterTimeHasPassed(uint256 _amount, uint256 _time) public {
        _amount = bound(_amount, 1e5, type(uint96).max);
        _time = bound(_time, 1000, type(uint96).max);

        vm.deal(user, _amount);

        vm.prank(user);
        vault.deposit{value: _amount}();

        uint256 startingBalance = rebaseToken.balanceOf(user);
        assertEq(startingBalance, _amount);

        vm.warp(block.timestamp + _time);

        uint256 balanceOfUser = rebaseToken.balanceOf(user);

        vm.deal(owner, balanceOfUser - _amount);
        vm.prank(owner);
        addRewardsToVault(balanceOfUser - _amount);

        vm.prank(user);
        vault.redeem(type(uint256).max);

        assertEq(user.balance, _amount + balanceOfUser - _amount); //ETH balance
        assertEq(rebaseToken.balanceOf(user), 0); // rebase token balance
    }

    function test_CannotRedeemMoreThanBalance(uint256 _amount) public {
        // Deposit funds
        _amount = bound(_amount, 1e5, type(uint96).max);
        vm.deal(user, _amount);
        vm.startPrank(user);
        vault.deposit{value: _amount}();

        vm.expectRevert();
        vault.redeem(_amount + 1);
        vm.stopPrank();
    }

    function test_getRedabseTokenAddress() public view {
        assertEq(vault.getRedabseTokenAddress(), address(rebaseToken));
    }

    //Helper functions
    function addRewardsToVault(uint256 reward) public {
        (bool success,) = payable(address(vault)).call{value: reward}("");
        require(success);
    }
}
