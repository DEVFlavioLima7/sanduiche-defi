// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Token} from "./Token.sol";

// AMM de produto constante (x * y = k) com taxa de 0,3%, estilo Uniswap v2
contract SimpleAMM {
    Token public immutable token0;
    Token public immutable token1;
    uint256 public reserve0;
    uint256 public reserve1;

    event Swap(address indexed trader, address tokenIn, uint256 amountIn, uint256 amountOut);

    constructor(address _token0, address _token1) {
        token0 = Token(_token0);
        token1 = Token(_token1);
    }

    function addLiquidity(uint256 amount0, uint256 amount1) external {
        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
        reserve0 += amount0;
        reserve1 += amount1;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public pure returns (uint256)
    {
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    // minAmountOut = tolerância de slippage da vítima
    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut)
        external returns (uint256 amountOut)
    {
        require(tokenIn == address(token0) || tokenIn == address(token1), "token");
        bool zeroForOne = tokenIn == address(token0);

        (Token tIn, Token tOut, uint256 rIn, uint256 rOut) = zeroForOne
            ? (token0, token1, reserve0, reserve1)
            : (token1, token0, reserve1, reserve0);

        amountOut = getAmountOut(amountIn, rIn, rOut);
        require(amountOut >= minAmountOut, "slippage");

        tIn.transferFrom(msg.sender, address(this), amountIn);
        tOut.transfer(msg.sender, amountOut);

        if (zeroForOne) {
            reserve0 += amountIn;
            reserve1 -= amountOut;
        } else {
            reserve1 += amountIn;
            reserve0 -= amountOut;
        }
        emit Swap(msg.sender, tokenIn, amountIn, amountOut);
    }
}
