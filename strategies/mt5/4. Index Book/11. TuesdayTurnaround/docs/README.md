# TuesdayTurnaround MT5

## Deployable files

Recompilation requires exactly `TuesdayTurnaround.mq5` and `StrategyEngine.mqh`, `ExecutionRuntime.mqh`, `ChartVisuals.mqh`, all in this folder. Platform trade-library code is embedded locally; no custom or standard include file outside this root is needed. No external visual/ADX EX5 is required. Once compiled, the EA EX5 runs alone.

Layout matches VaultBreak/VWAPPullback/OBRB: the `.mq5` is only a compile entry point; `StrategyEngine.mqh` owns inputs, shared model state, signals and lifecycle orchestration (including the embedded platform trade SDK); `ExecutionRuntime.mqh` owns sizing, broker execution and owned recovery; `ChartVisuals.mqh` owns chart replay/drawing and the panel. All three headers are root-local. News and clock helpers are embedded into these modules; no separate helper header is needed.

MT5 native file APIs cannot write into the Experts source folder. Generated file logs and optional historical-news CSVs therefore use the terminal Common/Files sandbox, with flat strategy-specific names; terminal GlobalVariables retain recovery state. These platform data stores are the unavoidable exception to source-root placement. No DLL filesystem workaround is introduced.

Audit files: `Common/Files/TuesdayTurnaround_audit_<symbol>_<magic>.csv` (flat; no TuesdayTurnaround subfolder).


Port of the verified T1-T4 completed-Daily model. The EA follows the modular RBE/VaultBreak/OvernightBiasRangeBreakout layout.

## Signal and execution contract

- Source: broker-native D1 bars. The same RBE/Vault clock engine calibrates live server/GMT time and uses the 18:00 New York weekly-opening anchor in the tester and for dated history. Trading waits when that clock is unresolved.
- D1 session parity is mandatory: the broker bar must represent the same futures trading day as the NT8 native Daily bar. Compilation does not prove this; compare D1 OHLC and dates before testing PnL.
- A Monday is eligible only when its preceding D1 bar is the exact calendar Friday.
- T1: Monday close <= 99% of Friday close.
- T2: Monday close < Monday open and IBS < 0.20.
- T3/T4: Monday close < Friday close and IBS < 0.50.
- Entry: market buy on the first executable Tuesday quote after the completed Monday D1 bar.
- T1/T2 timed exit: first executable quote at/after configurable `BaseCloseHHMMSS` (default 16:59:55 New York) Tuesday. T3/T4 use the same clock Friday (fourth trading session). This is the MT5 executable proxy for the final tradable price before the 17:00 session end. T4 may exit earlier at the first later completed close above the preceding D1 high.
- Stop: ES/MES = Monday low minus 0.50 Monday range; MNQ = low minus 0.75 range; NQ = low minus one tick.
- NQ only: move stop to commission-covered break-even after +1.5 initial R.
- A gap/open through the stop skips the trade.
- Risk sizing uses learned owned-deal commission when available, otherwise the asset commission fallback, plus one assumed slippage tick per side by default. `CostPerContract` remains a legacy total-cost override. `Fixed Lots` exists for parity probes; `Cash Risk Budget` sizes against the configured cash risk.

Current research candidates are NQ/MNQ T1 and ES/MES T4. `Model` remains an explicit manual input; the EA does not silently change rules from the symbol. T4 can hold through multiple sessions and is unsuitable for Tradeify's daily-flat account unless a separately tested forced-close variant is selected.

## News contract

MT5's native economic calendar supplies live events in broker-server time. Default: USD High/red events with a total 10-minute blackout, split exactly 5 minutes before and 5 minutes after. Presets also provide 5 minutes (2:30/2:30), 14 minutes (7/7), and 20 minutes (10/10). Red/yellow/all classification follows the ORB Scalper method, including its housing/oil importance adjustment.

