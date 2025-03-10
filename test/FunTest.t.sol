// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {FunDeployer} from "../src/FunDeployer.sol";
import {FunEventTracker} from "../src/FunEventTracker.sol";
import {FunPool} from "../src/FunPool.sol";
import {FunStorage} from "../src/Storage.sol";
import {SimpleERC20} from "../src/SimpleERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FunLPManager} from "../src/FunLPManager.sol";

contract FunTest is Test {
    FunDeployer deployer;
    FunEventTracker eventTracker;
    FunPool pool;
    FunStorage funStorage;
    SimpleERC20 implementation;
    FunLPManager lpManager;

    address owner;
    address treasury;
    address user1;
    address user2;

    function setUp() public {
        uint256 forkId = vm.createFork("https://mainnet.optimism.io");
        //  uint256 forkId = vm.createFork("https://rpc.mainnet.taraxa.io");
        vm.selectFork(forkId);

        owner = vm.addr(1);
        treasury = vm.addr(2);
        user1 = vm.addr(3);
        user2 = vm.addr(4);

        vm.deal(owner, 1000000000 ether);
        vm.deal(user1, 1000000000 ether);
        vm.deal(user2, 1000000000 ether);

        vm.startPrank(owner);

        implementation = new SimpleERC20();
        funStorage = new FunStorage();
        eventTracker = new FunEventTracker(address(funStorage));

        pool = new FunPool(address(implementation), address(treasury), address(eventTracker));

        deployer = new FunDeployer(address(pool), address(treasury), address(funStorage), address(eventTracker));

        lpManager = new FunLPManager(address(pool), 1000);

        pool.addDeployer(address(deployer));
        pool.setLPManager(address(lpManager));
        funStorage.addDeployer(address(deployer));
        eventTracker.addDeployer(address(deployer));
        eventTracker.addDeployer(address(pool));
    }

    function test_createToken() public {
        deployer.createFun{value: 10000000}("Test", "TT", "Test Token", 1000000000 ether, 0, 0, 0);

        //     FunStorage.FunDetails memory funTokenDetail = funStorage.getFunContract(0);

        //     uint256 amountOut = pool.getAmountOutTokens(funTokenDetail.funAddress, 300 ether);
        //    // console.log("current",pool.FunTokenPoolData.tradeActive());//(funTokenDetail.funAddress));
        //     console.log("active old",pool.getFuntokenPool(funTokenDetail.funAddress).pool.tradeActive);
        //     console.log("current",pool.getCurrentCap(funTokenDetail.funAddress));

        //     pool.buyTokens{value : 500 ether}(funTokenDetail.funAddress, amountOut, address(0x0));
        //     console.log("active new",pool.getFuntokenPool(funTokenDetail.funAddress).pool.tradeActive);
        //     console.log("current update",pool.getCurrentCap(funTokenDetail.funAddress));

        //     pool.getCurrentCap(funTokenDetail.funAddress);

        FunStorage.FunDetails memory funTokenDetail = funStorage.getFunContract(0);
        uint256 listThresholdCap = pool.getListThresholdCap(funTokenDetail.funAddress);
        console.log("Listing Threshold:", listThresholdCap);
        uint256 currentCap = pool.getCurrentCap(funTokenDetail.funAddress);
        console.log("Initial Market Cap:", currentCap);
        console.log("Trade Active Before:", pool.getFuntokenPool(funTokenDetail.funAddress).pool.tradeActive);
        while (pool.getCurrentCap(funTokenDetail.funAddress) < listThresholdCap) {
            bool tradeActive = pool.getFuntokenPool(funTokenDetail.funAddress).pool.tradeActive;
            if (!tradeActive) {
                console.log("Trade stopped! Skipping further buys.");
                break;
            }
            pool.buyTokens{value: 1000 ether}(funTokenDetail.funAddress, 0, address(0x0));
            console.log("Updated Market Cap:", pool.getCurrentCap(funTokenDetail.funAddress));
        }
        bool tradeActiveAfter = pool.getFuntokenPool(funTokenDetail.funAddress).pool.tradeActive;
        console.log("Trade Active After:", tradeActiveAfter);
    }

    function test_buyTokens() public {
        deployer.createFun{value: 10000000}("Test", "TT", "Test Token", 1000000000 ether, 0, 0, 0);
        FunStorage.FunDetails memory funTokenDetail = funStorage.getFunContract(0);

        uint256 ethAmount = 300 ether;

        // חישוב העמלות בדיוק כמו בחוזה
        uint256 tradingFeePer = deployer.getTradingFeePer();
        uint256 taraAmountFee = (ethAmount * tradingFeePer) / 10000;

        // חישוב מדויק לאחר הפחתת עמלה
        uint256 expectedTokenAmount = pool.getAmountOutTokens(funTokenDetail.funAddress, ethAmount - taraAmountFee);

        uint256 userBalanceBefore = IERC20(funTokenDetail.funAddress).balanceOf(user1);

        vm.startPrank(user1);
        pool.buyTokens{value: ethAmount}(funTokenDetail.funAddress, expectedTokenAmount, address(0));
        vm.stopPrank();

        uint256 userBalanceAfter = IERC20(funTokenDetail.funAddress).balanceOf(user1);
        assertEq(userBalanceAfter - userBalanceBefore, expectedTokenAmount, "User did not receive correct token amount");
    }
}
