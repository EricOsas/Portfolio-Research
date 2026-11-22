# FVG Duo (MT5)

**Instrument:** USTEC (NQ/MNQ/USTEC index CFD). **Version:** 5.00.

Two independent FVG engines on one chart:

1. **Opening Drive FVG** — 10-minute fair-value gap, 1.25% stop, no resting price
   take-profit; the position is closed by a dated New York session deadline.
2. **Trend FVG** — completed M15 EMA 50/100 trend filter with fixed displacement,
   long-only, 3.0R target.

Defaults: $7.00 round-turn commission per lot, $100.00 cash risk per trade.
Broker-clock metadata requires validation; an unknown signal clock keeps
owned-position management active rather than opening new risk.

## Source layout

- `FVG_Duo.mq5` — inputs and `#include` wiring only.
- `StrategyEngine.mqh` — signal detection and trade lifecycle.
- `ExecutionRuntime.mqh` — order placement, stops, restart/ownership recovery.
- `VisualRecovery.mqh`, `ChartVisuals.mqh` — chart state and visual restore.
- `ClockProbe.mq5` — standalone broker-clock diagnostic, not part of the EA.
- `manifest.json` — hashes for the offline closeout candidate build.

## Analysis lineage

- Export: `Trades/MT5 Trades/MT5 FVGDuo Trades.xlsx` (standard MT5 Deals table).
- Registry key: `FVG Duo` in `analysis/strategies.json`.
- Paper counterpart: `Source Codes/NT8/10. FVGDuo_NT/`.
