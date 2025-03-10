// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {INonfungiblePositionManager} from "@v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IFunStorageInterface} from "./interfaces/IFunStorageInterface.sol";
import {IPool} from "@velodrome/interfaces/IPool.sol";

contract FunLPManager is Ownable, IERC721Receiver {
    struct LPPosition {
        address dev;
        uint256 token0Collected;
        uint256 token1Collected;
    }

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public feePer;

    address public positionManager = 0x1C5A295E9860d127D8A3E7af138Bb945c4377ae7;

    address public funPool;

    mapping(uint256 => LPPosition) public tokenIdToLPPosition;
    mapping(address => uint256[]) public devToTokenIds;

    event PositionDeposited(uint256 tokenId, address dev, uint256 timestamp);

    event FeesCollected(uint256 tokenId, address dev, address token, uint256 amount, uint256 timestamp);

    constructor(address _funPool, uint256 _feePer) Ownable(msg.sender) {
        funPool = _funPool;
        feePer = _feePer;
    }

    function depositNFTPosition(uint256 _tokenId, address _dev) external {
        require(msg.sender == funPool, "LPManager: Only FunPool can call this function");

        IERC721(positionManager).transferFrom(funPool, address(this), _tokenId);

        LPPosition memory lpPosition = LPPosition({dev: _dev, token0Collected: 0, token1Collected: 0});

        tokenIdToLPPosition[_tokenId] = lpPosition;
        devToTokenIds[_dev].push(_tokenId);

        emit PositionDeposited(_tokenId, _dev, block.timestamp);
    }

    function collectFees(uint256 _tokenId) external {
        LPPosition storage lpPosition = tokenIdToLPPosition[_tokenId];

        require(
            IERC721(positionManager).ownerOf(_tokenId) == address(this), "LPManager: LP Token not owned by LPManager"
        );
        require(
            (msg.sender == lpPosition.dev) || (msg.sender == owner()), "LPManager: Only Dev or Owner can collect fees"
        );

        // (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(positionManager).collect(INonfungiblePositionManager.CollectParams({
        //     tokenId: _tokenId,
        //     recipient: address(this),
        //     amount0Max: type(uint128).max,
        //     amount1Max: type(uint128).max
        // }));

        (uint256 amountA, uint256 amountB) = IPool(positionManager).claimFees();
        (address tokenA, address tokenB) = IPool(positionManager).tokens();
        // (,,address token0, address token1,,,,,,,,) = INonfungiblePositionManager(positionManager).positions(_tokenId);

        if (amountA > 0) {
            uint256 feeAmountA = (amountA * feePer) / BASIS_POINTS;
            IERC20(tokenA).transfer(owner(), feeAmountA);
            IERC20(tokenA).transfer(lpPosition.dev, amountA - feeAmountA);

            emit FeesCollected(_tokenId, lpPosition.dev, tokenA, amountA, block.timestamp);
        }

        if (amountB > 0) {
            uint256 feeAmountB = (amountB * feePer) / BASIS_POINTS;
            IERC20(tokenB).transfer(owner(), feeAmountB);
            IERC20(tokenB).transfer(lpPosition.dev, amountB - feeAmountB);

            emit FeesCollected(_tokenId, lpPosition.dev, tokenB, amountB, block.timestamp);
        }
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    function setFeePer(uint256 _feePer) external onlyOwner {
        require(_feePer > 0, "LPManager: Fee Per must be greater than 0");
        feePer = _feePer;
    }

    function emergencyWithdrawERC721(address _token, uint256 _tokenId) external onlyOwner {
        IERC721(_token).transferFrom(address(this), owner(), _tokenId);
    }
}
