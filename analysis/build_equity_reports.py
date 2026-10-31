#!/usr/bin/env python3
"""Build reproducible, platform-separated equity-curve research from repository exports.

NT8: Strategy Analyzer closed-trade CSV. Exported Profit is already net of
Commission; never subtract Commission a second time.

MT5: Strategy Tester XLSX Deals table. Deal cash flow is Profit + Commission
+ Swap. Entry and exit commissions remain on their own deal timestamps.

Curves start at USD 0 and show cumulative exported net PnL at original sizing.
They are not capital-normalized or prop-firm-rule simulations.
"""
from __future__ import annotations
import json, math, re
from datetime import date, datetime
from pathlib import Path
from typing import Any

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[1]
NT8_FILES = {
    "Gold ORB (RBE)": "NinjaTrader RBE Trades.csv",
    "Vault Break": "NinjaTrader VaultBreak Trades.csv",
    "VWAP Pullback": "NinjaTrader VWAPPullback Trades.csv",
    "Overnight Bias ORB": "NinjaTrader OvernightBiasRB Trades.csv",
    "Open Drive": "NinjaTrader OpenDrive Trades.csv",
    "NQ Precision Bot": "NinjaTrader NQPrecisionBot Trades.csv",
    "Opening-Shock Continuation": "NinjaTrader OpeningShockCont Trades.csv",
    "Sigma ORB": "NinjaTrader SigmaORB Trades.csv",
    "Flash ORB": "NinjaTrader FlashORB Trades.csv",
}
MT5_FILES = {
    "Gold X9": None,
    "Gold ORB (RBE)": None,
    "Tokyo Coil": "MT5 TokyoCoil Trades.xlsx",
    "Vault Break": "MT5 VaultBreak Trades.xlsx",
    "Overnight Bias ORB": "MT5 OvernightBiasRB Trades.xlsx",
    "Open Drive": "MT5 OpenDrive Trades.xlsx",
    "NQ Precision Bot": "MT5 NQPrecisionBot Trades.xlsx",
    "Opening-Shock Continuation": "MT5 OpeningShockContinuation Trades.xlsx",
    "Sigma ORB": "MT5 SigmaORB Trades.xlsx",
    "Flash ORB": "MT5 FlashORB Trades.xlsx",
    "Noise Band Momentum": "MT5 NoiseBandMomentum Trades.xlsx",
}
EXCLUDED_MT5_TYPES = {"balance", "credit", "charge", "correction", "bonus", "dividend", "tax", "interest"}

def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")

def money(value: Any) -> float:
    if value is None: return 0.0
    if isinstance(value, (int, float, np.number)): return float(value)
    s = str(value).strip()
    if not s or s in {"-", "—", "–", "n/a", "N/A"}: return 0.0
    neg = s.startswith("(") and s.endswith(")")
    s = s.replace("$", "").replace("€", "").replace("£", "").replace(",", "")
    s = s.replace("(", "").replace(")", "").strip()
    try:
        v = float(s)
        return -abs(v) if neg else v
    except ValueError:
        return 0.0

def number(value: Any, default: float = 0.0) -> float:
    try: return float(str(value).replace(",", "")) if value is not None and str(value).strip() else default
    except (ValueError, TypeError): return default

def parse_datetime(value: Any) -> pd.Timestamp | None:
    if value is None or str(value).strip() == "": return None
    if isinstance(value, (datetime, date, pd.Timestamp)):
        ts = pd.Timestamp(value)
        return None if pd.isna(ts) else ts
    s = str(value).strip()
    if re.match(r"^\d{4}\.\d{2}\.\d{2}", s): s = s.replace(".", "-", 2)
    ts = pd.to_datetime(s, errors="coerce")
    return None if pd.isna(ts) else pd.Timestamp(ts)

def base_event(**kwargs: Any) -> dict[str, Any]:
    row = {
        "timestamp": None, "entry_timestamp": None, "strategy": "", "platform": "",
        "instrument": "", "side": "", "quantity": 0.0, "net_pnl": 0.0,
        "gross_pnl": 0.0, "commission": 0.0, "swap": 0.0, "cost_adjustment": 0.0, "event_type": "",
        "is_closed_trade": False, "source_file": "", "deal_id": "",
        "exit_reason": "", "mae": np.nan, "mfe": np.nan,
    }
    row.update(kwargs)
    return row

