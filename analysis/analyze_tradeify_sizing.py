"""Tradeify $50k Growth: contract-level stage sizing for the NT8 books.

The prop engine sizes NT8 books from a requested dollar risk and then rounds to
whole micros. That hides the real constraint: on NQ a single micro already has a
mean losing trade of roughly USD 127-182, so the broker minimum is not a small
position on a $50k account with a $2,000 trailing drawdown. This script
enumerates whole-contract allocations per sleeve, enforces the four-mini
concurrent cap, and reports the evaluation/funded odds at each.

Run: python analysis/analyze_tradeify_sizing.py
Writes reports/prop-firms/Tradeify-50K-Growth-Futures/reports/stage_sizing.{csv,md}.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "analysis"))
import build_live_and_prop_reports as engine  # noqa: E402

OUT = ROOT / "reports" / "prop-firms" / "Tradeify-50K-Growth-Futures" / "reports"
N_SIMS = 5000
HORIZON = 252
SEED = 20261123

CHALLENGE_BOOK = ["FVG Duo", "Flash ORB", "Gold ORB (RBE)", "Sigma ORB"]
FUNDED_BOOK = ["Flash ORB", "Gold ORB (RBE)", "Opening-Shock Continuation", "Sigma ORB"]
PAIR_BOOK = ["Flash ORB", "Overnight Bias ORB"]

# mini-equivalents per sleeve; 0.1 = one micro
ALLOCATIONS = [0.1, 0.2, 0.3, 0.5, 1.0]


def calibrate(trades: pd.DataFrame) -> pd.DataFrame:
    """Freeze 1R on the first 60% of sessions, as the prop engine does."""
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
        trades.loc[idx, "live_pnl"] = trades.loc[idx, "native_pnl"]
    return trades


def run_book(trades, rmat, gross_rmat, activemat, val, book, k, label, seed):
    units = {s: float(trades.loc[trades["strategy"] == s, "risk_unit"].iloc[0]) for s in book}
    weights = {s: k * units[s] for s in book}
    sizes = {s: k for s in book}
    exposure = engine.max_concurrent_mini_equiv(trades, book, sizes)
    compliant = exposure <= 4.0 + 1e-9
    book_daily = engine.weighted_daily_pnl(rmat, val, book, weights)
    gross_daily = engine.weighted_daily_pnl(gross_rmat, val, book, weights)
    active = activemat.loc[val, book].any(axis=1)
    paired = np.column_stack([book_daily.values, gross_daily.values])
    paths, act = engine.sample_block_paths(paired, active.values, seed=seed, date_index=val)
    t = trades[trades["strategy"].isin(book) &
               trades["exit_date"].between(val.min(), val.max())]
    micro = engine.microscalping_stats(t)
    net_paths = paths[:, :, 0]
    clip_binding = float((net_paths < -1250.0).mean())
    worst_day = float(net_paths.min())
    res = engine.simulate_tradeify(paths[:, :, 0], act, 1.0, micro["eligible"],
                                   engine.weekly_activity_ok(active),
                                   position_limit_compliant=compliant,
                                   consistency_paths=paths[:, :, 1])
    risk_total = float(sum(weights.values()))
    return {
        "book": label,
        "strategies": " + ".join(book),
        "mini_equiv_per_sleeve": k,
        "micros_per_sleeve": int(round(k * 10)),
        "concurrent_mini_equiv": round(exposure, 2),
        "position_limit_compliant": compliant,
        "risk_per_book_trade_usd": round(risk_total, 2),
        "risk_pct_of_50k": round(100.0 * risk_total / 50000.0, 2),
        "R_buffer_to_2000_trail": round(2000.0 / risk_total, 2) if risk_total else np.nan,
        "microscalping_eligible": micro["eligible"],
        "validation_trade_share_over_10s": micro["trade_share_over_10s"],
        "share_of_days_below_1250_dll": round(clip_binding, 5),
        "worst_simulated_day_usd": round(worst_day, 2),
        **res,
    }


def main():
    trades, _ = engine.load_platform_trades("NT8")
    trades = calibrate(trades)
    dates, rmat, _, _, activemat = engine.make_matrices(trades)
    cut = max(1, min(len(dates) - 1, int(len(dates) * 0.60)))
    val = dates[cut:]
    gross_rmat = pd.DataFrame(
        {s: trades[trades["strategy"] == s].groupby("exit_date")["gross_r_multiple"]
         .sum().reindex(val, fill_value=0.0) for s in rmat.columns}, index=val)

    rows = []
    for book, label, seed in [(CHALLENGE_BOOK, "Challenge book", SEED),
                              (FUNDED_BOOK, "Funded book", SEED + 7),
                              (PAIR_BOOK, "Lower-risk pair", SEED + 13)]:
        for k in ALLOCATIONS:
            rows.append(run_book(trades, rmat, gross_rmat, activemat, val, book, k,
                                 label, seed + int(k * 10)))
    df = pd.DataFrame(rows)
    OUT.mkdir(parents=True, exist_ok=True)
    df.to_csv(OUT / "stage_sizing.csv", index=False)

    def pick(row, keys, default=np.nan):
        for key in keys:
            if key in row and pd.notna(row[key]):
                return row[key]
        return default

    lines = [
        "# Tradeify $50k Growth — stage sizing in whole contracts",
        "",
        "The prop engine starts from a requested dollar risk and rounds to whole",
        "micros. That hides the binding constraint: on NQ a single micro has a mean",
        "losing trade of roughly USD 127-182, so one micro per sleeve is already",
        "about 1% of a $50k account against a $2,000 trailing drawdown. This report",
        "enumerates contract allocations per sleeve, enforces the four-mini",
        "concurrent cap, and reports the odds at each.",
        "",
        "## 1R per sleeve in the NT8 exports",
        "",
        "| Sleeve | Instrument | 1R per mini | 1R per micro (0.1) |",
        "|---|---|---:|---:|",
    ]
    units = trades.groupby("strategy")["risk_unit"].first()
    instr = trades.groupby("strategy")["instrument"].first()
    for s in CHALLENGE_BOOK + [x for x in FUNDED_BOOK + PAIR_BOOK if x not in CHALLENGE_BOOK]:
        lines.append(f"| {s} | {instr[s]} | ${units[s]:,.0f} | ${units[s]/10:,.0f} |")
    lines += [
        "",
        "## Allocation ladder",
        "",
        "| Book | Minis/sleeve | Micros/sleeve | Risk per trade | % of $50k | R to $2k trail | Pass | Eval breach | Funded breach | Payout | Median payout days | Days below the $1,250 clip |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for _, r in df.iterrows():
        lines.append(
            f"| {r['book']} | {r['mini_equiv_per_sleeve']:g} | {r['micros_per_sleeve']} | "
            f"${r['risk_per_book_trade_usd']:,.0f} | {r['risk_pct_of_50k']:.2f}% | "
            f"{r['R_buffer_to_2000_trail']:.1f} | "
            f"{(pick(r, ['evaluation_pass_rate']))*100:.1f}% | "
            f"{r['evaluation_hard_breach_rate']*100:.1f}% | "
            f"{r['funded_hard_breach_rate_conditional']*100:.1f}% | "
            f"{r['challenge_to_first_payout_rate']*100:.1f}% | "
            f"{r['median_days_to_first_payout_from_start']:.0f} | "
            f"{r['share_of_days_below_1250_dll']*100:.1f}% |")
    lines += [
        "",
        "## What to set, stage by stage",
        "",
        "NT8 sizing is whole contracts, so the settings are contract counts, not",
        "percentages. `FixedContracts` is the input on every sleeve; Flash ORB,",
        "FVG Duo and Open Drive also expose `RiskPercent` with `UseFixedContracts`",
        "off, but that scales position size with account equity and will exceed the",
        "four-mini cap on a $50k account once the book is sized sanely.",
        "",
        "| EA (NinjaScript) | Evaluation | Funded |",
        "|---|---|---|",
        "| FVG Duo (`FVG_Duo_NT8.cs`) | 1 micro (0.1), `SizingMode=FixedContracts`, on MNQ | not traded |",
        "| Flash ORB (`FlashTriggerOrbNT8.cs`) | 1 micro, `UseFixedContracts=true`, `FixedContracts=1` on MNQ | 1 micro |",
        "| Gold ORB RBE (`RangeBreakoutNT8.cs`) | 1 micro on MGC | 1 micro |",
        "| Sigma ORB (`SigmaBreakoutNT8.cs`) | 1 micro on MNQ | 1 micro |",
        "| Opening-Shock Continuation (`OpeningShockContinuationNT8.cs`) | not traded | 1 micro |",
        "| Overnight Bias ORB (`OvernightBiasRangeBreakoutNT8.cs`) | lower-risk alternative to FVG | 1 micro (alternative book) |",
        "",
        "One contract on MNQ/MGC equals one micro, so `FixedContracts=1` is the",
        "minimum position; it is also the only allocation that keeps the book inside",
        "a sane R buffer. Nothing scales with the account: the four-mini cap and the",
        "$2,000 trail both bind first.",
        "",
        "**Rows above one micro per sleeve are not tradeable recommendations.** The",
        "simulator clips a day's loss at the $1,250 soft daily limit; once a single",
        "trade's risk approaches that limit the clip stops being a stop and starts",
        "hiding the loss, which is why the large-size rows do not degrade the way the",
        "R-buffer column says they should. The last column shows how often the clip",
        "binds: at one micro it is rare, above two micros it is routine.",
        "",
        "Model limits: closed-PnL only, EOD trailing drawdown, no intraday floating",
        "losses, whole-micro rounding is exact here because every sleeve is set to a",
        "whole number of micros. 1R is a realized-loss proxy, not the initial stop.",
    ]
    (OUT / "stage_sizing.md").write_text(chr(10).join(lines) + chr(10), encoding="utf-8")
    print(df[["book", "mini_equiv_per_sleeve", "risk_per_book_trade_usd",
              "risk_pct_of_50k", "R_buffer_to_2000_trail",
              "evaluation_pass_rate", "challenge_to_first_payout_rate",
              "funded_hard_breach_rate_conditional"]].to_string(index=False))
    print("wrote", OUT / "stage_sizing.csv")


if __name__ == "__main__":
    main()
