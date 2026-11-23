"""The5ers Bootcamp stage sizing: percent-of-balance risk with minimum-lot floors.

The main prop engine sizes a book in fixed dollars. Real EAs size from the
current account balance, and the smallest tradable position (0.01 lot) sets a
dollar floor per sleeve. This script models what the operator actually places:

    risk_i(day) = max(pct * current_balance, min_lot_risk_i)

for each sleeve i, with the evaluation book used through Steps 1-3 and the
funded book used after funding (the real mid-account switch, not a
multiplication of two independent runs).

It writes Prop-Firms/The5ers-20K-Bootcamp/reports/stage_sizing.csv and
stage_sizing.md. Run: python analysis/analyze_the5ers_sizing.py
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
INSTRUMENTS = {
    "Gold X9": "XAUUSD", "GotobiFix EURJPY": "EURJPY", "GotobiFix USDJPY": "USDJPY",
    "Open Drive": "USTEC", "Flash ORB": "USTEC", "Tokyo Coil": "USDJPY",
    "Overnight Bias ORB": "USTEC",
}
N_SIMS = 5000
HORIZON = 252
BLOCK = 5
SEED = 20261122

EVAL_BOOK = ["Gold X9", "GotobiFix EURJPY", "GotobiFix USDJPY", "Open Drive"]
FUNDED_BOOK = ["Flash ORB", "Gold X9", "GotobiFix EURJPY", "Tokyo Coil"]
FUNDED_NO_X9 = ["Flash ORB", "GotobiFix EURJPY", "Tokyo Coil", "Overnight Bias ORB"]

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
    """1R in dollars at the broker minimum (0.01 lot), from the export itself."""
    x = trades[(trades["strategy"] == strategy) & (trades["native_pnl"] < 0)]
    per_001 = x["native_pnl"].abs() / (x["quantity"] * 100.0)
    return float(per_001.mean())


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
            due = funded & (step == 4) & (f_age > 0) & (f_age % 10 == 0) & (bal > funded_balance + 1e-9)
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

    sleeves = sorted({s for _, _, _, book in SCENARIOS for s in book} | set(EVAL_BOOK))
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
        "after funding (the real switch, not a product of two independent runs).",
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