def parse_nt8(path: Path, strategy: str) -> tuple[pd.DataFrame, dict[str, Any]]:
    df = pd.read_csv(path, dtype=str, keep_default_na=False, encoding="utf-8-sig")
    df.columns = [str(c).strip() for c in df.columns]
    required = {"Entry time", "Exit time", "Profit", "Qty"}
    missing = sorted(required - set(df.columns))
    if missing: raise ValueError(f"NT8 CSV missing required columns: {missing}")
    events, invalid_exit = [], 0
    for _, r in df.iterrows():
        entry, exit_ = parse_datetime(r.get("Entry time")), parse_datetime(r.get("Exit time"))
        if exit_ is None:
            invalid_exit += 1
            continue
        net, comm = money(r.get("Profit")), money(r.get("Commission"))
        events.append(base_event(
            timestamp=exit_, entry_timestamp=entry, strategy=strategy, platform="NT8",
            instrument=str(r.get("Instrument", "")).strip(),
            side=str(r.get("Market pos.", r.get("Market pos", ""))).strip(),
            quantity=number(r.get("Qty"), 1.0), net_pnl=net,
            gross_pnl=net + comm, commission=-abs(comm),
            event_type="closed_trade", is_closed_trade=True,
            source_file=path.name, deal_id=str(r.get("Trade number", "")),
            exit_reason=str(r.get("Exit name", "")),
            mae=money(r.get("MAE")), mfe=money(r.get("MFE")),
        ))
    out = pd.DataFrame(events)
    if out.empty: raise ValueError("No completed trades with valid Exit time.")
    cum_check = None
    if "Cum. net profit" in df.columns:
        expected, actual = money(df.iloc[-1]["Cum. net profit"]), float(out["net_pnl"].sum())
        cum_check = {"export_cumulative_last": expected, "sum_profit_column": actual,
                     "difference": actual - expected, "matches_within_5c": abs(actual - expected) <= 0.05}
    info = {
        "parser": "NT8 Strategy Analyzer CSV", "source_rows": int(len(df)),
        "parsed_events": int(len(out)), "invalid_or_missing_exit_time_rows": invalid_exit,
        "first_event": out["timestamp"].min().isoformat(), "last_event": out["timestamp"].max().isoformat(),
        "profit_semantics": "Profit is already net of Commission; commission is not deducted again.",
        "cumulative_net_profit_check": cum_check,
        "instruments": sorted(out["instrument"].dropna().astype(str).unique().tolist()),
        "timezone": "As exported by NinjaTrader; no timezone conversion applied.",
    }
    return out, info

def norm_header(value: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "_", str(value or "").strip().lower()).strip("_")

def extract_mt5_settings(wb) -> dict[str, Any]:
    """Read report metadata from the first sheet only; do not confuse table headers with settings."""
    settings: dict[str, Any] = {}
    if not wb.worksheets:
        return settings
    ws = wb.worksheets[0]
    labels = {
        "period": "report_period", "symbol": "report_symbol", "currency": "report_currency",
        "initial_deposit": "initial_deposit", "starting_balance": "starting_balance",
        "ending_equity": "ending_equity", "total_net_profit": "reported_total_net_profit",
        "profit_factor": "reported_profit_factor", "win_rate": "reported_win_rate",
        "total_trades": "reported_total_trades",
    }
    for ridx, row in enumerate(ws.iter_rows(values_only=True), start=1):
        if ridx > 50:
            break
        vals = list(row)
        for i, value in enumerate(vals):
            if value is None:
                continue
            raw = str(value).strip()
            # Some custom reports put all metadata in one title cell.
            for pattern, dest, parser in [
                (r"Symbol:\s*([^|]+)", "report_symbol", str),
                (r"Period:\s*([^|]+)", "report_period", str),
                (r"Deposit:\s*\$?([\d,]+(?:\.\d+)?)", "initial_deposit", money),
            ]:
                match = re.search(pattern, raw, flags=re.IGNORECASE)
                if match:
                    settings[dest] = parser(match.group(1).strip())
            key = norm_header(raw.rstrip(":"))
            if key in labels:
                next_value = next((vals[j] for j in range(i + 1, len(vals)) if vals[j] is not None and str(vals[j]).strip()), None)
                if next_value is not None:
                    dest = labels[key]
                    settings[dest] = (money(str(next_value).replace("%", "")) if dest == "reported_win_rate" else money(next_value)) if dest in {
                        "initial_deposit", "starting_balance", "ending_equity", "reported_total_net_profit",
                        "reported_profit_factor", "reported_win_rate", "reported_total_trades"
                    } else str(next_value).strip()
    return settings

