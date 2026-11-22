# GotobiFix (MT5)

**Instruments:** USDJPY, EURJPY, GBPJPY — one chart per pair. **Version:** 1.00.

Japanese *gotobi* settlement-day fix strategy:

- **Long leg:** into the 09:55 Tokyo fix.
- **Short leg:** from 09:55 to 10:30 Tokyo.
- Only Japanese gotobi settlement days are traded.
- Exits are clock-only. There is no stop or target by rule; an optional
  catastrophic broker-side stop and other guards default to off for rule parity.
- Default **fixed lots** (0.10; the reference rule is 1.00 on a 100k account), with
  an owned-lots exposure cap.

Magic numbers are distinct per chart/pair (default `26111701`). Trades are
appended to a common journal (`gotobifix_trades`), which is also the export used
for analysis. `ExtraHolidays` accepts official extra Japanese bank holidays.

## Source layout

- `GotobiFix.mq5` — inputs and wiring.
- `StrategyEngine.mqh` — calendar, gotobi detection, legs and clock exits.
- `ExecutionRuntime.mqh` — order handling, ownership and recovery.
- `ChartVisuals.mqh` — panel/visual state.

## Analysis lineage

- Exports: `Trades/MT5 Trades/MT5 GotobiFix {EURJPY,GBPJPY,USDJPY} Trades.xlsx`
  (custom completed-trade ledger).
- Registry keys: `GotobiFix EURJPY`, `GotobiFix GBPJPY`, `GotobiFix USDJPY`
  in `analysis/strategies.json` — each pair is a separate sleeve.
