"""Varredura de parametros do ataque sanduiche em AMM de produto constante.
Replica em Python (aritmetica inteira) o contrato SimpleAMM.sol (taxa 0,3%)."""
import csv
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

E18 = 10**18
R0 = R1 = 1_000_000 * E18          # liquidez inicial (igual ao script da Sepolia)


def amount_out(a_in, r_in, r_out):
    fee = a_in * 997
    return fee * r_out // (r_in * 1000 + fee)


def sandwich(victim_in, attacker_in, slippage, r0=R0, r1=R1):
    """Retorna dict com resultado. Tokens em unidades inteiras de 1e18."""
    v_in, a_in = victim_in * E18, attacker_in * E18
    fair = amount_out(v_in, r0, r1)
    min_out = fair * int(round((1 - slippage) * 10000)) // 10000

    # 1) front-run
    got_b = amount_out(a_in, r0, r1) if a_in > 0 else 0
    r0a, r1a = r0 + a_in, r1 - got_b
    # 2) vitima
    v_out = amount_out(v_in, r0a, r1a)
    if v_out < min_out:
        return dict(ok=False, fair=fair / E18, victim_out=0, loss=0, loss_pct=0, profit=0)
    r0b, r1b = r0a + v_in, r1a - v_out
    # 3) back-run
    back_a = amount_out(got_b, r1b, r0b) if got_b > 0 else 0
    profit = back_a - a_in
    loss = fair - v_out
    return dict(ok=True, fair=fair / E18, victim_out=v_out / E18, loss=loss / E18,
                loss_pct=100 * loss / fair, profit=profit / E18)


def best_attack(victim_in, slippage, max_cap=500_000, step=250):
    """Capital do atacante que maximiza o lucro respeitando o slippage da vitima."""
    best = (0, dict(ok=True, profit=0, loss=0, loss_pct=0, fair=0, victim_out=0))
    for a in range(step, max_cap + 1, step):
        r = sandwich(victim_in, a, slippage)
        if r["ok"] and r["profit"] > best[1]["profit"]:
            best = (a, r)
    return best


def save_csv(name, rows):
    with open(name, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys())
        w.writeheader()
        w.writerows(rows)


def main():
    out = os.path.dirname(os.path.abspath(__file__))

    # Validacao: mesmo caso executado na Sepolia (vitima 50k, atacante 20k, slippage 5%)
    v = sandwich(50_000, 20_000, 0.05)
    print("VALIDACAO (Sepolia): vitima recebeu %.2f TKB | atacante lucro %.2f TKA"
          % (v["victim_out"], v["profit"]))
    print("  esperado on-chain: 45684.37 TKB | 1855.67 TKA")

    # Exp 1: tamanho da troca da vitima (slippage 5%, atacante otimo)
    sizes = [1_000, 5_000, 10_000, 25_000, 50_000, 100_000, 200_000]
    rows1 = []
    for s in sizes:
        a, r = best_attack(s, 0.05)
        rows1.append(dict(victim_in=s, attacker_opt=a, profit=round(r["profit"], 2),
                          loss=round(r["loss"], 2), loss_pct=round(r["loss_pct"], 3)))
    save_csv(os.path.join(out, "exp1_tamanho.csv"), rows1)

    # Exp 2: tolerancia de slippage (vitima 50k, atacante otimo)
    slips = [0.001, 0.0025, 0.005, 0.01, 0.02, 0.03, 0.05, 0.10]
    rows2 = []
    for sl in slips:
        a, r = best_attack(50_000, sl, step=100)
        rows2.append(dict(slippage_pct=sl * 100, attacker_opt=a, profit=round(r["profit"], 2),
                          loss=round(r["loss"], 2), loss_pct=round(r["loss_pct"], 3)))
    save_csv(os.path.join(out, "exp2_slippage.csv"), rows2)

    # Exp 3: capital do atacante (vitima 50k, slippage 5%)
    caps = list(range(1_000, 120_001, 1_000))
    rows3 = []
    for c in caps:
        r = sandwich(50_000, c, 0.05)
        rows3.append(dict(attacker_in=c, ok=int(r["ok"]), profit=round(r["profit"], 2),
                          loss_pct=round(r["loss_pct"], 3)))
    save_csv(os.path.join(out, "exp3_capital.csv"), rows3)

    # Graficos
    fig, ax = plt.subplots(1, 2, figsize=(10, 4))
    ax[0].plot([r["victim_in"] for r in rows1], [r["profit"] for r in rows1], "o-")
    ax[0].set_xscale("log"); ax[0].set_xlabel("Troca da vitima (TKA)")
    ax[0].set_ylabel("Lucro bruto do atacante (TKA)"); ax[0].grid(alpha=.3)
    ax[1].plot([r["victim_in"] for r in rows1], [r["loss_pct"] for r in rows1], "o-", color="C3")
    ax[1].set_xscale("log"); ax[1].set_xlabel("Troca da vitima (TKA)")
    ax[1].set_ylabel("Prejuizo da vitima (%)"); ax[1].grid(alpha=.3)
    fig.suptitle("Exp. 1: efeito do tamanho da troca (slippage 5%)")
    fig.tight_layout(); fig.savefig(os.path.join(out, "exp1_tamanho.png"), dpi=200); plt.close(fig)

    fig, ax = plt.subplots(figsize=(6, 4))
    ax.plot([r["slippage_pct"] for r in rows2], [r["profit"] for r in rows2], "o-")
    ax.set_xscale("log"); ax.set_xlabel("Tolerancia de slippage da vitima (%)")
    ax.set_ylabel("Lucro maximo do atacante (TKA)"); ax.grid(alpha=.3)
    ax.set_title("Exp. 2: slippage vs lucro (vitima 50k TKA)")
    fig.tight_layout(); fig.savefig(os.path.join(out, "exp2_slippage.png"), dpi=200); plt.close(fig)

    fig, ax = plt.subplots(figsize=(6, 4))
    xs = [r["attacker_in"] for r in rows3 if r["ok"]]
    ys = [r["profit"] for r in rows3 if r["ok"]]
    ax.plot(xs, ys, "o-", ms=3)
    fail = [r["attacker_in"] for r in rows3 if not r["ok"]]
    if fail:
        ax.axvline(fail[0], color="r", ls="--", label="vitima reverte (slippage)")
        ax.legend()
    ax.set_xlabel("Capital do atacante (TKA)"); ax.set_ylabel("Lucro bruto (TKA)")
    ax.grid(alpha=.3); ax.set_title("Exp. 3: capital do atacante (vitima 50k, slippage 5%)")
    fig.tight_layout(); fig.savefig(os.path.join(out, "exp3_capital.png"), dpi=200); plt.close(fig)

    for nome, rows in (("EXP1 tamanho", rows1), ("EXP2 slippage", rows2)):
        print("\n" + nome)
        for r in rows:
            print(r)
    print("\nEXP3: atacante otimo ate o limite do slippage:",
          max((r for r in rows3 if r["ok"]), key=lambda r: r["profit"]))
    print("EXP3: primeiro capital que faz a vitima reverter:", fail[0] if fail else "nenhum")


if __name__ == "__main__":
    main()