At blackout start the default action cancels owned pending orders, consumes any locally armed Monday signal so it cannot refill, freezes trailing changes, and moves an existing profitable position's protective stop to estimated commission-and-slippage-covered break-even when executable. `FlattenAtBlackout` remains disabled. TT enters by market at Tuesday open and normally has no broker pending trigger order; cancellation is lifecycle cleanup, not a breakout rule. A fill caused during a cancellation race is always unwound; the flatten toggle controls only positions that predated the blackout.

Missing native-calendar data fails closed for new exposure and owned pending cleanup, but cannot move a stop or flatten a position. Those actions require a selected event and its pre-release interval. When flattening is enabled it takes priority; otherwise cost-covered break-even retries during that interval until price permits the protective improvement.

Every stop change is a one-way ratchet: `TTModifyOwnedStop` rejects a stop at or below the current protective stop. The later ordinary NQ +1.5R break-even therefore cannot lower a higher news break-even stop.

If the live native-calendar query fails, the filter fails closed and retries after 60 seconds. With news enabled, Strategy Tester also fails closed unless `HistoricalNewsCsv` names a Common Files CSV (`yyyy.mm.dd hh:mm,USD,High,title`, UTC). Disable the filter explicitly only for a separately labelled base parity run.

The effective magic is `MagicBase + model number`. Run only one instance for the same account/symbol/model/magic. Give duplicate instances different `MagicBase` values; MT5 netting accounts still cannot provide true same-symbol position ownership between strategies.

## Live Monday behavior

The current native D1 OHLC and IBS are read every tick and timer cycle, so Monday range/IBS visuals update without chart refresh. The signal is validated once, only after the D1 bar completes. A rejected Monday clears owned pending state.

## Release gates

1. MetaEditor compile with zero errors.
2. Fixed-volume MT5/NT8 parity: D1 OHLC, signals, Tuesday entries, stop, exit reason/time.
3. Visual tester: Monday values update and entry/stop/exit lines match deals.
4. Live demo: news fetch/cache, blackout edges, restart, reconnect, foreign order/position isolation.
5. Forward Sim, then one-micro canary.

## Recovery

2026-10-23 request-boundary safeguards: every embedded trade request checks a durable account/server/symbol/magic broker-restriction marker. A liquidation-only, close-only or disabled-server rejection pauses further requests across restart and retains broker protection. Reconnection alone does not clear a broker permission restriction. The EA reports the broker response; account permission recovery needs separate verification.

Close/stop requests require exact position identifier, verified opening magic/symbol and matching remaining entry/exit volume. Close intent is flushed before submission; pending and ambiguous acknowledgements block duplicate closes. Exact owned close history can hydrate a lost acknowledgement. A native exclusive executor lock prevents duplicate charts from managing the same strategy identity. Native terminal GlobalVariables and flat Common/Files lock storage are platform-managed exceptions to source-root packaging; the compiled EX5 still runs alone.

Proof: `3. TokyoCoil/validation/test_request_boundary.py` from the Experts root executes the production ownership, restriction and close-settlement predicates for both families. Both EAs compiled with zero errors/warnings. Source fixtures and compilation do not establish VPS/broker restart acceptance.

Saved position identifiers are cleared only after complete exact-position exit history validates the owned opening volume. Transaction callbacks use the same reconciliation path, so delayed deal history cannot bypass the guard. Manual exits with magic zero can settle the owned position; mixed opening ownership and netting reversals do not qualify.

Missing metadata/stop snapshots and foreign netting occupancy remain retryable waits. Existing broker protection is retained. Original risk must come from saved metadata or the verified opening order, never from a moved trailing stop.

Deployment requires only the rebuilt `TuesdayTurnaround.ex5`. The existing source files remain in this strategy root. Proof: `validation/test_contract.py` and `../../3. TokyoCoil/validation/test_exit_hydration.py` (from the Experts root, the latter is `3. TokyoCoil/validation/test_exit_hydration.py`). Native compilation and live broker/VPS recovery acceptance are distinct. See `../../CODING_RECOVERY.md`.
