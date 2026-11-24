"""Check C# T1-T4 predicates against the existing Python setup ledgers."""

import argparse
from pathlib import Path

import pandas as pd


def expected(row, model):
    exact_friday = pd.Timestamp(row.friday_date).date() == pd.Timestamp(row.session_date).date() - pd.Timedelta(days=3)
    if not exact_friday:
        return False
    if model == "T1":
        return row.monday_close <= 0.99 * row.friday_close
    if model == "T2":
        return row.monday_close < row.monday_open and row.ibs < 0.20
    return row.monday_close < row.friday_close and row.ibs < 0.50


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", type=Path)
    args = parser.parse_args()
    bad = 0
    for asset in ("ES", "NQ", "MES", "MNQ"):
        for model in ("T1", "T2", "T3", "T4"):
            path = args.results / f"{asset}_{model}_setups.csv"
            rows = pd.read_csv(path)
            derived = rows.apply(lambda row: expected(row, model), axis=1)
            recorded = rows.status.eq("SIGNAL")
            comparable = ~rows.reason.eq("MISSING_EXIT_SESSION")
            mismatches = int(((derived != recorded) & comparable).sum())
            bad += mismatches
            excluded = int((~comparable).sum())
            print(f"{asset:3} {model} signals={int(recorded.sum()):3} mismatches={mismatches} end_rows={excluded}")
        trades = pd.read_csv(args.results / f"{asset}_T1_baseline_unstopped_trades.csv")
        for row in trades.head(2).itertuples():
            print(f"  CHECK {row.session_date}: Monday C={row.monday_close:.2f}; "
                  f"entry {row.entry_time} @ {row.entry_price:.2f}; "
                  f"exit {row.exit_time} @ {row.exit_price:.2f}")
    raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
    main()
