"""Build plug-and-play MT5 ``.set`` files per prop firm and per stage.

The research pipeline decides which sleeves form each stage's book and what
dollar risk the book carries. This script turns those decisions into MT5 preset
files, so a stage is loaded by attaching the EA to its chart and loading one
file. Sizing is written in whole lots, because the minimum-lot analysis showed
that percent/cash inputs do not survive the 0.01-lot floor.

Output (default: ``C:/Users/Administrator/Documents/Portfolio/Set-Files``)::

    <firm>/<stage>/NN. <EA>.set
    <firm>/<stage>/manifest.csv
    <firm>/README.md
    README.md

Tradeify is futures/NT8 and has no ``.set`` files; its folder documents the
contract settings instead.
"""
from __future__ import annotations

import csv
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze_the5ers_sizing as T5  # noqa: E402
import build_live_and_prop_reports as engine  # noqa: E402

DEFAULT_OUT = Path(r"C:/Users/Administrator/Documents/Portfolio/Set-Files")

# stage -> (book, target risk per book trade in USD)
THE5ERS = {
    "Phase-1": (["Gold X9", "GotobiFix EURJPY", "GotobiFix USDJPY", "Open Drive"], 50.0),
    "Phase-2": (["Gold X9", "GotobiFix EURJPY", "GotobiFix USDJPY", "Open Drive"], 50.0),
    "Phase-3": (["Gold X9", "GotobiFix EURJPY", "GotobiFix USDJPY", "Open Drive"], 50.0),
    "Funded": (["Flash ORB", "GotobiFix EURJPY", "Tokyo Coil", "Overnight Bias ORB"], 100.0),
}

# ea label -> (source folder, file stem, symbol hint)
SOURCE = {
    "Gold X9": ("1. X9", "Gold_X9"),
    "Gold ORB (RBE)": ("2. RBE", "RangeBreakout"),
    "Tokyo Coil": ("3. TokyoCoil", "TokyoCoil"),
    "Vault Break": ("4. VaultBreak", "VaultBreak"),
    "Overnight Bias ORB": ("5. OvernightBiasRangeBreakout", "OvernightBiasRangeBreakout"),
    "Open Drive": ("6. OpenDrive", "OpenDrive"),
    "NQ Precision": ("7. NQPrecision", "NQPrecisionBot"),
    "Opening-Shock": ("8. OpeningShockContinuation", "OpeningShock"),
    "Sigma ORB": ("9. SigmaBreakout", "SigmaBreakout"),
    "Flash ORB": ("10. FlashTriggerORB", "FlashTriggerORB"),
    "Noise Band Momentum": ("11. NoiseBandMomentum", "NoiseBandMomentum"),
    "FVG Duo": ("12. FVGDuo", "FVG_Duo"),
    "GotobiFix EURJPY": ("13. GotobiFix", "GotobiFix"),
    "GotobiFix USDJPY": ("13. GotobiFix", "GotobiFix"),
    "GotobiFix GBPJPY": ("13. GotobiFix", "GotobiFix"),
}

EA_TITLE = {
    "Gold X9": "Gold X9",
    "Gold ORB (RBE)": "Gold ORB RBE",
    "Tokyo Coil": "Tokyo Coil",
    "Vault Break": "Vault Break",
    "Overnight Bias ORB": "Overnight Bias ORB",
    "Open Drive": "Open Drive",
    "NQ Precision": "NQ Precision",
    "Opening-Shock": "Opening Shock",
    "Sigma ORB": "Sigma ORB",
    "Flash ORB": "Flash ORB",
    "Noise Band Momentum": "Noise Band Momentum",
    "FVG Duo": "FVG Duo",
    "GotobiFix EURJPY": "GotobiFix EURJPY",
    "GotobiFix USDJPY": "GotobiFix USDJPY",
    "GotobiFix GBPJPY": "GotobiFix GBPJPY",
}


