#!/usr/bin/env python3
"""Decode NQ daily Last NCD files and build an unadjusted continuous M1 series.

The roll-selection and 18:00 ET boundary logic match the audited 2021+ build.
"""
from pathlib import Path
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
import argparse
import csv
import gzip
import json
import os
import re

import numpy as np
import pandas as pd

from ncd_minute import decode_minute


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input-root", type=Path, required=True,
        help="Folder containing quarterly contract folders (for example 'NQ 03-21').",
    )
    parser.add_argument(
        "--output-dir", type=Path, required=True,
        help="Directory for the continuous gzip CSV, quality CSV and audit JSON.",
    )
    parser.add_argument(
        "--timezone", default="America/New_York",
        help="Timezone assumed by the NCD timestamps (default: America/New_York).",
    )
    parser.add_argument(
        "--start-contract", default="NQ 03-21",
        help="First quarterly contract to include (default: NQ 03-21).",
    )
    parser.add_argument(
        "--end-contract", default="NQ 12-26",
        help="Last quarterly contract to include (default: NQ 12-26).",
    )
    parser.add_argument(
        "--label", default="2021plus",
        help="Filename suffix for this build (default: 2021plus).",
    )
    parser.add_argument(
        "--workers", type=int, default=min(8, os.cpu_count() or 1),
        help="Parallel decode workers (default: up to 8).",
    )
    return parser.parse_args()


def decode_one(arg):
    contract, filename, timezone_name = arg
    decoded = decode_minute(filename, timezone_name)
    diffs = np.diff(decoded["utc_us"])
    gap_minutes = diffs[diffs > 60_000_000] / 60_000_000
    summary = {
        "contract": contract,
        "date": Path(filename).name[:8],
        "rows": int(decoded["rows"]),
        "first_utc_us": int(decoded["utc_us"][0]) if decoded["rows"] else None,
        "last_utc_us": int(decoded["utc_us"][-1]) if decoded["rows"] else None,
        "volume": int(decoded["volume"].sum()),
        "duplicate_or_nonmonotonic": int((diffs <= 0).sum()),
        "gaps_over_1m": int(len(gap_minutes)),
        "missing_minutes_from_gaps": int(np.maximum(gap_minutes - 1, 0).sum()) if len(gap_minutes) else 0,
        "max_gap_minutes": float(gap_minutes.max()) if len(gap_minutes) else 0.0,
        "tick_size": float(decoded["tick_size"]),
    }
    return contract, Path(filename).name[:8], decoded, summary


def calendar_roll_date(contract):
    match = re.fullmatch(r"NQ (\d{2})-(\d{2})", contract)
    if not match:
        raise ValueError(f"Unexpected NQ contract folder name: {contract}")
    month = int(match.group(1))
    year = 2000 + int(match.group(2))
    third_friday = date(year, month, 15)
    return third_friday + timedelta(days=(4 - third_friday.weekday()) % 7 - 8)