def parse_mt5(path: Path, strategy: str) -> tuple[pd.DataFrame, dict[str, Any]]:
    wb = load_workbook(path, data_only=True, read_only=True)
    settings = extract_mt5_settings(wb)
    aliases = {
        "time": {"time", "date_time", "date"}, "deal": {"deal", "ticket"},
        "symbol": {"symbol", "instrument"}, "type": {"type"},
        "direction": {"direction", "entry_exit"}, "volume": {"volume", "lots", "size"},
        "price": {"price"}, "commission": {"commission", "commissions"},
        "swap": {"swap"}, "profit": {"profit", "pnl"}, "balance": {"balance"},
    }
    found = None
    for ws in wb.worksheets:
        for ridx, row in enumerate(ws.iter_rows(values_only=True), start=1):
            headers = [norm_header(v) for v in row]
            mapping = {}
            for key, opts in aliases.items():
                for idx, h in enumerate(headers):
                    if h in opts:
                        mapping[key] = idx
                        break
            if all(k in mapping for k in ("time", "deal", "type", "direction", "volume", "price", "profit")):
                found = (ws.title, ridx, mapping, ws)
                break
        if found:
            break

    # The NQ Precision Bot workbook uses a custom completed-trade ledger rather
    # than the standard MT5 Deals table. Its adjusted PnL is the final cost-aware
    # value; Broker Net is retained for reconciliation, not added to it.
    if not found:
        custom_aliases = {
            "entry_time": {"entry_time"}, "exit_time": {"exit_time"},
            "direction": {"direction", "side"}, "volume": {"volume", "lots"},
            "entry_price": {"entry_price"}, "exit_price": {"exit_price"},
            "broker_net": {"broker_net"}, "adjusted_net": {"adj_net_p_l", "adj_net_pnl", "adjusted_net", "adjusted_net_p_l"},
            "exit_reason": {"exit", "exit_reason"},
        }
        custom = None
        for ws in wb.worksheets:
            for ridx, row in enumerate(ws.iter_rows(values_only=True), start=1):
                headers = [norm_header(v) for v in row]
                mapping = {}
                for key, opts in custom_aliases.items():
                    for idx, h in enumerate(headers):
                        if h in opts:
                            mapping[key] = idx
                            break
                if all(k in mapping for k in ("entry_time", "exit_time", "direction", "volume",
                                               "entry_price", "exit_price", "broker_net", "adjusted_net")):
                    custom = (ws.title, ridx, mapping, ws)
                    break
            if custom:
                break
        if custom:
            sheet_name, header_row, col, ws = custom
            events, ignored = [], 0
            for row in ws.iter_rows(min_row=header_row + 1, values_only=True):
                entry = parse_datetime(row[col["entry_time"]] if col["entry_time"] < len(row) else None)
                exit_ = parse_datetime(row[col["exit_time"]] if col["exit_time"] < len(row) else None)
                if exit_ is None:
                    ignored += 1
                    continue
                broker_net = money(row[col["broker_net"]] if col["broker_net"] < len(row) else 0)
                adjusted_net = money(row[col["adjusted_net"]] if col["adjusted_net"] < len(row) else 0)
                direction = str(row[col["direction"]] if col["direction"] < len(row) else "").strip()
                exit_reason = str(row[col["exit_reason"]] if "exit_reason" in col and col["exit_reason"] < len(row) else "").strip()
                events.append(base_event(
                    timestamp=exit_, entry_timestamp=entry, strategy=strategy, platform="MT5",
                    instrument=str(settings.get("report_symbol", "USTEC")),
                    side=direction, quantity=number(row[col["volume"]] if col["volume"] < len(row) else 0),
                    net_pnl=adjusted_net, gross_pnl=broker_net,
                    commission=0.0, swap=0.0, cost_adjustment=adjusted_net - broker_net,
                    event_type="completed_trade", is_closed_trade=True,
                    source_file=path.name, deal_id=str(len(events) + 1), exit_reason=exit_reason,
                ))
            out = pd.DataFrame(events)
            wb.close()
            if out.empty:
                raise ValueError(f"Custom MT5 trade ledger found on {sheet_name} row {header_row}, but no trades parsed.")
            adjusted_sum = float(out["net_pnl"].sum())
            broker_sum = float(out["gross_pnl"].sum())
            reported = money(settings.get("reported_total_net_profit"))
            info = {
                "parser": "MT5 custom NQ Precision Bot XLSX completed-trade ledger",
                "sheet": sheet_name, "header_row_1_based": int(header_row),
                "parsed_trade_rows": int(len(out)), "ignored_rows_after_header": int(ignored),
                "first_event": out["timestamp"].min().isoformat(), "last_event": out["timestamp"].max().isoformat(),
                "profit_semantics": "Adj. Net P&L is used as final net PnL; Broker Net is retained for reconciliation.",
                "settings": settings,
                "broker_net_sum_usd": broker_sum, "adjusted_net_sum_usd": adjusted_sum,
                "modeled_cost_adjustment_sum_usd": adjusted_sum - broker_sum,
                "reported_total_net_profit_usd": reported,
                "adjusted_net_reconciliation": {
                    "difference": adjusted_sum - reported,
                    "matches_within_5c": abs(adjusted_sum - reported) <= 0.05,
                } if reported else None,
                "instruments": [str(settings.get("report_symbol", "USTEC"))],
                "timezone": "Broker/server timestamps as exported; no timezone conversion applied.",
            }
            return out, info
        wb.close()
        raise ValueError("Could not locate standard MT5 Deals table or custom NQ Precision Bot trade ledger.")

    sheet_name, header_row, col, ws = found
    events, ignored = [], 0
    for row in ws.iter_rows(min_row=header_row + 1, values_only=True):
        t = parse_datetime(row[col["time"]] if col["time"] < len(row) else None)
        deal = row[col["deal"]] if col["deal"] < len(row) else None
        typ = str(row[col["type"]] if col["type"] < len(row) else "").strip().lower()
        direction = str(row[col["direction"]] if col["direction"] < len(row) else "").strip().lower()
        symbol = str(row[col["symbol"]] if "symbol" in col and col["symbol"] < len(row) else settings.get("report_symbol", "")).strip()
        if t is None or deal is None or typ in EXCLUDED_MT5_TYPES:
            ignored += 1
            continue
        if typ not in {"buy", "sell", "buy limit", "sell limit", "buy stop", "sell stop"} and direction not in {"in", "out", "in/out", "out by", "out_by", "inout"}:
            ignored += 1
            continue
        vol = number(row[col["volume"]] if col["volume"] < len(row) else 0)
        gross = money(row[col["profit"]] if col["profit"] < len(row) else 0)
        comm = money(row[col["commission"]] if "commission" in col and col["commission"] < len(row) else 0)
        swap = money(row[col["swap"]] if "swap" in col and col["swap"] < len(row) else 0)
        bal = money(row[col["balance"]] if "balance" in col and col["balance"] < len(row) else 0)
        events.append(base_event(
            timestamp=t, strategy=strategy, platform="MT5", instrument=symbol,
            side=typ, quantity=vol, net_pnl=gross + comm + swap,
            gross_pnl=gross, commission=comm, swap=swap, cost_adjustment=0.0,
            event_type="deal_cashflow",
            is_closed_trade=("out" in direction or "inout" in direction or gross != 0),
            source_file=path.name, deal_id=str(deal), balance_after_deal=bal,
            direction=direction,
        ))
    wb.close()
    out = pd.DataFrame(events)
    if out.empty:
        raise ValueError(f"Deals header found on {sheet_name} row {header_row}, but no trade deals parsed.")
    balance_values = out["balance_after_deal"].replace(0, np.nan).dropna() if "balance_after_deal" in out else pd.Series(dtype=float)
    final_balance = float(balance_values.iloc[-1]) if len(balance_values) else None
    initial = money(settings.get("initial_deposit"))
    net_sum = float(out["net_pnl"].sum())
    balance_check = None
    if final_balance is not None and initial:
        delta = final_balance - initial
        balance_check = {"initial_deposit": initial, "final_balance": final_balance,
                         "balance_change": delta, "sum_deal_cashflows": net_sum,
                         "difference": net_sum - delta, "matches_within_5c": abs(net_sum - delta) <= 0.05}
    info = {
        "parser": "MetaTrader 5 Strategy Tester XLSX Deals table",
        "sheet": sheet_name, "header_row_1_based": int(header_row),
        "parsed_deal_events": int(len(out)), "ignored_rows_after_header": int(ignored),
        "first_event": out["timestamp"].min().isoformat(), "last_event": out["timestamp"].max().isoformat(),
        "profit_semantics": "Deal cash flow = Profit + Commission + Swap; entry/exit commissions remain on their deal timestamps.",
        "settings": settings, "balance_reconciliation": balance_check,
        "instruments": sorted(out["instrument"].dropna().astype(str).unique().tolist()),
        "timezone": "Broker/server timestamps as exported; no timezone conversion applied.",
    }
    return out, info