def rows(ea, lots, risk_usd, magic, comment):
    """Return the input rows a given EA needs to reproduce the sized book."""
    common = {"EnableTrading": "true"}
    if ea.startswith("Gold X9"):
        return {
            "Lotsizing_Method": "0",          # Manual_Lotsize = fixed lots
            "FixedLots": f"{lots:.2f}",
            "RiskScaling": "1.0",
            "TieredLot": "30.0",
            "InpFixedBalance": "0.0",
            "InpMagic": str(magic),
            "TradeComment": comment,
        }
    if ea == "Gold ORB (RBE)":
        return {"Risk_Money": f"{risk_usd:.2f}", "Magic": str(magic)}
    if ea == "Tokyo Coil":
        return {**common, "RiskPct": "0.0", "RiskMoney": f"{risk_usd:.2f}", "MagicC1": str(magic),
                "UseNewsFlatten": "false"}
    if ea in ("Vault Break", "Overnight Bias ORB", "NQ Precision", "Sigma ORB",
              "Flash ORB", "Opening-Shock", "Open Drive"):
        out = {**common, "UseFixedSize": "true", "FixedLots": f"{lots:.2f}",
               "RiskMoney": f"{risk_usd:.2f}"}
        if ea == "Open Drive":
            out = {**common, "UseFixedLots": "true", "FixedLots": f"{lots:.2f}",
                   "RiskPercent": "0.0", "RiskMoney": "0.0", "DailyLossLimitPct": "0.0"}
        if ea == "Opening-Shock":
            out["EnforceFixedSizeRiskCap"] = "false"
        return out
    if ea == "Noise Band Momentum":
        return {"InpRiskPercent": "0.0", "InpAllowMinLotOverride": "true"}
    if ea == "FVG Duo":
        return {"InpSizingMode": "0", "InpFixedLots": f"{lots:.2f}",
                "InpCashRisk": f"{risk_usd:.2f}", "InpMagic": str(magic)}
    if ea.startswith("GotobiFix"):
        return {**common, "Lots": f"{lots:.2f}", "DisasterStopPips": "0.0",
                "MaxFloatingLossMoney": "0.0", "MaxEntrySpreadPips": "0.0"}
    raise KeyError(f"No set-file mapping for {ea}")


def write_set(path, header, payload):
    body = [f"; {line}" for line in header] + [""]
    body += [f"{k}={v}" for k, v in payload.items()]
    path.write_text("\n".join(body) + "\n", encoding="utf-8")


def alloc(trades, book, target):
    unit = {s: float(trades.loc[trades["strategy"] == s, "risk_unit"].iloc[0]) for s in book}
    per = target / len(book)
    lots = {s: max(0.01, math.floor(per / unit[s] * 100.0 + 1e-9) / 100.0) for s in book}
    return lots, {s: lots[s] * unit[s] for s in book}


def symbol_for(trades, strategy):
    t = trades[trades["strategy"] == strategy]
    if not len(t):
        return ""
    symbols = t["instrument"].dropna().astype(str)
    return symbols.mode().iloc[0] if len(symbols) else ""


