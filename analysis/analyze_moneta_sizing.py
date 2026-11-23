"""Size the Moneta Funded 2-Step books to a dollar target in whole 0.01 lots.

The Monte Carlo ladder in ``build_live_and_prop_reports.py`` sizes a book as one
continuous dollar number per trade and divides it equally across sleeves. On
XAUUSD the broker minimum is 0.01 lot, so that ladder is not placeable. This
step keeps the same validation-period block bootstrap but sizes each sleeve in
whole lots:

    lots_i = max(0.01, floor(target / n_sleeves / 1R_per_lot_i * 100) / 100)

and prices the resulting book at the actual lots. It writes the stage-sizing
report for Moneta and a JSON allocation map the EA set-file builder consumes.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze_the5ers_sizing as T5
import build_live_and_prop_reports as engine

ACCOUNT = engine.MONETA_SIZE
OUT = engine.PROP_ROOT / "Moneta-2Step-25K" / "reports"

PHASE_BOOKS = {
    "4-sleeve": ["Gold X9", "GotobiFix EURJPY", "GotobiFix USDJPY", "Open Drive"],
    "X9 + OBR pair": ["Gold X9", "Overnight Bias ORB"],
    "3-sleeve (no index)": ["Gold X9", "GotobiFix EURJPY", "GotobiFix USDJPY"],
}
FUNDED_BOOKS = {
    "no gold": ["Flash ORB", "GotobiFix EURJPY", "Tokyo Coil", "Overnight Bias ORB"],
    "no gold, 3-sleeve": ["Flash ORB", "GotobiFix EURJPY", "Overnight Bias ORB"],
    "with gold": ["Flash ORB", "Gold X9", "GotobiFix EURJPY", "Tokyo Coil"],
}
TARGETS = [50.0, 100.0, 150.0, 200.0, 300.0, 500.0]


def loads(trades, book, target):
    unit = {s: float(trades.loc[trades["strategy"] == s, "risk_unit"].iloc[0]) for s in book}
    per = target / len(book)
    lots = {s: max(0.01, math.floor(per / unit[s] * 100.0 + 1e-9) / 100.0) for s in book}
    return lots, {s: lots[s] * unit[s] for s in book}


def simulate(trades, rmat, val, book, target, seed, phase="phase1"):
    lots, risk = loads(trades, book, target)
    r = np.stack([rmat.loc[val, s].values for s in book], axis=1)
    paths = T5.sample_joint(r, val, seed)
    book_daily = (paths * np.array([risk[s] for s in book])).sum(axis=2)
    active = np.ones_like(book_daily, dtype=bool)
    res = engine.simulate_moneta(book_daily, active, 1.0)
    return lots, risk, res


def main():
    trades, _ = engine.load_platform_trades("MT5")
    trades = T5.calibrate(trades)
    dates, rmat, _, _, _ = engine.make_matrices(trades)
    cut = max(1, min(len(dates) - 1, int(len(dates) * 0.60)))
    val = dates[cut:]
    unit = {s: float(trades.loc[trades["strategy"] == s, "risk_unit"].iloc[0]) for s in rmat.columns}

    floor = {s: 0.01 * unit[s] for s in unit}
    print("0.01-lot 1R:", {k: round(v, 2) for k, v in sorted(floor.items(), key=lambda kv: -kv[1])})

    rows = []
    for book_name, book in {**PHASE_BOOKS, **FUNDED_BOOKS}.items():
        for target in TARGETS:
            lots, risk, res = simulate(trades, rmat, val, book, target, seed=engine.SEED + 31 + len(rows))
            rows.append({
                "book": book_name,
                "sleeves": " + ".join(book),
                "target_usd": target,
                "lots": ", ".join(f"{s} {lots[s]:.2f}" for s in book),
                "actual_risk_usd": round(sum(risk.values()), 2),
                "pct_of_25k": round(sum(risk.values()) / ACCOUNT * 100, 3),
                "phase1_pass": res["pass_phase1_rate"],
                "both_phases_pass": res["pass_both_phases_rate"],
                "eval_breach": res["evaluation_hard_breach_rate"],
                "payout": res["challenge_to_first_payout_rate"],
                "funded_payout_conditional": res["funded_first_payout_rate_conditional"],
                "funded_breach": res["funded_hard_breach_rate_conditional"],
                "days_to_first_payout": res["median_days_to_first_payout_from_start"],
                "expected_first_payout_usd": res["expected_first_payout_usd"],
            })
            print(f"{book_name:20s} target {target:6.0f} risk {rows[-1]['actual_risk_usd']:7.2f} "
                  f"both {res['pass_both_phases_rate']:.3f} payout {res['challenge_to_first_payout_rate']:.3f} "
                  f"breach {res['evaluation_hard_breach_rate']:.3f}")
    df = pd.DataFrame(rows)
    OUT.mkdir(parents=True, exist_ok=True)
    df.to_csv(OUT / "stage_sizing.csv", index=False)

    # Selection: highest payout with the evaluation hard-breach rate kept at or
    # below 3%. A $25k 2-step is bought once, so the breach tail matters more
    # than shaving 30 days off the median.
    def pick(book_name, breach_cap=0.03):
        d = df[df["book"] == book_name]
        ok = d[d["eval_breach"] <= breach_cap]
        if len(ok):
            return ok.sort_values("payout", ascending=False).iloc[0]
        return d.sort_values("eval_breach").iloc[0]

    def pick_funded(book_name, breach_cap=0.02):
        d = df[df["book"] == book_name]
        ok = d[d["funded_breach"] <= breach_cap]
        pool = ok if len(ok) else d
        return pool.sort_values("funded_payout_conditional", ascending=False).iloc[0]

    phase_pick = {name: pick(name) for name in PHASE_BOOKS}
    funded_pick = {name: pick_funded(name) for name in FUNDED_BOOKS}

    # End-to-end plan: run the phase book through both phases, then switch the
    # book at funding. This is the only allocation the account actually follows.
    plan_rows = []
    for phase_name, phase_book in PHASE_BOOKS.items():
        pr = phase_pick[phase_name]
        for funded_name, funded_book in FUNDED_BOOKS.items():
            fr = funded_pick[funded_name]
            pe_lots, pe_risk = loads(trades, phase_book, float(pr["target_usd"]))
            fu_lots, fu_risk = loads(trades, funded_book, float(fr["target_usd"]))
            ep = T5.sample_joint(np.stack([rmat.loc[val, s].values for s in phase_book], axis=1), val,
                                 seed=engine.SEED + 77 + len(plan_rows))
            fp = T5.sample_joint(np.stack([rmat.loc[val, s].values for s in funded_book], axis=1), val,
                                 seed=engine.SEED + 78 + len(plan_rows))
            ep_book = (ep * np.array([pe_risk[s] for s in phase_book])).sum(axis=2)
            fp_book = (fp * np.array([fu_risk[s] for s in funded_book])).sum(axis=2)
            res = engine.simulate_moneta(ep_book, np.ones_like(ep_book, bool), 1.0,
                                         funded_paths=fp_book, funded_risk=1.0)
            plan_rows.append({
                "phase_book": phase_name, "phase_target_usd": float(pr["target_usd"]),
                "phase_risk_usd": round(float(sum(pe_risk.values())), 2),
                "funded_book": funded_name, "funded_target_usd": float(fr["target_usd"]),
                "funded_risk_usd": round(float(sum(fu_risk.values())), 2),
                "both_phases_pass": res["pass_both_phases_rate"],
                "eval_breach": res["evaluation_hard_breach_rate"],
                "payout": res["challenge_to_first_payout_rate"],
                "funded_payout_conditional": res["funded_first_payout_rate_conditional"],
                "funded_breach": res["funded_hard_breach_rate_conditional"],
                "days_to_first_payout": res["median_days_to_first_payout_from_start"],
                "expected_first_payout_usd": res["expected_first_payout_usd"],
            })
            print(f"plan {phase_name} ${pr['target_usd']:.0f} -> {funded_name} ${fr['target_usd']:.0f}: "
                  f"both {res['pass_both_phases_rate']:.3f} payout {res['challenge_to_first_payout_rate']:.3f} "
                  f"cond {res['funded_first_payout_rate_conditional']:.3f} "
                  f"fbreach {res['funded_hard_breach_rate_conditional']:.3f}")
    plan = pd.DataFrame(plan_rows)
    plan.to_csv(OUT / "plan_switch.csv", index=False)

    no_gold = plan[plan["funded_book"] == "no gold"]
    plan_pool = no_gold if len(no_gold) else plan
    acceptable = plan_pool[plan_pool["funded_breach"] <= 0.05]
    pool = acceptable if len(acceptable) else plan_pool
    best = pool.sort_values(["payout", "funded_breach"], ascending=[False, True]).iloc[0]
    lines = [
        "# Moneta 2-Step stage sizing with real lot floors",
        "",
        f"Account USD {ACCOUNT:,.0f}. Phase 1 target 5% (USD {ACCOUNT*0.05:,.0f}), Phase 2 target 10% "
        f"(USD {ACCOUNT*0.10:,.0f}), 4% daily loss (USD {ACCOUNT*0.04:,.0f}), 8% static maximum loss "
        f"(USD {ACCOUNT*0.08:,.0f}), 3 profitable days of at least 0.5% (USD {ACCOUNT*0.005:,.0f}) per phase "
        "and per payout cycle, 88% split, 14 calendar-day cycles approximated as 10 trading days.",
        "",
        "Sizing rule: `lots = max(0.01, floor(target / sleeves / 1R_per_lot * 100) / 100)`, so the target is "
        "divided equally but gold cannot go below 0.01 lot and overshoots.",
        "",
        "## 0.01-lot 1R by sleeve",
        "",
        "| Sleeve | 0.01-lot 1R |",
        "|---|---:|",
    ]
    for s in sorted(floor, key=lambda k: -floor[k]):
        lines.append(f"| {s} | ${floor[s]:.2f} |")
    lines += [
        "",
        "## Books at each target",
        "",
        "| Book | Sleeves | Target | Lots | Actual risk | % of $25k | Phase 1 pass | Both phases | Eval breach | Payout | Funded breach | Days | Expected first payout |",
        "|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in df.itertuples():
        lines.append(
            f"| {r.book} | {r.sleeves} | ${r.target_usd:.0f} | {r.lots} | ${r.actual_risk_usd:.2f} | "
            f"{r.pct_of_25k:.2f}% | {r.phase1_pass*100:.1f}% | {r.both_phases_pass*100:.1f}% | "
            f"{r.eval_breach*100:.1f}% | {r.payout*100:.1f}% | {r.funded_breach*100:.1f}% | "
            f"{r.days_to_first_payout:.0f} | ${r.expected_first_payout_usd:.0f} |")
    lines += [
        "",
        "## End-to-end plan with the funded switch",
        "",
        "| Phase book | Phase target | Funded book | Funded target | Both phases | Eval breach | Payout | Conditional payout | Funded breach | Days |",
        "|---|---:|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in plan.itertuples():
        lines.append(f"| {r.phase_book} | ${r.phase_target_usd:.0f} | {r.funded_book} | ${r.funded_target_usd:.0f} | "
                     f"{r.both_phases_pass*100:.1f}% | {r.eval_breach*100:.1f}% | {r.payout*100:.1f}% | "
                     f"{r.funded_payout_conditional*100:.1f}% | {r.funded_breach*100:.1f}% | {r.days_to_first_payout:.0f} |")
    lines += ["", f"Recommended: **{best['phase_book']}** at USD {best['phase_target_usd']:.0f} through Phase 1-2, "
              f"then **{best['funded_book']}** at USD {best['funded_target_usd']:.0f} when funded "
              f"({best['payout']*100:.1f}% first payout, {best['funded_breach']*100:.1f}% funded breach).", ""]
    lines += ["", "## Selected allocations", "",
              "| Stage | Book | Target | Lots | Actual risk | Both phases / payout | Eval breach |",
              "|---|---|---:|---|---:|---:|---:|"]
    alloc = {"account_size_usd": ACCOUNT, "phase_1": {}, "phase_2": {}, "funded": {}}
    for name, r in phase_pick.items():
        lines.append(f"| Phase 1-2 | {name} | ${r['target_usd']:.0f} | {r['lots']} | ${r['actual_risk_usd']:.2f} | "
                     f"{r['both_phases_pass']*100:.1f}% / {r['payout']*100:.1f}% | {r['eval_breach']*100:.1f}% |")
    for name, r in funded_pick.items():
        lines.append(f"| Funded | {name} | ${r['target_usd']:.0f} | {r['lots']} | ${r['actual_risk_usd']:.2f} | "
                     f"{r['funded_payout_conditional']*100:.1f}% / {r['funded_breach']*100:.1f}% | – |")

    # The set-file builder consumes these exact allocations.
    chosen_phase = phase_pick[best["phase_book"]]
    chosen_funded = funded_pick[best["funded_book"]]
    phase_target = float(plan.loc[plan["phase_book"] == best["phase_book"], "phase_target_usd"].iloc[0])
    funded_target = float(plan.loc[plan["funded_book"] == best["funded_book"], "funded_target_usd"].iloc[0])
    for stage, target, book in (("phase_1", phase_target, PHASE_BOOKS[best["phase_book"]]),
                                ("phase_2", phase_target, PHASE_BOOKS[best["phase_book"]]),
                                ("funded", funded_target, FUNDED_BOOKS[best["funded_book"]])):
        lots, risk = loads(trades, book, target)
        alloc[stage] = {
            "book": " + ".join(book),
            "target_usd": target,
            "actual_risk_usd": round(float(sum(risk.values())), 2),
            "sleeves": {s: {"lots": round(lots[s], 2), "risk_usd": round(risk[s], 2)} for s in book},
        }
    alloc["floor_1R"] = {s: round(floor[s], 4) for s in floor}
    (OUT / "ea_allocation.json").write_text(json.dumps(alloc, indent=2), encoding="utf-8")
    lines += ["", "Machine-readable allocation for the EA set files: [ea_allocation.json](ea_allocation.json).", ""]
    (OUT / "stage_sizing.md").write_text("\n".join(lines), encoding="utf-8")
    print("wrote", OUT / "stage_sizing.md")
    print("phase:", alloc["phase_1"]["actual_risk_usd"], "funded:", alloc["funded"]["actual_risk_usd"])


if __name__ == "__main__":
    main()
