# Plug-and-play set files

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