def daily_series(events: pd.DataFrame) -> pd.Series:
    if events.empty: return pd.Series(dtype=float)
    d = events.assign(date=pd.to_datetime(events["timestamp"]).dt.normalize()).groupby("date")["net_pnl"].sum()
    idx = pd.bdate_range(d.index.min(), d.index.max()).union(d.index).sort_values()
    return d.reindex(idx, fill_value=0.0).astype(float)

def curve_metrics(events: pd.DataFrame) -> dict[str, Any]:
    if events.empty: return {}
    daily = daily_series(events)
    eq = daily.cumsum()
    dd = eq.cummax() - eq
    pos, neg = daily[daily > 0].sum(), abs(daily[daily < 0].sum())
    pf = float(pos / neg) if neg > 0 else (float("inf") if pos > 0 else 0.0)
    sd = float(daily.std(ddof=1)) if len(daily) > 1 else 0.0
    sharpe = float(daily.mean() / sd * math.sqrt(252)) if sd > 0 else 0.0
    monthly, yearly = daily.resample("ME").sum(), daily.resample("YE").sum()
    active_months, active_years = monthly[monthly != 0], yearly[yearly != 0]
    net, maxdd = float(events["net_pnl"].sum()), float(dd.max()) if len(dd) else 0.0
    closed = events[events["is_closed_trade"] == True]
    return {
        "event_count": int(len(events)), "closed_trade_or_exit_deal_count": int(len(closed)),
        "active_days": int((daily != 0).sum()), "first_date": str(daily.index.min().date()),
        "last_date": str(daily.index.max().date()), "calendar_span_days": int((daily.index.max() - daily.index.min()).days + 1),
        "total_net_pnl_usd": net, "average_event_net_pnl_usd": float(events["net_pnl"].mean()),
        "gross_profit_column_sum_usd": float(events["gross_pnl"].sum()),
        "commission_cashflow_sum_usd": float(events["commission"].sum()),
        "swap_cashflow_sum_usd": float(events["swap"].sum()),
        "modeled_cost_adjustment_sum_usd": float(events["cost_adjustment"].sum()) if "cost_adjustment" in events else 0.0,
        "daily_profit_factor": pf, "daily_sharpe_252": sharpe, "max_drawdown_usd": maxdd,
        "net_profit_to_max_drawdown": float(net / maxdd) if maxdd > 0 else (float("inf") if net > 0 else 0.0),
        "positive_active_month_share": float((active_months > 0).mean()) if len(active_months) else 0.0,
        "positive_active_year_share": float((active_years > 0).mean()) if len(active_years) else 0.0,
        "positive_days_share": float((daily[daily != 0] > 0).mean()) if (daily != 0).any() else 0.0,
        "best_day_usd": float(daily.max()), "worst_day_usd": float(daily.min()),
        "daily_pnl_std_usd": sd, "daily_pnl": daily, "equity": eq, "drawdown": dd,
        "yearly_pnl": {str(k.year): float(v) for k, v in yearly.items()},
    }