def main():
    args = parse_args()
    root = args.input_root.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    if not root.is_dir():
        raise SystemExit(f"Input directory does not exist: {root}")
    if args.workers < 1:
        raise SystemExit("--workers must be at least 1")
    try:
        exchange_tz = ZoneInfo(args.timezone)
    except Exception as exc:
        raise SystemExit(f"Invalid timezone {args.timezone!r}: {exc}")

    start_roll_date = calendar_roll_date(args.start_contract)
    end_roll_date = calendar_roll_date(args.end_contract)
    if start_roll_date > end_roll_date:
        raise SystemExit("--start-contract must not be later than --end-contract")
    jobs = []
    for contract_dir in sorted(root.glob("NQ *"), key=lambda path: calendar_roll_date(path.name)):
        if not contract_dir.is_dir():
            continue
        contract_date = calendar_roll_date(contract_dir.name)
        if not start_roll_date <= contract_date <= end_roll_date:
            continue
        for filename in sorted(contract_dir.glob("*.Last.ncd")):
            jobs.append((contract_dir.name, str(filename), args.timezone))
    if not jobs:
        raise SystemExit(f"No *.Last.ncd files found under {root}/NQ */")

    output_dir.mkdir(parents=True, exist_ok=True)
    workers = min(args.workers, os.cpu_count() or 1)
    print(f"Decoding {len(jobs)} NQ Last files with {workers} workers...", flush=True)
    decoded_files = {}
    quality = []
    volume_by_contract = defaultdict(dict)
    with ProcessPoolExecutor(max_workers=workers) as executor:
        for contract, day_text, decoded, summary in executor.map(decode_one, jobs, chunksize=8):
            decoded_files[(contract, day_text)] = decoded
            quality.append(summary)
            volume_by_contract[contract][date.fromisoformat(day_text)] = summary["volume"]

    contracts = sorted(volume_by_contract, key=calendar_roll_date)
    rolls = []
    start_date = None
    for index, contract in enumerate(contracts):
        calendar_date = calendar_roll_date(contract)
        current_volumes = volume_by_contract.get(contract, {})
        next_volumes = volume_by_contract.get(contracts[index + 1], {}) if index + 1 < len(contracts) else {}
        roll_date = calendar_date
        if current_volumes and next_volumes:
            last_current_day = max(current_volumes)
            roll_date = None
            for day in sorted(set(current_volumes) | set(next_volumes)):
                if start_date and day < start_date:
                    continue
                if day not in next_volumes:
                    continue
                if (day in current_volumes and next_volumes[day] > current_volumes[day]) or (
                    day not in current_volumes and day > last_current_day
                ):
                    roll_date = day
                    break
            if roll_date is None:
                roll_date = max(max(current_volumes), max(next_volumes)) + timedelta(days=1)
        rolls.append({
            "contract": contract,
            "calendar_roll_date": calendar_date.isoformat(),
            "roll_date": roll_date.isoformat() if index + 1 < len(contracts) else None,
            "last_data_day": max(current_volumes).isoformat() if current_volumes else None,
            "next_contract": contracts[index + 1] if index + 1 < len(contracts) else None,
        })
        start_date = roll_date

    continuous_path = output_dir / f"NQ_1min_Last_continuous_{args.label}.csv.gz"
    rows_written = 0
    volume_written = 0
    first_timestamp = None
    last_timestamp = None
    selected_contracts = []
    with gzip.open(continuous_path, "wt", newline="", encoding="utf-8", compresslevel=6) as output:
        writer = csv.writer(output)
        writer.writerow(["utc_us", "open", "high", "low", "close", "volume", "contract"])
        for index, contract in enumerate(contracts):
            lower_day = date.fromisoformat(rolls[index - 1]["roll_date"]) if index > 0 else None
            upper_day = date.fromisoformat(rolls[index]["roll_date"]) if index + 1 < len(contracts) else None
            lower_bound = -2**63 if lower_day is None else int(
                datetime.combine(lower_day - timedelta(days=1), time(18), tzinfo=exchange_tz).timestamp() * 1_000_000
            )
            upper_bound = 2**63 - 1 if upper_day is None else int(
                datetime.combine(upper_day - timedelta(days=1), time(18), tzinfo=exchange_tz).timestamp() * 1_000_000
            )
            for day in sorted(volume_by_contract[contract]):
                decoded = decoded_files[(contract, day.strftime("%Y%m%d"))]
                indices = np.flatnonzero((decoded["utc_us"] >= lower_bound) & (decoded["utc_us"] < upper_bound))
                if not len(indices):
                    continue
                if contract not in selected_contracts:
                    selected_contracts.append(contract)
                writer.writerows(zip(
                    decoded["utc_us"][indices].tolist(),
                    decoded["open"][indices].tolist(),
                    decoded["high"][indices].tolist(),
                    decoded["low"][indices].tolist(),
                    decoded["close"][indices].tolist(),
                    decoded["volume"][indices].tolist(),
                    [contract] * len(indices),
                ))
                rows_written += len(indices)
                volume_written += int(decoded["volume"][indices].sum())
                first_value = int(decoded["utc_us"][indices[0]])
                last_value = int(decoded["utc_us"][indices[-1]])
                first_timestamp = first_value if first_timestamp is None else min(first_timestamp, first_value)
                last_timestamp = last_value if last_timestamp is None else max(last_timestamp, last_value)

    quality_frame = pd.DataFrame(quality).sort_values(["contract", "date"])
    quality_path = output_dir / f"NQ_1min_file_quality_{args.label}.csv"
    quality_frame.to_csv(quality_path, index=False)
    audit = {
        "dataset_id": f"NQ_M1_LAST_CONTINUOUS_{args.label.upper().replace('-', '_')}_V1",
        "source_archive": "NQminute.7z",
        "contract_scope": {"start": args.start_contract, "end": args.end_contract},
        "timezone_assumption": args.timezone,
        "raw_data_is_unadjusted_contract_files": True,
        "roll_method": f"first day next contract Last volume exceeds current contract; roll boundary 18:00 {args.timezone}",
        "contracts_found": len(contracts),
        "contracts_used": selected_contracts,
        "last_files_decoded": len(quality),
        "decode_errors": 0,
        "last_rows_before_roll": int(quality_frame.rows.sum()),
        "last_volume_before_roll": int(quality_frame.volume.sum()),
        "continuous_rows": rows_written,
        "continuous_volume": volume_written,
        "continuous_first_utc": datetime.fromtimestamp(first_timestamp / 1e6, timezone.utc).isoformat() if first_timestamp else None,
        "continuous_last_utc": datetime.fromtimestamp(last_timestamp / 1e6, timezone.utc).isoformat() if last_timestamp else None,
        "last_daily_file_rows_min": int(quality_frame.rows.min()),
        "last_daily_file_rows_median": float(quality_frame.rows.median()),
        "last_daily_file_rows_max": int(quality_frame.rows.max()),
        "last_files_with_gaps": int((quality_frame.gaps_over_1m > 0).sum()),
        "last_total_gaps_over_1m": int(quality_frame.gaps_over_1m.sum()),
        "last_missing_minutes_from_gaps": int(quality_frame.missing_minutes_from_gaps.sum()),
        "last_max_gap_minutes": float(quality_frame.max_gap_minutes.max()),
        "last_duplicate_or_nonmonotonic_rows": int(quality_frame.duplicate_or_nonmonotonic.sum()),
        "rolls": rolls,
    }
    audit_path = output_dir / f"NQ_1min_data_audit_{args.label}.json"
    audit_path.write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in audit.items() if key != "rolls"}, indent=2))
    print(f"\nWrote: {continuous_path}")
    print(f"Wrote: {quality_path}")
    print(f"Wrote: {audit_path}")


if __name__ == "__main__":
    main()
