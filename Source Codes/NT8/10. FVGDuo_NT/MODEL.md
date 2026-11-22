# FVG Duo (NT8)

**Instrument:** NQ / GC futures (export used NQ DEC26). **Strategy version:** 5.00 shell.

NinjaTrader 8 execution shell for the FVG Duo engines: Opening Drive FVG
(10-minute gap, 1.25% stop, dated New York session deadline) and Trend FVG
(M15 EMA 50/100, fixed displacement, long-only, 3.0R target).

The shell owns only what the platform can prove: executable quotes, fill risk,
scoped inventory, durable order lineage and separately protected contract
slices. Signal decisions are meant to live in `FvgDuoCore.cs`.

Apply to any chart of the instrument — the strategy adds its own M1 / M10 / M15
series. Set *Days to load* high enough for roughly 1,000 completed M15 bars of
warm-up; 10 calendar days is the engine minimum and a few months is safer for
the EMA/ATR seed. The flatten minute comes from the platform session template
when it falls inside 13:00–17:00 New York; otherwise the strategy's RTH table
applies.

## Source completeness

- Present: `FVG_Duo_NT8.cs` (shell, fill-risk, slice book, recovery evidence).
- **Missing: `FvgDuoCore.cs`.** The signal/indicator core referenced by the shell
  is not in this folder, so this NT8 source drop cannot be compiled as-is.
  Treat the MT5 implementation (`Source Codes/MT5/12. FVGDuo/`) as the complete
  reference until the core is restored.

## Analysis lineage

- Export: `Trades/NT8 Trades/NinjaTrader FVGDuo Trades.csv`.
- Registry key: `FVG Duo` in `analysis/strategies.json`.
- Paper counterpart: `Source Codes/MT5/12. FVGDuo/`.
