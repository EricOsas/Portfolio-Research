#!/usr/bin/env python3
"""Inspect MT5 workbook table schemas for reproducible trade-ledger parsing."""
from __future__ import annotations
import json
import re
from pathlib import Path
from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "MT5 Trades"
OUTPUT = ROOT / "reports" / "source_schemas" / "mt5_export_schemas.json"

def norm(value):
    return re.sub(r"[^a-z0-9]+", "_", str(value or "").strip().lower()).strip("_")

def clean(value):
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        try:
            return value.isoformat()
        except Exception:
            pass
    return value

def inspect(path):
    wb = load_workbook(path, data_only=True, read_only=True)
    result = {"file": path.name, "worksheets": []}
    required = {"time", "deal", "type", "direction", "volume", "price", "profit"}
    for ws in wb.worksheets:
        found = None
        sample = []
        for ridx, row in enumerate(ws.iter_rows(values_only=True), start=1):
            vals = list(row)
            headers = [norm(v) for v in vals]
            if required.issubset(set(headers)):
                found = {
                    "header_row_1_based": ridx,
                    "headers": [str(v) if v is not None else "" for v in vals],
                    "normalized_headers": headers,
                }
                break
        if found:
            for row in ws.iter_rows(min_row=found["header_row_1_based"] + 1, max_row=found["header_row_1_based"] + 4, values_only=True):
                sample.append([clean(v) for v in row])
            result["worksheets"].append({
                "sheet": ws.title,
                **found,
                "sample_rows": sample,
            })
    wb.close()
    return result

def main():
    files = sorted(INPUT.glob("*.xlsx"))
    output = {"file_count": len(files), "files": [inspect(p) for p in files]}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, default=str), encoding="utf-8")
    print(json.dumps({"inspected_files": len(files), "output": str(OUTPUT)}, indent=2))

if __name__ == "__main__":
    main()