def plot_curve(events: pd.DataFrame, title: str, output: Path, subtitle: str = "") -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    if events.empty:
        fig, ax = plt.subplots(figsize=(12, 5))
        ax.text(.5, .5, "No parsed trade data / no strategy passed screen", ha="center", va="center", fontsize=14)
        ax.set_axis_off()
        fig.savefig(output, dpi=160, bbox_inches="tight")
        plt.close(fig)
        return
    m, eq, dd = curve_metrics(events), None, None
    eq, dd = m["equity"], m["drawdown"]
    fig, (ax, axd) = plt.subplots(2, 1, figsize=(13, 7), sharex=True, gridspec_kw={"height_ratios": [3, 1]})
    fig.patch.set_facecolor("#f7f8fa")
    for a in (ax, axd):
        a.set_facecolor("#ffffff")
        a.grid(True, alpha=.22, linestyle="--")
        a.spines[["top", "right"]].set_visible(False)
    ax.plot(eq.index, eq.values, linewidth=2.0, color="#1769aa", label="Cumulative net PnL")
    ax.fill_between(eq.index, eq.values, 0, where=eq.values >= 0, color="#2e8b57", alpha=.12)
    ax.fill_between(eq.index, eq.values, 0, where=eq.values < 0, color="#c0392b", alpha=.12)
    ax.axhline(0, color="#555", linewidth=.8)
    ax.set_ylabel("Cumulative net PnL (USD)")
    ax.set_title(title, loc="left", fontsize=15, fontweight="bold", pad=12)
    text = (subtitle + "\n" if subtitle else "") + (
        f"Net USD {m['total_net_pnl_usd']:,.0f} | Max DD USD {m['max_drawdown_usd']:,.0f}"
        f" | Daily PF {m['daily_profit_factor']:.2f} | Daily Sharpe {m['daily_sharpe_252']:.2f}"
        f" | Active days {m['active_days']:,}"
    )
    ax.text(.01, .97, text, transform=ax.transAxes, va="top", fontsize=8.5, color="#374151")
    ax.legend(loc="best", frameon=False)
    axd.fill_between(dd.index, -dd.values, 0, color="#c0392b", alpha=.28)
    axd.plot(dd.index, -dd.values, color="#c0392b", linewidth=1)
    axd.set_ylabel("Drawdown\n(USD)")
    locator = mdates.AutoDateLocator(minticks=5, maxticks=10)
    axd.xaxis.set_major_locator(locator)
    axd.xaxis.set_major_formatter(mdates.ConciseDateFormatter(locator))
    fig.tight_layout()
    fig.savefig(output, dpi=170, bbox_inches="tight")
    plt.close(fig)

