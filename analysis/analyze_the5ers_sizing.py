"""The5ers Bootcamp stage sizing: percent-of-balance risk with minimum-lot floors.

The main prop engine sizes a book in fixed dollars. Real EAs size from the
current account balance, and the smallest tradable position (0.01 lot) sets a
dollar floor per sleeve. This script models what the operator actually places:

    risk_i(day) = max(pct * current_balance, min_lot_risk_i)

for each sleeve i, with the evaluation book used through Steps 1-3 and the
funded book used after funding (the real mid-account switch, not a
multiplication of two independent runs).

It writes Prop-Firms/The5ers-20K-Bootcamp/reports/stage_sizing.csv,
stage_sizing.md, book_sizing.csv, pair_sizing.csv and plan_switch.csv. Run:
python analysis/analyze_the5ers_sizing.py
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "analysis"))
import build_live_and_prop_reports as engine  # noqa: E402

OUT = ROOT / "Prop-Firms" / "The5ers-20K-Bootcamp" / "reports"
# The five Gold X9 exports are one EA at five TradeFrequency settings and are
# mutually exclusive: a book may hold one preset, never two.
GOLD_X9 = "Gold X9 (Low)"  # preset chosen by the screening; see reports/strategy_suitability.md
INSTRUMENTS = {
    GOLD_X9: "XAUUSD", "GotobiFix EURJPY": "EURJPY", "GotobiFix USDJPY": "USDJPY",
    "Open Drive": "USTEC", "Flash ORB": "USTEC", "Tokyo Coil": "USDJPY",
    "Overnight Bias ORB": "USTEC",
}
N_SIMS = 5000
HORIZON = 252
BLOCK = 5
SEED = 20261122

EVAL_BOOK = [GOLD_X9, "GotobiFix EURJPY", "GotobiFix USDJPY", "Open Drive"]
FUNDED_BOOK = ["Flash ORB", GOLD_X9, "GotobiFix EURJPY", "Tokyo Coil"]
FUNDED_NO_X9 = ["Flash ORB", "GotobiFix EURJPY", "Tokyo Coil", "Overnight Bias ORB"]
PAIRS = [
    [GOLD_X9, "Overnight Bias ORB"],
    ["GotobiFix EURJPY", "Overnight Bias ORB"],
    ["GotobiFix USDJPY", "Overnight Bias ORB"],
    ["Flash ORB", "Overnight Bias ORB"],
    ["Gold ORB (RBE)", GOLD_X9],
    ["GotobiFix EURJPY", "Tokyo Coil"],
]
EQUAL_SPLIT_USD = 25.0

# Three books, sized to a target risk in whole 0.01 lots.
BOOKS = {
    "Phase book (4 sleeves)": [GOLD_X9, "GotobiFix EURJPY", "GotobiFix USDJPY", "Open Drive"],
    "Phase book (X9 + OBR pair)": [GOLD_X9, "Overnight Bias ORB"],
    "Funded book (no gold)": ["Flash ORB", "GotobiFix EURJPY", "Tokyo Coil", "Overnight Bias ORB"],
    "Low-risk book (Flash + OBR)": ["Flash ORB", "Overnight Bias ORB"],
}
TARGETS = [25.0, 50.0, 100.0]

# (label, evaluation pct per sleeve, funded pct per sleeve, funded book)
SCENARIOS = [
    ("A. Physical minimum, no scaling", 0.00001, 0.00001, FUNDED_BOOK),
    ("B. 0.05%/sleeve, scaled", 0.0005, 0.0005, FUNDED_BOOK),
    ("C. 0.125%/sleeve, scaled", 0.00125, 0.00125, FUNDED_BOOK),
    ("D. 0.25%/sleeve, scaled", 0.0025, 0.0025, FUNDED_BOOK),
    ("E. 0.5%/sleeve, scaled", 0.005, 0.005, FUNDED_BOOK),
    ("F. Min eval, funded without X9 at 0.125%/sleeve", 0.0005, 0.00125, FUNDED_NO_X9),
    ("G. Min eval, funded without X9 at 0.25%/sleeve", 0.0005, 0.0025, FUNDED_NO_X9),
]


def min_lot_risk(trades: pd.DataFrame, strategy: str) -> float:
    """1R in dollars at the broker minimum (0.01 lot).

    Uses the same frozen training-sample risk_unit the R-multiples are built
    from, so the dollar floor and the simulated R paths share one calibration.
    """
    unit = trades.loc[trades["strategy"] == strategy, "risk_unit"]
    if len(unit) and np.isfinite(float(unit.iloc[0])) and float(unit.iloc[0]) > 0:
        return float(unit.iloc[0]) * 0.01
    x = trades[(trades["strategy"] == strategy) & (trades["native_pnl"] < 0)]
    return float((x["native_pnl"].abs() / (x["quantity"] * 100.0)).mean() * 0.01)


def sample_joint(matrix: np.ndarray, date_index, seed: int):
    """Block-bootstrap whole rows so sleeve correlation survives resampling."""
    rng = np.random.default_rng(seed)
    n_days = len(matrix)
    block = max(1, min(BLOCK, n_days))
    nblocks = int(math.ceil(HORIZON / block))
    dates = pd.DatetimeIndex(date_index)
    candidates = np.flatnonzero((dates.weekday == 0) &
                                (np.arange(n_days) + block <= n_days))
    if len(candidates) == 0:
        candidates = np.arange(max(1, n_days - block + 1))
    starts = rng.choice(candidates, size=(N_SIMS, nblocks), replace=True)
    idx = (starts[:, :, None] + np.arange(block)[None, None, :]) % n_days
    idx = idx.reshape(N_SIMS, -1)[:, :HORIZON]
    return matrix[idx]


def simulate_stages(eval_r: np.ndarray, eval_floors: np.ndarray,
                    funded_r: np.ndarray, funded_floors: np.ndarray,
                    eval_pct: float, funded_pct: float):
    n = eval_r.shape[0]
    h = eval_r.shape[1]
    step = np.ones(n, dtype=np.int8)          # 1..3 evaluation, 4 funded, 5 failed
    bal = np.full(n, 5000.0)
    step_balance = (5000.0, 10000.0, 15000.0)
    target = tuple(b * 1.06 for b in step_balance)
    floor = tuple(b * 0.95 for b in step_balance)
    funded_balance = 20000.0
    funded_floor = funded_balance * 0.96

    pass1 = np.full(n, -1, dtype=int)
    pass2 = np.full(n, -1, dtype=int)
    pass3 = np.full(n, -1, dtype=int)
    fail_step = np.zeros((3, n), dtype=bool)
    fail_max = np.zeros(n, dtype=bool)
    f_breach = np.zeros(n, dtype=bool)
    f_breach_day = np.full(n, -1, dtype=int)
    f_age = np.zeros(n, dtype=int)
    payout_day = np.full(n, -1, dtype=int)
    payout = np.zeros(n)
    payout_count = np.zeros(n, dtype=int)
    total_cash = np.zeros(n)
    risk_ratio = np.zeros((4, n))              # realized risk / balance by stage
    risk_days = np.zeros(4, dtype=int)

    for d in range(h):
        start = step.copy()
        start_bal = bal.copy()

        # Evaluation book, one risk budget per sleeve.
        eval_risk = np.maximum(eval_pct * start_bal[:, None], eval_floors[None, :])
        eval_daily = (eval_r[:, d, :] * eval_risk).sum(axis=1)
        # Funded book, same rule.
        f_risk = np.maximum(funded_pct * start_bal[:, None], funded_floors[None, :])
        f_daily = (funded_r[:, d, :] * f_risk).sum(axis=1)

        for idx, st in enumerate((1, 2, 3)):
            m = start == st
            if not m.any():
                continue
            bal[m] += eval_daily[m]
            risk_ratio[idx, m] += eval_risk[m].sum(axis=1) / start_bal[m]
            risk_days[idx] += int(m.sum())
            bad = m & (bal <= floor[idx])
            fail_step[idx] |= bad
            fail_max |= bad
            step[bad] = 5
            ok = m & (step == st) & (bal >= target[idx])
            if ok.any():
                step[ok] = st + 1
                bal[ok] = (10000.0, 15000.0, funded_balance)[idx]
                if st == 1:
                    pass1[ok] = d
                elif st == 2:
                    pass2[ok] = d
                else:
                    pass3[ok] = d
                    f_age[ok] = 0

        funded = (start == 4) & (step == 4)
        if funded.any():
            pause = 0.03 * start_bal[funded]
            raw = f_daily[funded]
            bal[funded] += np.maximum(raw, -pause)
            risk_ratio[3, funded] += f_risk[funded].sum(axis=1) / start_bal[funded]
            risk_days[3] += int(funded.sum())
            f_age[funded] += 1
            bad = funded & (bal <= funded_floor)
            f_breach |= bad
            f_breach_day[bad] = d
            fail_max |= bad
            step[bad] = 5
            # USD 300 gross minimum payout (USD 150 net); smaller gains carry forward.
            due = funded & (step == 4) & (f_age > 0) & (f_age % 10 == 0) & (bal - funded_balance >= 300.0 - 1e-9)
            if due.any():
                amt = np.zeros(n)
                amt[due] = (bal[due] - funded_balance) * 0.50
                total_cash[due] += amt[due]
                payout_count[due] += 1
                first = due & (payout_day < 0)
                payout_day[first] = d
                payout[first] = amt[first]
                bal[due] = funded_balance

    reached = pass3 >= 0
    first_payout = payout_day >= 0
    realized = [float(risk_ratio[i].sum() / risk_days[i]) if risk_days[i] else np.nan
                for i in range(4)]
    return {
        "pass_step1_rate": float((pass1 >= 0).mean()),
        "pass_step2_conditional": float((pass2 >= 0).sum() / max(1, (pass1 >= 0).sum())),
        "pass_step3_conditional": float((pass3 >= 0).sum() / max(1, (pass2 >= 0).sum())),
        "reach_funded_rate": float(reached.mean()),
        "evaluation_hard_breach_rate": float((fail_step[0] | fail_step[1] | fail_step[2]).mean()),
        "funded_first_payout_conditional": float(first_payout[reached].mean()) if reached.any() else 0.0,
        "funded_hard_breach_conditional": float(f_breach[reached].mean()) if reached.any() else 0.0,
        "payout_rate_from_start": float(first_payout.mean()),
        "median_days_to_payout": float(np.median(payout_day[first_payout]) + 1) if first_payout.any() else np.nan,
        "expected_first_payout_usd": float(payout.mean()),
        "median_payout_conditional_usd": float(np.median(payout[first_payout])) if first_payout.any() else np.nan,
        "total_payout_cash_usd": float(total_cash.mean()),
        "payout_count_mean": float(payout_count.mean()),
        "realized_risk_pct_stage1": realized[0] * 100,
        "realized_risk_pct_stage2": realized[1] * 100,
        "realized_risk_pct_stage3": realized[2] * 100,
        "realized_risk_pct_funded": realized[3] * 100,
    }


def calibrate(trades: pd.DataFrame) -> pd.DataFrame:
    """Same frozen training-sample 1R calibration the prop engine uses."""
    dates = pd.bdate_range(trades["exit_date"].min(), trades["exit_date"].max())
    cut = max(1, min(len(dates) - 1, int(len(dates) * 0.60)))
    train_end = dates[cut - 1]
    for strategy, idx in trades.groupby("strategy").groups.items():
        train = trades.loc[idx]
        train = train[train["exit_date"] <= train_end]
        losses = train["native_pnl"]
        losing = losses[losses < 0]
        unit = abs(float(losing.mean())) if len(losing) else float(losses.abs().median())
        if not np.isfinite(unit) or unit <= 0:
            unit = float(losses.abs().mean()) if len(losses) else 1.0
        trades.loc[idx, "risk_unit"] = unit
        trades.loc[idx, "r_multiple"] = trades.loc[idx, "native_pnl"] / unit
        trades.loc[idx, "gross_r_multiple"] = trades.loc[idx, "gross_pnl"] / unit
        trades.loc[idx, "live_pnl"] = trades.loc[idx, "r_multiple"] * 100.0
    return trades


def main():
    trades, _ = engine.load_platform_trades("MT5")
    trades = calibrate(trades)
    dates, rmat, _, _, _ = engine.make_matrices(trades)
    cut = max(1, min(len(dates) - 1, int(len(dates) * 0.60)))
    val = dates[cut:]

    sleeves = sorted({s for _, _, _, book in SCENARIOS for s in book}
                     | set(EVAL_BOOK) | {s for book in PAIRS for s in book})
    floors = {s: min_lot_risk(trades, s) for s in sleeves}
    print("min-lot 1R ($, 0.01 lot):", {k: round(v, 2) for k, v in floors.items()})

    eval_r = np.stack([rmat.loc[val, s].values for s in EVAL_BOOK], axis=1)
    eval_paths = sample_joint(eval_r, val, SEED)
    eval_floor_arr = np.array([floors[s] for s in EVAL_BOOK])

    sampled = {}
    for book in {tuple(b) for _, _, _, b in SCENARIOS}:
        book = list(book)
        sampled[tuple(book)] = (
            sample_joint(np.stack([rmat.loc[val, s].values for s in book], axis=1), val, SEED + 1),
            np.array([floors[s] for s in book]),
        )

    rows = []
    for label, ep, fp, fbook in SCENARIOS:
        funded_paths, funded_floor_arr = sampled[tuple(fbook)]
        res = simulate_stages(eval_paths, eval_floor_arr, funded_paths,
                              funded_floor_arr, ep, fp)
        rows.append({"scenario": label,
                     "eval_book": " + ".join(EVAL_BOOK),
                     "funded_book": " + ".join(fbook),
                     "eval_pct_per_sleeve": ep * 100,
                     "funded_pct_per_sleeve": fp * 100,
                     **res})
        print(label, {k: (round(v, 4) if isinstance(v, float) else v) for k, v in res.items()})

    df = pd.DataFrame(rows)

    pair_rows = []
    for book in PAIRS:
        book = list(book)
        paths = sample_joint(np.stack([rmat.loc[val, s].values for s in book], axis=1), val, SEED + 31)
        fl = np.array([floors[s] for s in book])
        minlot = simulate_stages(paths, fl, paths, fl, 1e-5, 1e-5)
        eq = np.full(len(book), EQUAL_SPLIT_USD / len(book))
        equal = simulate_stages(paths, eq, paths, eq, 0.0, 0.0)
        bal = np.full(len(book), float(fl.max()))
        balanced = simulate_stages(paths, bal, paths, bal, 0.0, 0.0)
        pair_rows.append({
            "pair": " + ".join(book),
            "risk_0_01lot_sleeve_1": round(float(fl[0]), 2),
            "risk_0_01lot_sleeve_2": round(float(fl[1]), 2),
            "minlot_total_usd": round(float(fl.sum()), 2),
            "minlot_pct_of_5k": round(float(fl.sum()) / 5000.0 * 100, 2),
            "minlot_pct_of_20k": round(float(fl.sum()) / 20000.0 * 100, 3),
            "minlot_share_sleeve_1_pct": round(float(fl[0]) / float(fl.sum()) * 100, 1),
            "minlot_share_sleeve_2_pct": round(float(fl[1]) / float(fl.sum()) * 100, 1),
            "minlot_reach_funded": minlot["reach_funded_rate"],
            "minlot_eval_breach": minlot["evaluation_hard_breach_rate"],
            "minlot_payout": minlot["payout_rate_from_start"],
            "minlot_funded_breach": minlot["funded_hard_breach_conditional"],
            "minlot_days": minlot["median_days_to_payout"],
            "equal25_payout": equal["payout_rate_from_start"],
            "equal25_funded_breach": equal["funded_hard_breach_conditional"],
            "equal25_days": equal["median_days_to_payout"],
            "balanced_total_usd": round(float(bal.sum()), 2),
            "balanced_pct_of_5k": round(float(bal.sum()) / 5000.0 * 100, 2),
            "balanced_reach_funded": balanced["reach_funded_rate"],
            "balanced_payout": balanced["payout_rate_from_start"],
            "balanced_funded_breach": balanced["funded_hard_breach_conditional"],
            "balanced_days": balanced["median_days_to_payout"],
        })
        print("pair", " + ".join(book), pair_rows[-1]["minlot_total_usd"], round(pair_rows[-1]["minlot_payout"], 3))
    pd.DataFrame(pair_rows).to_csv(OUT / "pair_sizing.csv", index=False)

    # Whole-lot sizing to a target risk: the answer to "why pin them at 0.01 lot".
    import math as _math
    unit = {s: float(trades.loc[trades["strategy"] == s, "risk_unit"].iloc[0])
            for s in rmat.columns}
    book_rows = []
    for name, book in BOOKS.items():
        paths = sample_joint(np.stack([rmat.loc[val, s].values for s in book], axis=1),
                             val, SEED + 47 + len(book))
        for target in TARGETS:
            per = target / len(book)
            lots = {s: max(0.01, _math.floor(per / unit[s] * 100.0 + 1e-9) / 100.0) for s in book}
            risk = {s: lots[s] * unit[s] for s in book}
            fl = np.array([risk[s] for s in book])
            res = simulate_stages(paths, fl, paths, fl, 0.0, 0.0)
            book_rows.append({
                "book": name, "target_usd": target,
                "lots": ", ".join(f"{s} {lots[s]:.2f}" for s in book),
                "actual_risk_usd": round(float(fl.sum()), 2),
                "pct_of_5k": round(float(fl.sum()) / 5000.0 * 100, 2),
                "pct_of_20k": round(float(fl.sum()) / 20000.0 * 100, 2),
                "reach_funded": res["reach_funded_rate"],
                "eval_breach": res["evaluation_hard_breach_rate"],
                "payout": res["payout_rate_from_start"],
                "funded_breach": res["funded_hard_breach_conditional"],
                "days": res["median_days_to_payout"],
            })
            print("book", name, target, book_rows[-1]["actual_risk_usd"],
                  round(book_rows[-1]["payout"], 3))
    pd.DataFrame(book_rows).to_csv(OUT / "book_sizing.csv", index=False)

    def lots_for(target: float, book: list[str]) -> tuple[dict[str, float], float]:
        per = target / len(book)
        lots = {s: max(0.01, _math.floor(per / unit[s] * 100.0 + 1e-9) / 100.0) for s in book}
        return lots, float(sum(lots[s] * unit[s] for s in book))

    # The execution plan: the four-sleeve book sized to USD 50 through Steps
    # 1-3, then the funded switch to the no-gold book at USD 100. Both stages
    # are indexed from one joint matrix so the switch keeps same-day sleeve
    # correlation instead of multiplying two independent runs.
    plan_sleeves = list(dict.fromkeys(EVAL_BOOK + FUNDED_NO_X9))
    plan_paths = sample_joint(
        np.stack([rmat.loc[val, s].values for s in plan_sleeves], axis=1), val, SEED + 73)
    column = {s: i for i, s in enumerate(plan_sleeves)}
    phase_lots, phase_risk = lots_for(50.0, EVAL_BOOK)
    funded_lots, funded_risk = lots_for(100.0, FUNDED_NO_X9)
    plan_res = simulate_stages(
        plan_paths[:, :, [column[s] for s in EVAL_BOOK]],
        np.array([phase_lots[s] * unit[s] for s in EVAL_BOOK]),
        plan_paths[:, :, [column[s] for s in FUNDED_NO_X9]],
        np.array([funded_lots[s] * unit[s] for s in FUNDED_NO_X9]),
        0.0, 0.0)
    plan = {
        "phase_book": " + ".join(EVAL_BOOK),
        "phase_target_usd": 50.0,
        "phase_lots": ", ".join(f"{s} {phase_lots[s]:.2f}" for s in EVAL_BOOK),
        "phase_risk_usd": round(phase_risk, 2),
        "funded_book": " + ".join(FUNDED_NO_X9),
        "funded_target_usd": 100.0,
        "funded_lots": ", ".join(f"{s} {funded_lots[s]:.2f}" for s in FUNDED_NO_X9),
        "funded_risk_usd": round(funded_risk, 2),
        **plan_res,
    }
    pd.DataFrame([plan]).to_csv(OUT / "plan_switch.csv", index=False)
    plan_row = (
        f"| {plan['phase_lots']} | " "$" f"{plan['phase_risk_usd']:.2f} | {plan['funded_lots']} | "
        "$" f"{plan['funded_risk_usd']:.2f} | "
        f"{plan['reach_funded_rate']*100:.1f}% | {plan['evaluation_hard_breach_rate']*100:.1f}% | "
        f"{plan['payout_rate_from_start']*100:.1f}% | {plan['funded_hard_breach_conditional']*100:.1f}% | "
        f"{plan['median_days_to_payout']:.0f} | " "$" f"{plan['expected_first_payout_usd']:.0f} |"
    )
    print("plan switch", plan["reach_funded_rate"], plan["payout_rate_from_start"])

    OUT.mkdir(parents=True, exist_ok=True)
    df.to_csv(OUT / "stage_sizing.csv", index=False)

    lines = [
        "# The5ers $20k Bootcamp — stage sizing with real lot floors",
        "",
        "The main prop engine sizes a book in continuous dollars. Real EAs size in",
        "whole lots, and 0.01 lot is the smallest position the broker allows, so each",
        "sleeve has a dollar risk floor. On a $5k step the floor, not the percentage,",
        "decides the risk. This report models `risk_i = max(pct x balance, 0.01-lot 1R_i)`",
        "per sleeve, with the evaluation book through Steps 1-3 and the funded book",
        "after funding (the real switch, not a product of two independent runs). A payout",
        "requires at least USD 300 gross (USD 150 net at the 50% split).",
        "",
        "## 0.01-lot 1R per sleeve (mean losing trade at 0.01 lot, from the export)",
        "",
        "| Sleeve | Instrument | 1R at 0.01 lot |",
        "|---|---|---:|",
    ]
    for sleeve in EVAL_BOOK + ["Flash ORB", "Tokyo Coil", "Overnight Bias ORB"]:
        lines.append(f"| {sleeve} | {INSTRUMENTS.get(sleeve, '')} | ${floors[sleeve]:.2f} |")
    lines += [
        "",
        "Gold X9 is the binding floor: 0.01 lot is already ~$20 of mean risk, which is",
        "0.4% of a $5k step by itself. The FX and index sleeves cost $0.04-$1.15 at the",
        "same minimum, so they cannot be scaled down to match a percentage either —",
        "the book is gold-heavy at minimum size no matter what percentage you set.",
        "",
        "## Scenarios",
        "",
        "| Scenario | Stage 1 risk | Step 2 | Step 3 | Funded | Reach funded | Eval breach | First payout | Funded breach | Median payout days | Expected first payout |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for _, r in df.iterrows():
        lines.append(
            f"| {r['scenario']} | {r['realized_risk_pct_stage1']:.2f}% | "
            f"{r['realized_risk_pct_stage2']:.2f}% | {r['realized_risk_pct_stage3']:.2f}% | "
            f"{r['realized_risk_pct_funded']:.2f}% | {r['reach_funded_rate']*100:.1f}% | "
            f"{r['evaluation_hard_breach_rate']*100:.1f}% | "
            f"{r['payout_rate_from_start']*100:.1f}% | "
            f"{r['funded_hard_breach_conditional']*100:.1f}% | "
            f"{r['median_days_to_payout']:.0f} | ${r['expected_first_payout_usd']:.0f} |")
    lines += [
        "",
        "Realized risk is the average of (sum of sleeve dollar risk / start-of-day balance)",
        "over that stage's trading days, so it shows the minimum-lot distortion directly.",
        "\"Reach funded\" is the probability of passing all three steps; \"first payout\" includes",
        "the funded stage; \"funded breach\" is conditional on reaching the funded account.",
        "",
        "## Two-sleeve pairs",
        "",
        "Pairs are the only books where the minimum-lot split is visible: the cheap sleeve",
        "cannot be scaled down to match the expensive one, so the split is not 50/50.",
        "",
        "| Pair | 0.01-lot risk (sleeve 1 / 2) | Total | % of $5k step | Split (1 / 2) | Reach funded | Eval breach | Payout | Funded breach | Balanced risk | Balanced payout | Balanced breach |",
        "|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in pair_rows:
        lines.append(
            f"| {r['pair']} | ${r['risk_0_01lot_sleeve_1']:.2f} / ${r['risk_0_01lot_sleeve_2']:.2f} | "
            f"${r['minlot_total_usd']:.2f} | {r['minlot_pct_of_5k']:.2f}% | "
            f"{r['minlot_share_sleeve_1_pct']:.0f}% / {r['minlot_share_sleeve_2_pct']:.0f}% | "
            f"{r['minlot_reach_funded']*100:.1f}% | {r['minlot_eval_breach']*100:.1f}% | "
            f"{r['minlot_payout']*100:.1f}% | {r['minlot_funded_breach']*100:.1f}% | "
            f"${r['balanced_total_usd']:.2f} | {r['balanced_payout']*100:.1f}% | "
            f"{r['balanced_funded_breach']*100:.1f}% |")
    lines += [
        "",
        "\"Balanced\" sizes both sleeves to the larger one's 0.01-lot risk (a placeable",
        "whole-lot size for the cheap sleeve), so the book is no longer gold-dominated but",
        "the total risk roughly doubles. The minimum-lot column is the gold-dominated",
        "reality; the USD 25 equal-split model (12.50 per sleeve) is not placeable on Gold",
        "X9 or Gold ORB (RBE), which need more than that for one 0.01 lot.",
        "",
        "## Reading it",
        "",
        "- Scenarios B-E all start from the same stage-1 floor, so stage 1 is nearly",
        "  identical; the percentage only starts to bite on Steps 2-3 and funded.",
        "- Scaling the funded book with the balance is what breaks it: at 0.125%/sleeve",
        "  the funded book with Gold X9 breaches the 4% floor in more than half of paths.",
        "- The fix is to drop Gold X9 from the funded book (F-G): the remaining sleeves",
        "  are cheap at 0.01 lot, so the same percentage is a much smaller book and the",
        "  funded breach collapses.",
        "",
        "## Books sized to a target risk, in whole 0.01 lots",
        "",
        "0.01 lot is not a strategy choice, it is the broker floor. This table sizes each",
        "book to a target risk instead, rounds down to 0.01 lots, and never goes below the",
        "floor, so gold still overshoots its share.",
        "",
        "| Book | Target | Lots | Actual risk | % of $5k | % of $20k | Reach funded | Eval breach | Payout | Funded breach | Median days |",
        "|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in book_rows:
        lines.append(
            f"| {r['book']} | ${r['target_usd']:.0f} | {r['lots']} | ${r['actual_risk_usd']:.2f} | "
            f"{r['pct_of_5k']:.2f}% | {r['pct_of_20k']:.2f}% | {r['reach_funded']*100:.1f}% | "
            f"{r['eval_breach']*100:.1f}% | {r['payout']*100:.1f}% | {r['funded_breach']*100:.1f}% | "
            f"{r['days']:.0f} |")
    lines += [
        "",
        "Reading: the cheap books only work once they are sized up, and their limit is",
        "time, not risk. At USD 25 total the cheap pairs pass Step 1 in 96-99% of paths but",
        "cannot finish three steps inside 252 days; at USD 50 they complete. Gold still",
        "cannot be sized below 0.01 lot, so any gold book overshoots its target share.",
        "",
        "## Execution plan with the funded switch",
        "",
        "The plan places the four-sleeve evaluation book at a USD 50 target through",
        "Steps 1-3, then switches to the no-gold funded book at USD 100. Both stages",
        "share one path matrix, so the switch is simulated, not multiplied.",
        "",
        "| Phase lots (USD 50) | Phase risk | Funded lots (USD 100) | Funded risk | Reach funded | Eval breach | First payout | Funded breach | Median payout days | Expected first payout |",
        "|---|---:|---|---:|---:|---:|---:|---:|---:|---:|",
        plan_row,
        "",
        "Conditional first payout after funding is "
        f"{plan['funded_first_payout_conditional']*100:.1f}%; median payout on successful paths is "
        f"$" f"{plan['median_payout_conditional_usd']:.0f}.",
        "",
        "## Recommended settings (verified against the EA sources)",
        "",
        "Sleeves and inputs are in the MetaQuotes terminal tree, not in this repo.",
        "Hold these unchanged through Steps 1-3; do not scale them as the balance grows.",
        "",
        "| EA (file) | Input | Challenge value | Funded value |",
        "|---|---|---|---|",
        "| Gold X9 (`1. X9/Gold_X9_v6_3.mq5`) | `Lotsizing_Method` / `FixedLots` | `Manual_Lotsize` / `0.01` | not traded |",
        "| GotobiFix (`5. GotobiFix/GotobiFix.mq5`) | `Lots` / `MaxExposureLots` | `0.05` / `0.10` per pair | `0.24` / `0.50` (EURJPY) |",
        "| Open Drive (`4. Index Book/3. OpenDrive`) | `RiskMoney` (with `UseFixedLots=false`) | `8` | not traded |",
        "| Flash ORB (`4. Index Book/7. FlashTriggerORB`) | `RiskMoney` (with `UseFixedSize=false`) | not traded | `25` |",
        "| Tokyo Coil (`3. TokyoCoil`) | `RiskMoney` (with `RiskPct` ignored) | not traded | `25` |",
        "| Overnight Bias ORB (`4. Index Book/2. OvernightBiasRangeBreakout`) | `RiskMoney` (with `UseFixedSize=false`) | not traded | `25` |",
        "",
        "Why these inputs: Gold X9 defaults to `Tiered_Lotsizing`, whose per-trade budget",
        "is `(TieredLot/DDTierDivisor) x balance x 0.0001 x RiskWeight`; with the shipped",
        "`TieredLot=30` and `RiskWeight` summing to ~2.84 over nine strategies that is",
        "about $1.50 per strategy at $5k, below the 0.01-lot floor, so the EA always",
        "min-lots on a small account. `Manual_Lotsize` makes that explicit.",
        "GotobiFix has only fixed lots; Flash ORB, Overnight Bias and the rest of the",
        "Index Book have `RiskMoney` (fixed cash) or fixed lots, not percentage risk.",
        "Only Open Drive (`RiskPercent`) and Tokyo Coil (`RiskPct`) offer percentage",
        "sizing, which is why they are listed with fixed `RiskMoney` when the plan calls",
        "for a constant dollar book.",
        "",
        "Model limits: closed-PnL only (no floating-loss breaches), no spread/slippage",
        "beyond the export, no evaluation fees, funded scale-up ladder not modeled.",
        "1R is a realized-loss proxy, not the initial stop.",
    ]
    (OUT / "stage_sizing.md").write_text(chr(10).join(lines) + chr(10), encoding="utf-8")
    print("wrote", OUT / "stage_sizing.csv")


if __name__ == "__main__":
    main()
