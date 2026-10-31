#!/usr/bin/env python3
"""
NQ Precision Bot Equity Curve Generator
Generates per-platform equity curves (NT8 and MT5 separately):
1. NT8 Equity Curve:
   - Starting Capital: $25,000
   - Sizing: 1 NQ contract fixed
   - Commission: $5.76 round-trip / contract (Tradeify all-in rate)
   - Point value: $20/pt
2. MT5 Equity Curve:
   - Starting Capital: $25,000
   - Sizing: Fixed $100 risk (cost-inclusive) on USTEC
   - Output: separate charts with cumulative equity, drawdown shaded area,
     annual boundary lines, and performance metrics table.
"""

from __future__ import annotations

import argparse
import csv
import glob
import math
import os
import sys
from datetime import datetime
from typing import Any, Dict, List, Tuple

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import numpy as np


def parse_nt8_trades(csv_path: str, commission_per_contract: float = 5.76) -> List[Dict[str, Any]]:
    """Loads NT8 trades and re-calculates P&L for exactly 1 contract at $5.76 commission."""
    trades = []
    if not os.path.exists(csv_path):
        print(f"[!] File not found: {csv_path}")
        return trades

    with open(csv_path, mode="r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if "NT8 Entry Price" in row and "NT8 Exit Price" in row:
                # NQPrecisionBot_315_Completed_Trade_Parity.csv
                d_str = row.get("Date", "").strip()
                direction = row.get("Direction", "").strip().upper()
                entry_px = float(row.get("NT8 Entry Price", 0.0))
                exit_px = float(row.get("NT8 Exit Price", 0.0))
                exit_reason = row.get("NT8 Exit Reason", "").strip()

                mult = 1 if "LONG" in direction or "BUY" in direction else -1
                pts = mult * (exit_px - entry_px)
                gross_1con = pts * 20.0  # 1 NQ contract = $20/pt
                net_1con = gross_1con - commission_per_contract

                trades.append({
                    "date": datetime.strptime(d_str, "%Y-%m-%d"),
                    "direction": direction,
                    "entry_price": entry_px,
                    "exit_price": exit_px,
                    "points": pts,
                    "gross": gross_1con,
                    "commission": commission_per_contract,
                    "net": net_1con,
                    "exit_reason": exit_reason,
                })
            elif "Market pos." in row or "Market pos" in row:
                # Strategy Analyzer export
                entry_t = row.get("Entry time", "").strip()
                pos = row.get("Market pos.", row.get("Market pos", "")).upper()
                entry_px = float(row.get("Entry price", "0").replace("$", "").replace(",", ""))
                exit_px = float(row.get("Exit price", "0").replace("$", "").replace(",", ""))
                qty = float(row.get("Qty", 1.0))
                profit = float(row.get("Profit", "0").replace("$", "").replace(",", ""))
                exit_reason = row.get("Exit name", "").strip()

                d_str = entry_t.split()[0]
                dt = datetime.strptime(d_str, "%m/%d/%Y")

                mult = 1 if "LONG" in pos or "BUY" in pos else -1
                pts = mult * (exit_px - entry_px)
                gross_1con = pts * 20.0
                net_1con = gross_1con - commission_per_contract

                trades.append({
                    "date": dt,
                    "direction": pos,
                    "entry_price": entry_px,
                    "exit_price": exit_px,
                    "points": pts,
                    "gross": gross_1con,
                    "commission": commission_per_contract,
                    "net": net_1con,
                    "exit_reason": exit_reason,
                })
            elif "EntryPrice" in row and "ExitPrice" in row:
                # Custom NQPrecisionBot_trades.csv
                d_str = row.get("Date", "").strip()
                direction = row.get("Direction", "").strip().upper()
                entry_px = float(row.get("EntryPrice", 0.0))
                exit_px = float(row.get("ExitPrice", 0.0))
                mult = 1 if "LONG" in direction or "BUY" in direction else -1
                pts = mult * (exit_px - entry_px)
                gross_1con = pts * 20.0
                net_1con = gross_1con - commission_per_contract

                trades.append({
                    "date": datetime.strptime(d_str, "%Y-%m-%d"),
                    "direction": direction,
                    "entry_price": entry_px,
                    "exit_price": exit_px,
                    "points": pts,
                    "gross": gross_1con,
                    "commission": commission_per_contract,
                    "net": net_1con,
                    "exit_reason": "",
                })

    trades.sort(key=lambda x: x["date"])
    return trades


def parse_mt5_trades(csv_path: str) -> List[Dict[str, Any]]:
    """Loads MT5 trades from NQPrecision_test_*.trades.csv."""
    trades = []
    if not os.path.exists(csv_path):
        print(f"[!] File not found: {csv_path}")
        return trades

    with open(csv_path, mode="r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if "entry_server" in row and "adjusted_net" in row:
                d_str = row.get("central_date", "").replace(".", "-").strip()
                t_str = row.get("entry_server", "").strip()
                side = row.get("side", "").strip().upper()
                vol = float(row.get("volume", 1.0))
                entry_px = float(row.get("entry_price", 0.0))
                exit_px = float(row.get("exit_price", 0.0))
                broker_net = float(row.get("broker_net", 0.0))
                cost = float(row.get("modeled_cost", 0.0))
                net = float(row.get("adjusted_net", broker_net - cost))
                exit_reason = row.get("exit_reason", "")

                dt = datetime.strptime(d_str, "%Y-%m-%d")
                trades.append({
                    "date": dt,
                    "direction": side,
                    "entry_price": entry_px,
                    "exit_price": exit_px,
                    "volume": vol,
                    "gross": broker_net,
                    "cost": cost,
                    "net": net,
                    "exit_reason": exit_reason,
                })

    trades.sort(key=lambda x: x["date"])
    return trades


def compute_metrics(trades: List[Dict[str, Any]], starting_capital: float = 25000.0) -> Dict[str, Any]:
    """Computes comprehensive performance statistics."""
    if not trades:
        return {}

    equity = [starting_capital]
    dates = [trades[0]["date"]]
    daily_returns = []

    cum = starting_capital
    peak = starting_capital
    max_dd_dollars = 0.0
    max_dd_pct = 0.0
    wins = 0
    losses = 0
    gross_profit = 0.0
    gross_loss = 0.0

    annual_pnl: Dict[int, float] = {}

    for t in trades:
        net = t["net"]
        cum += net
        equity.append(cum)
        dates.append(t["date"])

        if net > 0:
            wins += 1
            gross_profit += net
        else:
            losses += 1
            gross_loss += abs(net)

        if cum > peak:
            peak = cum
        dd_d = peak - cum
        dd_p = (dd_d / peak) * 100.0 if peak > 0 else 0.0
        if dd_d > max_dd_dollars:
            max_dd_dollars = dd_d
        if dd_p > max_dd_pct:
            max_dd_pct = dd_p

        yr = t["date"].year
        annual_pnl[yr] = annual_pnl.get(yr, 0.0) + net

    total_net = cum - starting_capital
    total_trades = len(trades)
    win_rate = (wins / total_trades) * 100.0 if total_trades > 0 else 0.0
    profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else float("inf")

    # Sharpe approximation
    pnls = [t["net"] for t in trades]
    pnl_std = float(np.std(pnls)) if len(pnls) > 1 else 1.0
    sharpe = (float(np.mean(pnls)) / pnl_std * math.sqrt(252)) if pnl_std > 0 else 0.0

    return {
        "starting_capital": starting_capital,
        "ending_equity": cum,
        "total_net_pnl": total_net,
        "total_return_pct": (total_net / starting_capital) * 100.0,
        "total_trades": total_trades,
        "wins": wins,
        "losses": losses,
        "win_rate": win_rate,
        "profit_factor": profit_factor,
        "max_dd_dollars": max_dd_dollars,
        "max_dd_pct": max_dd_pct,
        "sharpe": sharpe,
        "annual_pnl": annual_pnl,
        "equity_series": equity,
        "date_series": dates,
    }


def plot_equity_curve(
    metrics: Dict[str, Any],
    title: str,
    subtitle: str,
    output_png: str,
    accent_color: str = "#00c3ff",
):
    """Renders professional equity curve with drawdown shading and annual stats table."""
    if not metrics:
        print(f"[!] No metrics to plot for {title}")
        return

    dates = metrics["date_series"]
    equity = np.array(metrics["equity_series"])

    # Compute high-water mark and drawdown
    hwm = np.maximum.accumulate(equity)
    drawdown = hwm - equity

    plt.style.use("dark_background")
    fig, (ax_main, ax_dd) = plt.subplots(
        2, 1, figsize=(14, 9), gridspec_kw={"height_ratios": [3.2, 1.2]}, sharex=True
    )
    fig.patch.set_facecolor("#0b0f19")
    ax_main.set_facecolor("#111827")
    ax_dd.set_facecolor("#111827")

    # Main equity curve
    ax_main.plot(dates, equity, color=accent_color, linewidth=2.2, label="Portfolio Equity", zorder=4)
    ax_main.plot(dates, hwm, color="#4ade80", linewidth=1.0, linestyle="--", alpha=0.6, label="High-Water Mark")

    # Fill starting capital baseline
    ax_main.axhline(metrics["starting_capital"], color="#64748b", linestyle=":", linewidth=1.0, alpha=0.7)

    # Shaded drawdown area on main chart
    ax_main.fill_between(dates, equity, hwm, color="#ef4444", alpha=0.15, label="Drawdown Region")

    # Titles and formatting
    ax_main.set_title(title, fontsize=16, fontweight="bold", color="#f8fafc", pad=16)
    ax_main.text(
        0.01,
        0.94,
        subtitle,
        transform=ax_main.transAxes,
        fontsize=10,
        color="#94a3b8",
        verticalalignment="top",
    )

    ax_main.set_ylabel("Account Equity (USD)", fontsize=11, color="#cbd5e1", labelpad=10)
    ax_main.yaxis.set_major_formatter("${x:,.0f}")
    ax_main.grid(True, linestyle="--", alpha=0.2, color="#475569")
    ax_main.legend(loc="upper left", framealpha=0.4, facecolor="#1e293b", edgecolor="#475569", fontsize=9)

    # Drawdown chart
    ax_dd.fill_between(dates, -drawdown, 0, color="#f87171", alpha=0.5)
    ax_dd.plot(dates, -drawdown, color="#ef4444", linewidth=1.2)
    ax_dd.set_ylabel("Drawdown (USD)", fontsize=10, color="#cbd5e1", labelpad=10)
    ax_dd.yaxis.set_major_formatter("${x:,.0f}")
    ax_dd.grid(True, linestyle="--", alpha=0.2, color="#475569")

    # Annual vertical boundary lines
    years = sorted(list(set(d.year for d in dates)))
    for y in years[1:]:
        first_d = datetime(y, 1, 1)
        ax_main.axvline(first_d, color="#38bdf8", linestyle=":", alpha=0.4, linewidth=1.0)
        ax_dd.axvline(first_d, color="#38bdf8", linestyle=":", alpha=0.4, linewidth=1.0)
        ax_main.text(
            first_d,
            ax_main.get_ylim()[0] + (ax_main.get_ylim()[1] - ax_main.get_ylim()[0]) * 0.05,
            f" {y}",
            color="#38bdf8",
            fontsize=9,
            alpha=0.7,
        )

    # Date formatting
    ax_dd.xaxis.set_major_locator(mdates.MonthLocator(interval=3))
    ax_dd.xaxis.set_major_formatter(mdates.DateFormatter("%b %Y"))
    plt.xticks(rotation=0)

    # Summary Stats Table Box
    annual_str = " | ".join(f"{yr}: ${pnl:+,.0f}" for yr, pnl in sorted(metrics["annual_pnl"].items()))
    stats_text = (
        f"Initial Capital: ${metrics['starting_capital']:,.0f}\n"
        f"Final Equity:   ${metrics['ending_equity']:,.2f} ({metrics['total_return_pct']:+.1f}%)\n"
        f"Total P&L:      ${metrics['total_net_pnl']:+,.2f}\n"
        f"Max Drawdown:   ${metrics['max_dd_dollars']:,.2f} ({metrics['max_dd_pct']:.2f}%)\n"
        f"Profit Factor:  {metrics['profit_factor']:.2f}\n"
        f"Win Rate:       {metrics['win_rate']:.1f}% ({metrics['wins']}W / {metrics['losses']}L)\n"
        f"Total Trades:   {metrics['total_trades']}\n"
        f"Annual P&L:     {annual_str}"
    )

    ax_main.text(
        0.985,
        0.05,
        stats_text,
        transform=ax_main.transAxes,
        fontsize=9,
        fontfamily="monospace",
        color="#e2e8f0",
        verticalalignment="bottom",
        horizontalalignment="right",
        bbox=dict(boxstyle="round,pad=0.6", facecolor="#0f172a", edgecolor="#334155", alpha=0.9),
    )

    plt.tight_layout()
    os.makedirs(os.path.dirname(output_png), exist_ok=True)
    plt.savefig(output_png, dpi=300, facecolor=fig.get_facecolor(), edgecolor="none")
    plt.close()
    print(f"[+] Saved Equity Curve: {output_png}")


def main():
    parser = argparse.ArgumentParser(description="NQ Precision Bot Equity Curve Generator")
    parser.add_argument("--nt8-csv", help="Path to NT8 trades CSV")
    parser.add_argument("--mt5-csv", help="Path to MT5 trades CSV")
    args = parser.parse_args()

    default_nt8_path = r"c:\Users\Administrator\Documents\NT8 Trades\NQPrecisionBot_315_Completed_Trade_Parity.csv"
    val_dir = r"c:\Users\Administrator\Documents\NinjaTrader 8\bin\Custom\Strategies\4. Index Book\5. NQPrecisionBot_NT\validation"

    # 1. Generate NT8 Equity Curve
    nt8_file = args.nt8_csv or default_nt8_path
    if os.path.exists(nt8_file):
        print(f"[*] Processing NT8 trades from {nt8_file}...")
        nt8_trades = parse_nt8_trades(nt8_file, commission_per_contract=5.76)
        nt8_metrics = compute_metrics(nt8_trades, starting_capital=25000.0)
        out_nt8 = os.path.join(val_dir, "equity_curve_NT8.png")
        plot_equity_curve(
            nt8_metrics,
            title="NQ Precision Bot — NinjaTrader 8 Equity Curve",
            subtitle="Config: 1 NQ Contract | $25,000 Starting Account | $5.76 Round-Trip Tradeify Commission | 2023 - 2026",
            output_png=out_nt8,
            accent_color="#38bdf8",
        )

    # 2. Generate MT5 Equity Curve
    mt5_file = args.mt5_csv
    if not mt5_file:
        # Search for latest NQPrecision_test_*.trades.csv in Common/Files
        pattern = r"C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\Common\Files\NQPrecision\logs\*.trades.csv"
        found = sorted(glob.glob(pattern), key=os.path.getmtime, reverse=True)
        if found:
            mt5_file = found[0]

    if mt5_file and os.path.exists(mt5_file):
        print(f"[*] Processing MT5 trades from {mt5_file}...")
        mt5_trades = parse_mt5_trades(mt5_file)
        mt5_metrics = compute_metrics(mt5_trades, starting_capital=25000.0)
        out_mt5 = os.path.join(val_dir, "equity_curve_MT5.png")
        plot_equity_curve(
            mt5_metrics,
            title="NQ Precision Bot — MetaTrader 5 (USTEC) Equity Curve",
            subtitle="Config: Fixed $100 Risk (Cost-Inclusive) | $25,000 Starting Account | ICMarkets USTEC | 2023 - 2026",
            output_png=out_mt5,
            accent_color="#a855f7",
        )
    else:
        print("[!] No MT5 trades file available yet to plot.")


if __name__ == "__main__":
    main()
