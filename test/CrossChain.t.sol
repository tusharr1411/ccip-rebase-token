///SPDX-License-Identifier:MIT

pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {RebaseToken, Ownable} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {TokenPool} from "lib/ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {CCIPLocalSimulatorFork, Register} from "lib/chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from
    "lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "lib/ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "lib/ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "lib/ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChain is Test {
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;
    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    RebaseToken sepoliaRebaseToken;
    RebaseToken arbSepoliaRebaseToken;

    Vault vault;

    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    address owner = makeAddr("owner");
    address patrick = makeAddr("patrick");

    function setUp() public {
        string memory SEPOLIA_ETH_RPC_URL = vm.envString("SEPOLIA_ETH_RPC_URL");
        string memory ARB_SEPOLIA_RPC_URL = vm.envString("ARB_SEPOLIA_RPC_URL");

        sepoliaFork = vm.createSelectFork(SEPOLIA_ETH_RPC_URL);
        arbSepoliaFork = vm.createFork(ARB_SEPOLIA_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork)); //make ccipLocalSimulatorFork contract persistant so that it's state is preserved during chain switches

        //deploy and configure on sepolia
        vm.startPrank(owner);
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        sepoliaRebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaRebaseToken)));

        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaRebaseToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        sepoliaRebaseToken.grantMintAndBurnRole(address(vault));
        sepoliaRebaseToken.grantMintAndBurnRole(address(sepoliaPool));

        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaRebaseToken)
        );
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaRebaseToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaRebaseToken), address(sepoliaPool)
        );
        vm.stopPrank();

        //deploy and configure on arb-sepolia
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        arbSepoliaRebaseToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaRebaseToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaRebaseToken.grantMintAndBurnRole(address(vault));
        arbSepoliaRebaseToken.grantMintAndBurnRole(address(arbSepoliaPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaRebaseToken)
        );
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(
            address(arbSepoliaRebaseToken)
        );
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaRebaseToken), address(arbSepoliaPool)
        );

        // configureTokenPool(
        //     sepoliaFork,
        //     sepoliaPool,
        //     arbSepoliaPool,
        //     IRebaseToken(address(arbSepoliaRebaseToken)),
        //     sepoliaNetworkDetails
        // );
        vm.stopPrank();
    }

    /////////////////////////////////////////////////////////////
    ////////////////      Helper functions    ///////////////////
    /////////////////////////////////////////////////////////////

    function configureTokenPool(
        uint256 fork,
        RebaseTokenPool localPool,
        RebaseTokenPool remotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(fork);
        vm.startPrank(owner);

        RebaseTokenPool.ChainUpdate[] memory chains = new RebaseTokenPool.ChainUpdate[](1);

        // chains[0] = RebaseTokenPool.ChainUpdate({
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector, // ──╮ Remote chain selector
            allowed: true, //                             ────────────────╯ Whether the chain should be enabled
            remotePoolAddress: abi.encode(address(remotePool)), //        Address of the remote pool, ABI encoded in the case of a remote EVM chain.
            remoteTokenAddress: abi.encode(address(remoteToken)), //       Address of the remote token, ABI encoded in the case of a remote EVM chain.
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}), // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        localPool.applyChainUpdates(chains);
        vm.stopPrank();
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        ///////////////////     construct message to sign as cross chain transaction
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(localToken), // token address on the local chain.
            amount: amountToBridge // Amount of tokens.
        });
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(patrick), // abi.encode(receiver address) for dest EVM chains
            data: "", // Data payload
            tokenAmounts: tokenAmounts, // Token transfers
            feeToken: localNetworkDetails.linkAddress, // Address of feeToken. address(0) means you will send msg.value.
            extraArgs: "" //Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });
        //---------------------------------------------------------------------------------------

        uint256 balanceBeforeBridge = IERC20(address(localToken)).balanceOf(patrick);
        console.log("Local balance of Patrick before bridge: %d", balanceBeforeBridge);

        /////////////////////    Handle token approvals and send the message to cross chain via ccip
        ccipLocalSimulatorFork.requestLinkFromFaucet(
            patrick,
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        ); // Give the patrick LINK for fee to CCIP network (executing before startPrank as it changes prank)

        vm.startPrank(patrick);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge); // Approve the router to burn tokens on patrick's behalf
        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress,
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        ); // Approve the router to take fee from the patrick's wallet
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message); // send the message to remote chain by paying link token as fee
        vm.stopPrank();
        //---------------------------------------------------------------------------------------

        uint256 sourceBalanceAfterBridge = IERC20(address(localToken)).balanceOf(patrick);
        console.log("Local balance of Patrick after bridge: %d", sourceBalanceAfterBridge);
        assertEq(sourceBalanceAfterBridge, balanceBeforeBridge - amountToBridge);

        //////////////     check patrick's info on destination chain before bridge
        vm.selectFork(localFork);
        vm.warp(block.timestamp + 900);
        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 900); // Pretend it takes 15 minutes to bridge the tokens
        // get initial balance on Arbitrum
        uint256 initialArbBalance = IERC20(address(remoteToken)).balanceOf(patrick); // should be zero
        console.log("Remote balance of Patrick before bridge: %d", initialArbBalance);

        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork); // CCIP network triggers this and  look for `CCIPSendRequested` event from past logs which switches to destination network fork  and routes the cross chain message on the destination address. Then router handle the transaction.
        console.log("Remote patrick's interest rate: %d", remoteToken.getUserInterestRate(patrick));
        uint256 destBalance = IERC20(address(remoteToken)).balanceOf(patrick);
        console.log("Remote balance of Patrick after bridge: %d", destBalance);
        assertEq(destBalance, initialArbBalance + amountToBridge);
    }

    /////////////////////////////////////////////////////////////
    ////////////////      Cross chain tests   ///////////////////
    /////////////////////////////////////////////////////////////

    function test_BridgeAllTokens() public {
        uint256 ETH_AMOUNT = 1000e18;

        //configure pools on both chains
        configureTokenPool(
            sepoliaFork,
            sepoliaPool,
            arbSepoliaPool,
            IRebaseToken(address(arbSepoliaRebaseToken)),
            arbSepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork,
            arbSepoliaPool,
            sepoliaPool,
            IRebaseToken(address(sepoliaRebaseToken)),
            sepoliaNetworkDetails
        );

        vm.selectFork(sepoliaFork); //------------------------------------------------------

        vm.deal(patrick, ETH_AMOUNT); //Give patrick rebase token on source chain to bridge to destination chain
        vm.prank(patrick);
        vault.deposit{value: ETH_AMOUNT}(); // mint patrick rebase token on sepolia (sepoliaRebaseToken) for ETH_AMOUNT ethers.
        console.log("Bridging %d tokens", ETH_AMOUNT);
        uint256 startBalance = sepoliaRebaseToken.balanceOf(patrick);
        assertEq(startBalance, ETH_AMOUNT);

        //bridge all tokens to arbSepolia
        bridgeTokens(
            startBalance,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaRebaseToken,
            arbSepoliaRebaseToken
        );

        // let's make sure we can bridge back tokens to sepolia
        vm.selectFork(sepoliaFork);
        vm.warp(block.timestamp + 3600);
        vm.selectFork(arbSepoliaFork);
        console.log("User Balance Before Warp: %d", arbSepoliaRebaseToken.balanceOf(patrick));
        vm.warp(block.timestamp + 3600);
        console.log("User Balance After Warp: %d", arbSepoliaRebaseToken.balanceOf(patrick));
        uint256 destBalance = IERC20(address(arbSepoliaRebaseToken)).balanceOf(patrick);
        console.log("Amount bridging back %d tokens ", destBalance);
        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaRebaseToken,
            sepoliaRebaseToken
        );
    }

    function test_bridgeTwice() public {
        uint256 ETH_AMOUNT = 1000e18;

        //configure pools on both chains
        configureTokenPool(
            sepoliaFork,
            sepoliaPool,
            arbSepoliaPool,
            IRebaseToken(address(arbSepoliaRebaseToken)),
            arbSepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork,
            arbSepoliaPool,
            sepoliaPool,
            IRebaseToken(address(sepoliaRebaseToken)),
            sepoliaNetworkDetails
        );

        //////////////////////////////////////////////
        vm.selectFork(sepoliaFork);

        vm.deal(patrick, ETH_AMOUNT); //Give patrick rebase token on source chain to bridge to destination chain
        vm.prank(patrick);
        vault.deposit{value: ETH_AMOUNT}(); // mint patrick rebase token on sepolia (sepoliaRebaseToken) for ETH_AMOUNT ethers.
        console.log("Bridging %d tokens", ETH_AMOUNT);
        uint256 startBalance = sepoliaRebaseToken.balanceOf(patrick);
        assertEq(startBalance, ETH_AMOUNT);

        //bridge half tokens to arbSepolia
        bridgeTokens(
            startBalance / 2,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaRebaseToken,
            arbSepoliaRebaseToken
        );
        // -------------------------------------------------

        // wait for 1 hour for the interest to accrue
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 3600);
        vm.selectFork(sepoliaFork);
        vm.warp(block.timestamp + 3600);
        uint256 newSepoliaBalance = IERC20(address(sepoliaRebaseToken)).balanceOf(patrick); // half + interest on half on sepolia

        console.log("Bridging all remaing %d tokens (second bridging event)", newSepoliaBalance);
        bridgeTokens(
            newSepoliaBalance,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaRebaseToken,
            arbSepoliaRebaseToken
        );
        // --------------------------------------------------

        // bridge back ALL TOKENS to the source chain after 1 hour
        vm.selectFork(sepoliaFork);
        vm.warp(block.timestamp + 3600);
        vm.selectFork(arbSepoliaFork);
        // wait an hour for the tokens to accrue interest on the destination chain
        console.log("User Balance Before Warp: %d", arbSepoliaRebaseToken.balanceOf(patrick));
        vm.warp(block.timestamp + 3600);
        console.log("User Balance After Warp: %d", arbSepoliaRebaseToken.balanceOf(patrick));
        uint256 destBalance = IERC20(address(arbSepoliaRebaseToken)).balanceOf(patrick);
        console.log("Amount bridging back %d tokens ", destBalance);
        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaRebaseToken,
            sepoliaRebaseToken
        );
    }
}