def plot_dashboard(strategy_events: dict[str, pd.DataFrame], title: str, output: Path) -> None:
    items = [(k, v) for k, v in strategy_events.items() if not v.empty]
    if not items: return
    ncols, nrows = 3, math.ceil(len(items) / 3)
    fig, axes = plt.subplots(nrows, ncols, figsize=(16, 4.2 * nrows), squeeze=False)
    fig.suptitle(title, fontsize=17, fontweight="bold", x=.04, ha="left")
    for ax in axes.flat: ax.set_visible(False)
    for ax, (name, ev) in zip(axes.flat, items):
        ax.set_visible(True)
        m, eq = curve_metrics(ev), curve_metrics(ev)["equity"]
        ax.plot(eq.index, eq.values, linewidth=1.5, color="#1769aa")
        ax.axhline(0, color="#666", linewidth=.7)
        ax.fill_between(eq.index, eq.values, 0, alpha=.08, color="#1769aa")
        ax.set_title(name, fontsize=10, fontweight="bold", loc="left")
        ax.set_ylabel("Net PnL (USD)", fontsize=8)
        ax.tick_params(axis="both", labelsize=7)
        ax.grid(True, alpha=.2, linestyle="--")
        ax.text(.02, .96, f"Net USD {m['total_net_pnl_usd']:,.0f} | DD USD {m['max_drawdown_usd']:,.0f}",
                transform=ax.transAxes, va="top", fontsize=7)
    fig.tight_layout(rect=[0, 0, 1, .96])
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=170, bbox_inches="tight")
    plt.close(fig)

def score_and_select(strategy_events: dict[str, pd.DataFrame], metrics_rows: list[dict[str, Any]]) -> tuple[list[str], pd.DataFrame, str]:
    if not metrics_rows: return [], pd.DataFrame(), "No parsed strategies."
    mdf = pd.DataFrame(metrics_rows).set_index("strategy")
    eligible = mdf[
        (mdf["total_net_pnl_usd"] > 0) & (mdf["daily_profit_factor"] > 1.0) &
        (mdf["active_days"] >= 30) & (mdf["positive_active_month_share"] >= 0.45) &
        (mdf["net_profit_to_max_drawdown"] > 0.50)
    ].copy()
    if eligible.empty:
        return [], pd.DataFrame(), (
            "No strategy passed the evidence screen (positive net PnL, daily PF > 1, at least 30 active days, "
            "at least 45% positive active months, and net-PnL/max-DD > 0.5). "
            "No deployment shortlist is recommended from these exports yet."
        )
    weights = {"daily_sharpe_252": .35, "daily_profit_factor": .25,
               "net_profit_to_max_drawdown": .20, "positive_active_month_share": .10, "active_days": .10}
    score = pd.Series(0.0, index=eligible.index)
    for col, weight in weights.items():
        values = eligible[col].replace([np.inf, -np.inf], np.nan)
        if values.notna().any(): score += values.rank(pct=True).fillna(0) * weight
    eligible["screen_score"] = score
    eligible = eligible.sort_values("screen_score", ascending=False)
    daily_map = {k: daily_series(v).rename(k) for k, v in strategy_events.items() if not v.empty}
    corr = pd.concat(daily_map.values(), axis=1).fillna(0.0).corr(min_periods=30) if daily_map else pd.DataFrame()
    selected = []
    for name in eligible.index.tolist():
        if len(selected) >= 4: break
        if selected:
            vals = [corr.loc[name, prior] if name in corr.index and prior in corr.columns else np.nan for prior in selected]
            if any(pd.isna(v) or abs(float(v)) > .80 for v in vals): continue
        selected.append(name)
    note = (
        "Screening is a transparent evidence filter, not parameter optimization. Eligible strategies must have "
        "positive net PnL, daily PF > 1.00, at least 30 active days, at least 45% positive active months, and "
        "net PnL/max drawdown > 0.50. Candidates are ranked by daily Sharpe, daily PF, net-PnL/max-DD, "
        "positive-month share and sample size. Up to four are retained, excluding candidates with absolute "
        "daily-PnL correlation above 0.80 to an already selected strategy. Correlation requires 30 overlapping "
        "business days. The shortlist is provisional and is not a sizing instruction."
    )
    return selected, eligible.reset_index(), note

