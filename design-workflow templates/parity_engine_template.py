#!/usr/bin/env python3
"""
NQ Precision Bot Parity Validation Engine
Cross-checks trading events, signals, and execution across:
1. Roboquant (RQ) - Canonical Baseline (315 trades)
2. NinjaTrader 8 (NT8) - C# Strategy Analyzer / Live Trades
3. MetaTrader 5 (MT5) - MQL5 Strategy Tester / Live Trades
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import sys
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple


@dataclass
class TradeEvent:
    platform: str
    date: str  # YYYY-MM-DD
    timestamp: str  # YYYY-MM-DD HH:MM:SS (ET)
    action: str  # BUY / SELL
    quantity: float
    entry_price: float
    exit_time: Optional[str] = None
    exit_price: Optional[float] = None
    stop_loss: Optional[float] = None
    take_profit: Optional[float] = None
    exit_reason: Optional[str] = None
    gross_pnl: Optional[float] = None
    net_pnl: Optional[float] = None
    commission: Optional[float] = None
    raw_ref: Optional[Dict[str, Any]] = None


@dataclass
class ParityDiscrepancy:
    date: str
    metric: str
    expected: Any
    actual: Any
    platform: str
    tolerance: Optional[float] = None
    reason: str = ""


class ParityEngine:
    def __init__(self, tick_size: float = 0.25):
        self.tick_size = tick_size
        self.half_tick = tick_size / 2.0

    @staticmethod
    def normalize_action(action_str: str) -> str:
        s = action_str.strip().upper()
        if "BUY" in s or "LONG" in s:
            return "BUY"
        if "SELL" in s or "SHORT" in s:
            return "SELL"
        return s

    @staticmethod
    def load_rq_trades(trades_txt_path: str) -> List[TradeEvent]:
        """Loads canonical trades from RoboQuant Trades.txt tab-delimited file."""
        events = []
        if not os.path.exists(trades_txt_path):
            print(f"[!] Warning: RQ file not found at {trades_txt_path}")
            return events

        with open(trades_txt_path, mode="r", encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split("\t")
                if len(parts) < 10 or not parts[0].isdigit():
                    continue

                trade_num = int(parts[0])
                direction = ParityEngine.normalize_action(parts[1])
                qty = float(parts[2])
                entry_time = parts[3].strip()
                date_str = entry_time.split(" ")[0]
                entry_px = float(parts[4])
                exit_time = parts[5].strip()
                exit_px = float(parts[6])
                sl = float(parts[7]) if parts[7] else None
                tp = float(parts[8]) if parts[8] else None
                gross = float(parts[9].replace("+", "").replace(",", "")) if parts[9] else 0.0
                comm = float(parts[10].replace(",", "")) if parts[10] else 0.0
                net = gross + comm

                events.append(
                    TradeEvent(
                        platform="Roboquant",
                        date=date_str,
                        timestamp=entry_time,
                        action=direction,
                        quantity=qty,
                        entry_price=entry_px,
                        exit_time=exit_time,
                        exit_price=exit_px,
                        stop_loss=sl,
                        take_profit=tp,
                        gross_pnl=gross,
                        commission=comm,
                        net_pnl=net,
                        raw_ref={"trade_num": trade_num},
                    )
                )
        return events

    @staticmethod
    def load_nt8_parity_csv(csv_path: str) -> List[TradeEvent]:
        """Loads pre-matched NT8 trades from NQPrecisionBot_315_Completed_Trade_Parity.csv."""
        events = []
        if not os.path.exists(csv_path):
            print(f"[!] Warning: NT8 parity file not found at {csv_path}")
            return events

        with open(csv_path, mode="r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                d = row.get("Date", "").strip()
                direction = ParityEngine.normalize_action(row.get("Direction", ""))
                entry_px = float(row.get("NT8 Entry Price", 0.0))
                exit_px = float(row.get("NT8 Exit Price", 0.0))
                entry_t = row.get("NT8 Entry Time", "").strip()
                exit_t = row.get("NT8 Exit Time", "").strip()
                exit_reason = row.get("NT8 Exit Reason", "").strip()
                net_pnl = float(row.get("NT8 Net", 0.0))
                qty = float(row.get("NT8 Qty", 1.0))

                events.append(
                    TradeEvent(
                        platform="NT8",
                        date=d,
                        timestamp=entry_t,
                        action=direction,
                        quantity=qty,
                        entry_price=entry_px,
                        exit_time=exit_t,
                        exit_price=exit_px,
                        exit_reason=exit_reason,
                        net_pnl=net_pnl,
                        raw_ref=row,
                    )
                )
        return events

    @staticmethod
    def load_nt8_strategy_analyzer_csv(csv_path: str) -> List[TradeEvent]:
        """Loads trades from standard NinjaTrader Strategy Analyzer export or NQPrecisionBot_trades.csv."""
        events = []
        if not os.path.exists(csv_path):
            print(f"[!] Warning: NT8 Strategy Analyzer file not found at {csv_path}")
            return events

        with open(csv_path, mode="r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                # Handle either native Strategy Analyzer format or custom CSV format
                if "Market pos." in row or "Market pos" in row:
                    # Native NT8 Strategy Analyzer format
                    pos = row.get("Market pos.", row.get("Market pos", ""))
                    action = ParityEngine.normalize_action(pos)
                    qty = float(row.get("Qty", 1.0))
                    entry_px = float(row.get("Entry price", "0").replace("$", "").replace(",", ""))
                    exit_px = float(row.get("Exit price", "0").replace("$", "").replace(",", ""))
                    entry_t = row.get("Entry time", "").strip()
                    exit_t = row.get("Exit time", "").strip()
                    exit_reason = row.get("Exit name", "").strip()
                    profit = float(row.get("Profit", "0").replace("$", "").replace(",", ""))
                    comm = float(row.get("Commission", "0").replace("$", "").replace(",", ""))
                    net = profit - comm

                    # Parse date from entry_t (e.g., "10/31/2025 9:59:55 AM")
                    date_str = ""
                    if entry_t:
                        try:
                            dt = datetime.strptime(entry_t.split()[0], "%m/%d/%Y")
                            date_str = dt.strftime("%Y-%m-%d")
                        except Exception:
                            date_str = entry_t.split()[0]

                    events.append(
                        TradeEvent(
                            platform="NT8",
                            date=date_str,
                            timestamp=entry_t,
                            action=action,
                            quantity=qty,
                            entry_price=entry_px,
                            exit_time=exit_t,
                            exit_price=exit_px,
                            exit_reason=exit_reason,
                            gross_pnl=profit,
                            commission=comm,
                            net_pnl=net,
                            raw_ref=row,
                        )
                    )
                elif "Date" in row and "EntryPrice" in row:
                    # Custom NQPrecisionBot_trades.csv format
                    d = row.get("Date", "").strip()
                    action = ParityEngine.normalize_action(row.get("Direction", ""))
                    entry_px = float(row.get("EntryPrice", 0.0))
                    exit_px = float(row.get("ExitPrice", 0.0))
                    entry_t = row.get("EntryTime", "").strip()
                    exit_t = row.get("ExitTime", "").strip()
                    qty = float(row.get("Quantity", 1.0))
                    gross = float(row.get("Gross", 0.0))
                    net = float(row.get("Net", 0.0))
                    comm = float(row.get("Commission", 0.0))
                    sl = float(row.get("Stop", 0.0)) if row.get("Stop") else None
                    tp = float(row.get("Target", 0.0)) if row.get("Target") else None

                    events.append(
                        TradeEvent(
                            platform="NT8",
                            date=d,
                            timestamp=entry_t,
                            action=action,
                            quantity=qty,
                            entry_price=entry_px,
                            exit_time=exit_t,
                            exit_price=exit_px,
                            stop_loss=sl,
                            take_profit=tp,
                            gross_pnl=gross,
                            commission=comm,
                            net_pnl=net,
                            raw_ref=row,
                        )
                    )
        return events

    @staticmethod
    def load_mt5_trades_csv(csv_path: str) -> List[TradeEvent]:
        """Loads trades from MT5 exported *.trades.csv or ReportTester.csv."""
        events = []
        if not os.path.exists(csv_path):
            print(f"[!] Warning: MT5 file not found at {csv_path}")
            return events

        with open(csv_path, mode="r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if "side" in row and "entry_price" in row:
                    # NQPrecision_test_*.trades.csv format
                    side = ParityEngine.normalize_action(row.get("side", ""))
                    qty = float(row.get("volume", 1.0))
                    entry_px = float(row.get("entry_price", 0.0))
                    exit_px = float(row.get("exit_price", 0.0))
                    entry_t = row.get("entry_server", "").strip()
                    exit_t = row.get("exit_server", "").strip()
                    sl = float(row.get("original_sl", 0.0)) if row.get("original_sl") else None
                    tp = float(row.get("original_tp", 0.0)) if row.get("original_tp") else None
                    net = float(row.get("adjusted_net", row.get("broker_net", 0.0)))
                    c_date = row.get("central_date", "").replace(".", "-").strip()
                    reason_code = row.get("exit_reason", "").strip()
                    exit_reason = "SL" if reason_code == "4" else "TP" if reason_code == "5" else "Time/Market"

                    events.append(
                        TradeEvent(
                            platform="MT5",
                            date=c_date,
                            timestamp=entry_t,
                            action=side,
                            quantity=qty,
                            entry_price=entry_px,
                            exit_time=exit_t,
                            exit_price=exit_px,
                            stop_loss=sl,
                            take_profit=tp,
                            exit_reason=exit_reason,
                            net_pnl=net,
                            raw_ref=row,
                        )
                    )
        return events

    def compare_event_streams(
        self,
        base_events: List[TradeEvent],
        target_events: List[TradeEvent],
        target_platform: str,
    ) -> Tuple[List[ParityDiscrepancy], Dict[str, Any]]:
        """Compares target platform trade stream against canonical base events."""
        discrepancies: List[ParityDiscrepancy] = []

        base_by_date = {e.date: e for e in base_events if e.date}
        target_by_date = {e.date: e for e in target_events if e.date}

        all_dates = sorted(set(base_by_date.keys()) | set(target_by_date.keys()))
        matched_count = 0
        skipped_count = 0
        direction_match_count = 0
        entry_deltas = []
        exit_deltas = []

        for d in all_dates:
            base_ev = base_by_date.get(d)
            target_ev = target_by_date.get(d)

            if base_ev and not target_ev:
                discrepancies.append(
                    ParityDiscrepancy(
                        date=d,
                        metric="execution_presence",
                        expected=f"{base_ev.action} {base_ev.quantity} contracts",
                        actual="NO_TRADE",
                        platform=target_platform,
                        reason=f"Canonical {base_ev.platform} traded on {d}, but {target_platform} did not.",
                    )
                )
                skipped_count += 1
                continue

            if target_ev and not base_ev:
                discrepancies.append(
                    ParityDiscrepancy(
                        date=d,
                        metric="execution_presence",
                        expected="NO_TRADE",
                        actual=f"{target_ev.action} {target_ev.quantity} contracts",
                        platform=target_platform,
                        reason=f"{target_platform} traded on {d}, but canonical baseline did not.",
                    )
                )
                skipped_count += 1
                continue

            matched_count += 1

            # 1. Action Parity
            if base_ev.action == target_ev.action:
                direction_match_count += 1
            else:
                discrepancies.append(
                    ParityDiscrepancy(
                        date=d,
                        metric="action_direction",
                        expected=base_ev.action,
                        actual=target_ev.action,
                        platform=target_platform,
                        reason=f"Direction mismatch on {d} (Expected {base_ev.action}, Got {target_ev.action}).",
                    )
                )

            # 2. Entry Price Delta
            entry_diff = abs(base_ev.entry_price - target_ev.entry_price)
            entry_deltas.append(entry_diff)
            # Roll dates can have large basis deltas (200+ pts), regular days are typically <= 5 pts
            if entry_diff > 10.0:
                discrepancies.append(
                    ParityDiscrepancy(
                        date=d,
                        metric="entry_price_basis_shift",
                        expected=base_ev.entry_price,
                        actual=target_ev.entry_price,
                        platform=target_platform,
                        tolerance=10.0,
                        reason=f"Large basis delta {entry_diff:.2f} pts on {d} (contract roll or feed basis shift).",
                    )
                )
            elif entry_diff > self.half_tick:
                discrepancies.append(
                    ParityDiscrepancy(
                        date=d,
                        metric="entry_price_fill_delta",
                        expected=base_ev.entry_price,
                        actual=target_ev.entry_price,
                        platform=target_platform,
                        tolerance=self.half_tick,
                        reason=f"Fill delta {entry_diff:.2f} pts exceeds half-tick tolerance {self.half_tick}.",
                    )
                )

            # 3. Exit Price Delta
            if base_ev.exit_price is not None and target_ev.exit_price is not None:
                exit_diff = abs(base_ev.exit_price - target_ev.exit_price)
                exit_deltas.append(exit_diff)

        dir_pct = (direction_match_count / matched_count * 100.0) if matched_count > 0 else 0.0
        avg_entry_delta = (sum(entry_deltas) / len(entry_deltas)) if entry_deltas else 0.0
        avg_exit_delta = (sum(exit_deltas) / len(exit_deltas)) if exit_deltas else 0.0

        summary = {
            "target_platform": target_platform,
            "total_canonical_trades": len(base_events),
            "total_target_trades": len(target_events),
            "matched_dates": matched_count,
            "direction_matches": direction_match_count,
            "direction_parity_pct": round(dir_pct, 2),
            "unmatched_dates": skipped_count,
            "avg_entry_delta_pts": round(avg_entry_delta, 2),
            "avg_exit_delta_pts": round(avg_exit_delta, 2),
            "total_discrepancies": len(discrepancies),
        }
        return discrepancies, summary


def main():
    parser = argparse.ArgumentParser(description="NQ Precision Bot Cross-Platform Parity Validator")
    parser.add_argument("--rq-file", help="Path to canonical Roboquant Trades.txt", required=False)
    parser.add_argument("--nt8-file", help="Path to NT8 trades CSV (parity CSV or Strategy Analyzer export)", required=False)
    parser.add_argument("--mt5-file", help="Path to MT5 trades CSV (*.trades.csv)", required=False)
    parser.add_argument("--out-csv", help="Path to write full multi-platform comparison CSV", required=False)
    args = parser.parse_args()

    # Default paths if not provided
    default_rq = r"c:\Users\Administrator\Documents\NinjaTrader 8\bin\Custom\Strategies\4. Index Book\5. NQPrecisionBot_NT\validation\RoboQuant\Trades.txt"
    default_nt8 = r"c:\Users\Administrator\Documents\NT8 Trades\NQPrecisionBot_315_Completed_Trade_Parity.csv"

    rq_path = args.rq_file or default_rq
    nt8_path = args.nt8_file or default_nt8
    mt5_path = args.mt5_file

    engine = ParityEngine()

    print("==================================================================")
    print("       NQ Precision Bot Cross-Platform Parity Audit Report        ")
    print("==================================================================")

    rq_events = engine.load_rq_trades(rq_path)
    print(f"[*] Loaded RoboQuant (Baseline) trades: {len(rq_events)}")

    # Audit NT8
    if nt8_path and os.path.exists(nt8_path):
        nt8_events = engine.load_nt8_parity_csv(nt8_path)
        if not nt8_events:
            nt8_events = engine.load_nt8_strategy_analyzer_csv(nt8_path)
        print(f"[*] Loaded NinjaTrader 8 trades: {len(nt8_events)}")
        discs_nt8, summary_nt8 = engine.compare_event_streams(rq_events, nt8_events, "NT8")
        print("\n--- NinjaTrader 8 Parity Summary ---")
        for k, v in summary_nt8.items():
            print(f"  {k}: {v}")
    else:
        print(f"[!] NT8 file not found: {nt8_path}")

    # Audit MT5
    if mt5_path and os.path.exists(mt5_path):
        mt5_events = engine.load_mt5_trades_csv(mt5_path)
        print(f"\n[*] Loaded MetaTrader 5 trades: {len(mt5_events)}")
        discs_mt5, summary_mt5 = engine.compare_event_streams(rq_events, mt5_events, "MT5")
        print("\n--- MetaTrader 5 Parity Summary ---")
        for k, v in summary_mt5.items():
            print(f"  {k}: {v}")
    elif mt5_path:
        print(f"[!] MT5 file not found: {mt5_path}")

    print("\n==================================================================")


if __name__ == "__main__":
    main()
