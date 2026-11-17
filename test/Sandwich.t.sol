// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";

contract SandwichTest is Test {
    Token tA;
    Token tB;
    SimpleAMM amm;
    address lp = makeAddr("lp");
    address victim = makeAddr("victim");
    address attacker = makeAddr("attacker");

    function setUp() public {
        tA = new Token("Token A", "TKA");
        tB = new Token("Token B", "TKB");
        amm = new SimpleAMM(address(tA), address(tB));

        tA.mint(lp, 1_000_000e18);
        tB.mint(lp, 1_000_000e18);
        vm.startPrank(lp);
        tA.approve(address(amm), type(uint256).max);
        tB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1_000_000e18, 1_000_000e18);
        vm.stopPrank();

        tA.mint(victim, 50_000e18);
        tA.mint(attacker, 20_000e18);
        vm.prank(victim);
        tA.approve(address(amm), type(uint256).max);
        vm.startPrank(attacker);
        tA.approve(address(amm), type(uint256).max);
        tB.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    function test_sandwich() public {
        uint256 victimIn = 50_000e18;
        uint256 attackerIn = 20_000e18;

        // Quanto a vítima receberia sem ataque
        uint256 fair = amm.getAmountOut(victimIn, amm.reserve0(), amm.reserve1());
        uint256 minOut = (fair * 95) / 100; // tolera 5% de slippage

        // 1) FRONT-RUN: atacante compra B antes da vítima
        vm.prank(attacker);
        uint256 gotB = amm.swap(address(tA), attackerIn, 0);

        // 2) Transação da vítima executa a preço pior
        vm.prank(victim);
        uint256 victimOut = amm.swap(address(tA), victimIn, minOut);

        // 3) BACK-RUN: atacante vende B e embolsa a diferença
        vm.prank(attacker);
        amm.swap(address(tB), gotB, 0);

        uint256 profit = tA.balanceOf(attacker) - 0; // começou com 0 após o front-run
        console.log("Vitima receberia (sem ataque), TKB:", fair / 1e18);
        console.log("Vitima recebeu (com ataque), TKB:  ", victimOut / 1e18);
        console.log("Prejuizo da vitima, TKB:           ", (fair - victimOut) / 1e18);
        console.log("Saldo final do atacante, TKA:      ", profit / 1e18);

        assertLt(victimOut, fair);
        assertGt(profit, attackerIn); // saiu com mais do que entrou
    }
}