def write_platform(platform: str, manifest: dict[str, str | None], input_dir: Path, output_dir: Path) -> dict[str, Any]:
    (output_dir / "charts" / "individual").mkdir(parents=True, exist_ok=True)
    (output_dir / "charts" / "portfolios").mkdir(parents=True, exist_ok=True)
    (output_dir / "reports").mkdir(parents=True, exist_ok=True)
    all_events, strategy_events, quality, manifest_rows, metric_rows = [], {}, [], [], []
    for strategy, filename in manifest.items():
        if filename is None:
            manifest_rows.append({"strategy": strategy, "status": "pending_export", "source_file": "", "note": "No trade export in repository."})
            quality.append({"strategy": strategy, "status": "pending_export", "notes": "No source export."})
            continue
        path = input_dir / filename
        if not path.exists():
            manifest_rows.append({"strategy": strategy, "status": "missing_file", "source_file": filename, "note": "Expected export file not found."})
            quality.append({"strategy": strategy, "status": "missing_file", "source_file": filename})
            continue
        try:
            events, info = parse_nt8(path, strategy) if platform == "NT8" else parse_mt5(path, strategy)
            events = events.sort_values("timestamp").reset_index(drop=True)
            strategy_events[strategy] = events
            all_events.append(events)
            m = curve_metrics(events)
            row = {k: v for k, v in m.items() if k not in {"daily_pnl", "equity", "drawdown", "yearly_pnl"}}
            row.update({"strategy": strategy, "source_file": filename, "platform": platform,
                        "instruments": "; ".join(info.get("instruments", [])), "parser": info.get("parser", "")})
            metric_rows.append(row)
            quality.append({"strategy": strategy, "status": "parsed", "source_file": filename, **info})
            manifest_rows.append({"strategy": strategy, "status": "parsed", "source_file": filename, "note": "Trade export parsed successfully."})
            subtitle = f"{platform} export | {info.get('first_event','')[:10]} to {info.get('last_event','')[:10]}"
            plot_curve(events, f"{platform} | {strategy}", output_dir / "charts" / "individual" / f"{slug(strategy)}.png", subtitle)
        except Exception as exc:
            strategy_events[strategy] = pd.DataFrame()
            quality.append({"strategy": strategy, "status": "parse_error", "source_file": filename, "error": str(exc)})
            manifest_rows.append({"strategy": strategy, "status": "parse_error", "source_file": filename, "note": str(exc)})
    plot_dashboard(strategy_events, f"{platform} | Individual strategy equity curves",
                   output_dir / "charts" / "individual" / "strategy_dashboard.png")
    combined = pd.concat(all_events, ignore_index=True).sort_values("timestamp") if all_events else pd.DataFrame()
    plot_curve(combined, f"{platform} | All exported strategies combined",
               output_dir / "charts" / "portfolios" / "all_strategies.png",
               "Original exported sizing; unscaled sum of strategy net PnL.")
    all_m = curve_metrics(combined) if not combined.empty else {}
    selected, eligible, selection_note = score_and_select(strategy_events, metric_rows)
    recommended = pd.concat([strategy_events[n] for n in selected], ignore_index=True).sort_values("timestamp") if selected else pd.DataFrame()
    plot_curve(recommended, f"{platform} | Evidence-screened strategy shortlist",
               output_dir / "charts" / "portfolios" / "recommended_strategies.png",
               "Original exported sizing; selected strategies only. Not a risk-normalized allocation.")
    rec_m = curve_metrics(recommended) if not recommended.empty else {}
    daily_map = {k: daily_series(v).rename(k) for k, v in strategy_events.items() if not v.empty}
    daily_df = pd.concat(daily_map.values(), axis=1).fillna(0.0) if daily_map else pd.DataFrame()
    if not daily_df.empty:
        names = list(daily_map)
        daily_df["ALL_STRATEGIES"] = daily_df[names].sum(axis=1)
        daily_df["RECOMMENDED"] = daily_df[selected].sum(axis=1) if selected else 0.0
        daily_df.index.name = "date"
        daily_df.to_csv(output_dir / "reports" / "daily_pnl.csv", date_format="%Y-%m-%d")
        daily_df[names].corr(min_periods=30).to_csv(output_dir / "reports" / "correlation_matrix.csv")
    else:
        pd.DataFrame().to_csv(output_dir / "reports" / "daily_pnl.csv")
        pd.DataFrame().to_csv(output_dir / "reports" / "correlation_matrix.csv")
    if metric_rows:
        pd.DataFrame(metric_rows).to_csv(output_dir / "reports" / "strategy_metrics.csv", index=False)
        annual = []
        for strategy, ev in strategy_events.items():
            if ev.empty: continue
            for yr, val in daily_series(ev).resample("YE").sum().items():
                annual.append({"strategy": strategy, "year": yr.year, "net_pnl_usd": float(val)})
        pd.DataFrame(annual).to_csv(output_dir / "reports" / "annual_pnl.csv", index=False)
    else:
        pd.DataFrame().to_csv(output_dir / "reports" / "strategy_metrics.csv", index=False)
        pd.DataFrame().to_csv(output_dir / "reports" / "annual_pnl.csv", index=False)
    if all_events:
        ledger = pd.concat(all_events, ignore_index=True)
        ledger["timestamp"] = pd.to_datetime(ledger["timestamp"]).dt.strftime("%Y-%m-%d %H:%M:%S")
        if "entry_timestamp" in ledger.columns:
            ledger["entry_timestamp"] = pd.to_datetime(ledger["entry_timestamp"], errors="coerce").dt.strftime("%Y-%m-%d %H:%M:%S")
        ledger.to_csv(output_dir / "reports" / "normalized_event_ledger.csv", index=False)
    pd.DataFrame(manifest_rows).to_csv(output_dir / "reports" / "strategy_manifest.csv", index=False)
    (output_dir / "reports" / "data_quality.json").write_text(json.dumps(quality, indent=2, default=str), encoding="utf-8")
    portfolio_rows = []
    for name, m in [("All exported strategies", all_m), ("Recommended shortlist", rec_m)]:
        if m: portfolio_rows.append({"portfolio": name, **{k: v for k, v in m.items() if k not in {"daily_pnl", "equity", "drawdown", "yearly_pnl"}}})
    pd.DataFrame(portfolio_rows).to_csv(output_dir / "reports" / "portfolio_metrics.csv", index=False)
    recommendation = [f"# {platform} strategy selection", "", selection_note, "", "## Selected strategies", ""]
    recommendation += [f"- **{n}** — included in the provisional portfolio." for n in selected] if selected else [
        "- None. No strategy passed the evidence screen; do not treat the all-strategy curve as a deployment recommendation."]
    recommendation += ["", "## Eligible candidates (ranked)", ""]
    if not eligible.empty:
        recommendation.append(eligible[["strategy", "screen_score", "total_net_pnl_usd", "daily_profit_factor",
            "daily_sharpe_252", "max_drawdown_usd", "net_profit_to_max_drawdown",
            "positive_active_month_share", "active_days"]].to_markdown(index=False))
    else: recommendation.append("No eligible candidates.")
    recommendation += [
        "", "## Interpretation limits", "",
        "- PnL is the exported amount at original strategy-test size. No contract/lot scaling was applied.",
        "- Curves start at USD 0 and show cumulative net PnL, not a capital-normalized account balance.",
        "- The all-strategy curve assumes every strategy can run simultaneously; it does not model margin, overlap, portfolio risk limits or prop-firm rules.",
        "- NT8 Profit already includes commission. MT5 deal cash flow uses Profit + Commission + Swap.",
        "- MT5 entry commissions can be recognized on entry-deal dates; NT8 reports completed-trade PnL at exit.",
        "- Export timestamps are not timezone-normalized. Do not treat cross-platform daily correlations as synchronized.",
        "- This is a research shortlist, not a guarantee or position-sizing recommendation.",
    ]
    (output_dir / "reports" / "recommendations.md").write_text("\n".join(recommendation) + "\n", encoding="utf-8")
    summary = {
        "platform": platform, "expected_strategies": len(manifest),
        "parsed_strategies": sum(1 for r in manifest_rows if r["status"] == "parsed"),
        "pending_or_missing": [r for r in manifest_rows if r["status"] != "parsed"],
        "selected_strategies": selected,
        "all_portfolio_metrics": {k: v for k, v in all_m.items() if k not in {"daily_pnl", "equity", "drawdown", "yearly_pnl"}},
        "recommended_portfolio_metrics": {k: v for k, v in rec_m.items() if k not in {"daily_pnl", "equity", "drawdown", "yearly_pnl"}},
    }
    (output_dir / "reports" / "summary.json").write_text(json.dumps(summary, indent=2, default=str), encoding="utf-8")
    return summary

def main() -> int:
    nt8 = write_platform("NT8", NT8_FILES, ROOT / "NT8 Trades", ROOT / "NT8")
    mt5 = write_platform("MT5", MT5_FILES, ROOT / "MT5 Trades", ROOT / "MT5")
    top = {"generated_utc": datetime.utcnow().isoformat(timespec="seconds") + "Z",
           "repository": "EricOsas/Portfolio-Research",
           "method": "Export-based cumulative net PnL; original exported sizing; no added costs.",
           "platforms": {"NT8": nt8, "MT5": mt5}}
    (ROOT / "reports").mkdir(exist_ok=True)
    (ROOT / "reports" / "run_summary.json").write_text(json.dumps(top, indent=2, default=str), encoding="utf-8")
    print(json.dumps({
        "NT8": {"parsed": nt8["parsed_strategies"], "expected": nt8["expected_strategies"], "selected": nt8["selected_strategies"]},
        "MT5": {"parsed": mt5["parsed_strategies"], "expected": mt5["expected_strategies"], "selected": mt5["selected_strategies"]},
    }, indent=2))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