def build_firm(out, firm, stages, trades, base_magic, firm_title, notes):
    phase_rows = []
    for phase_no, (stage, (book, target)) in enumerate(stages.items(), start=1):
        lots, risk = alloc(trades, book, target)
        folder = out / firm / stage
        folder.mkdir(parents=True, exist_ok=True)
        for stale in folder.glob("*.set"):
            stale.unlink()
        if (folder / "manifest.csv").exists():
            (folder / "manifest.csv").unlink()
        for i, (ea, lots_i) in enumerate(lots.items(), start=1):
            magic = base_magic + phase_no * 100 + i
            comment = f"{firm.split('-')[0]}-{stage}-{i}"
            src_folder, stem = SOURCE[ea]
            title = EA_TITLE[ea]
            fname = f"{i:02d}. {title}.set"
            payload = rows(ea, lots_i, risk[ea], magic, comment)
            write_set(folder / fname, [
                f"{firm_title} | {stage} | {title}",
                f"Target book risk USD {target:.0f}; this sleeve USD {risk[ea]:.2f} "
                f"({lots_i:.2f} lots, 0.01-lot 1R = USD {risk[ea] / lots_i:.2f})",
                "Generated by analysis/build_set_files.py from the validated book allocation.",
            ], payload)
            phase_rows.append({
                "stage": stage, "file": f"{stage}/{fname}", "ea": ea,
                "source": str(Path("Source Codes") / "MT5" / src_folder / stem),
                "symbol": symbol_for(trades, ea), "lots": f"{lots_i:.2f}",
                "risk_usd": f"{risk[ea]:.2f}", "magic": magic,
                "trade_comment": comment,
            })
        with (folder / "manifest.csv").open("w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=list(phase_rows[0]))
            w.writeheader()
            w.writerows([r for r in phase_rows if r["stage"] == stage])

    readme = [f"# {firm_title} — EA set files", "",
              "Load one file per chart. The `.set` files only override the sizing, magic and",
              "enable inputs; every other strategy input keeps its shipped default.", ""]
    for stage_index, (stage, (book, target)) in enumerate(stages.items(), start=1):
        lots, risk = alloc(trades, book, target)
        readme += [f"## {stage}", "",
                   f"Book target USD {target:.0f} per trade "
                   f"(actual USD {sum(risk.values()):.2f}, "
                   f"{sum(risk.values()) / target * 100:.0f}% of target).", "",
                   "| # | EA | Symbol | Lots | Risk USD | Magic |", "|---|---|---|---:|---:|---:|"]
        for i, (ea, lots_i) in enumerate(lots.items(), start=1):
            readme.append(f"| {i} | {EA_TITLE[ea]} | {symbol_for(trades, ea)} | {lots_i:.2f} | "
                          f"{risk[ea]:.2f} | {base_magic + stage_index * 100 + i} |")
        readme.append("")
    readme += notes
    (out / firm / "README.md").write_text("\n".join(readme) + "\n", encoding="utf-8")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    trades, _ = engine.load_platform_trades("MT5")
    trades = T5.calibrate(trades)
    unit = {s: float(trades.loc[trades["strategy"] == s, "risk_unit"].iloc[0]) for s in trades["strategy"].unique()}

    common_notes = [
        "## How to load a stage", "",
        "1. Open one chart per row in the table and attach that EA.",
        "2. `Right click > Load` the matching `.set` from this folder (or drag it onto the chart).",
        "3. Confirm the size shown in the EA panel before enabling trading.",
        "4. Keep the listed magic numbers: they separate stages in the report exports.",
        "",
        "Sizing is written as whole lots rather than percent or cash risk because the broker",
        "minimum (0.01 lot) is the binding constraint: on XAUUSD one 0.01 lot already risks",
        f"USD {0.01 * unit.get('Gold X9', 0):.2f} at the model's 1R. Any percent or cash input",
        "below that floor silently becomes 0.01 lot anyway.",
        "",
        "### Before going live", "",
        "- Check the broker's contract size and minimum volume for each symbol.",
        "- Confirm the chart timeframes each EA expects (see its `MODEL.md`).",
        "- Run one day on demo to compare the risk the EA reports against the table above.",
    ]

    build_firm(out, "The5ers-20K-Bootcamp", THE5ERS, trades, 760000,
               "The5ers $20,000 Bootcamp", common_notes + [
                   "", "### Stage notes", "",
                   "- Phase 1, 2 and 3 use the same four-sleeve book and the same lots; only the magic changes so the",
                   "  pass of each step is attributable.",
                   "- The funded stage drops Gold X9 and switches to Flash ORB + GotobiFix EURJPY + Tokyo Coil +",
                   "  Overnight Bias ORB. Keeping gold in the funded book is what produced the ~41% funded breach",
                   "  in the earlier model.",
               ])

    moneta_alloc = engine.PROP_ROOT / "Moneta-2Step-10K" / "reports" / "ea_allocation.json"
    if moneta_alloc.exists():
        a = json.loads(moneta_alloc.read_text(encoding="utf-8"))
        stages = {}
        labels = {"phase_1": "Phase-1", "phase_2": "Phase-2", "funded": "Funded"}
        for key, label in labels.items():
            s = a[key]
            stages[label] = ([k for k in s["sleeves"]], float(s["target_usd"]))
        build_firm(out, "Moneta-2Step-10K", stages, trades, 770000,
                   "Moneta Funded $10,000 2-Step Standard", common_notes + [
                       "", "### Stage notes", "",
                       "- Phase 1 (target 5%) and Phase 2 (target 10%) run the same book and the same lots; the",
                       "  binding constraint is Phase 2, which needs twice the R in the same 8% static budget.",
                       "- The funded stage drops gold. The 4% daily loss is a hard breach at Moneta, so the",
                       "  funded book is sized well below it.",
                       "- News: no new or held exposure from 5 minutes before to 5 minutes after high-impact",
                       "  releases, in evaluation and funded. The set files do not enable the EAs' news filters",
                       "  because some of them need a calendar CSV; flatten manually for those windows.",
                       "- Incidental opposing positions from independent EAs on the same account are allowed.",
                       "  Do not run opposing exposure deliberately across accounts.",
                   ])
    else:
        print("Moneta allocation missing; run analysis/analyze_moneta_sizing.py first")

    tradeify = out / "Tradeify-50K-Growth"
    tradeify.mkdir(parents=True, exist_ok=True)
    (tradeify / "README.md").write_text("""# Tradeify $50,000 Growth — strategy settings

Tradeify is a futures account, so these are NinjaTrader strategy parameters, not
MT5 `.set` files. NinjaTrader has no portable preset file; set the values below in
the strategy dialog and save a workspace.

| Stage | Sleeves | Contracts |
|---|---|---|
| Challenge | FVG Duo, Flash ORB, Gold ORB (RBE), Sigma ORB | 1 micro each (MNQ/MGC) |
| Funded | Flash ORB, Gold ORB (RBE), Opening-Shock, Sigma ORB | 1 micro each |
| Lower risk | Flash ORB + Overnight Bias ORB | 1 micro each |

Required parameter changes:

- `UseFixedContracts = true` and `FixedContracts = 1` on every sleeve.
- Keep `UseFixedContracts = true` on Flash, FVG Duo and Open Drive so a
  `RiskPercent` input cannot scale the book.
- Do not raise any sleeve above one micro: the four-mini cap does not bind, but
  the USD 2,000 trailing drawdown does, and above one micro the simulator's
  USD 1,250 daily-loss clip starts hiding losses.

One micro per sleeve is already about 1% of the $50k account. See
`Prop-Firms/Tradeify-50K-Growth-Futures/reports/stage_sizing.md` in the research
repository for the per-sleeve 1R values and pass/payout odds.
""", encoding="utf-8")

    (out / "README.md").write_text("""# Plug-and-play set files

Pre-configured MT5 preset files, one folder per stage, for each prop firm the
research models. Load the file that matches the stage you are trading; the rest
of each EA's inputs stay at their shipped defaults.

| Firm | Account | Stages | Files |
|---|---|---|---|
| [Moneta](Moneta-2Step-10K/README.md) | USD 10,000 2-Step Standard | Phase 1, Phase 2, Funded | MT5 `.set` |
| [The5ers](The5ers-20K-Bootcamp/README.md) | USD 20,000 Bootcamp | Phase 1, Phase 2, Phase 3, Funded | MT5 `.set` |
| [Tradeify](Tradeify-50K-Growth/README.md) | USD 50,000 Growth futures | Challenge, Funded | NinjaTrader settings |

Each stage folder also contains `manifest.csv` (EA, symbol, lots, dollar risk,
magic number) and the firm README repeats it as a table.

Regenerate after any research change:

```
python analysis/analyze_moneta_sizing.py
python analysis/build_set_files.py
```

The sizing in these files is the minimum-lot analysis, not a percentage of
balance: on XAUUSD the broker minimum is 0.01 lot and that alone risks more than
a small percentage would allow. Treat the dollar column as the expected 1R, not a
guaranteed stop loss.
""", encoding="utf-8")
    print("wrote", out)


if __name__ == "__main__":
    main()
