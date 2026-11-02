# NQPrecisionBot — NT8 portfolio runtime

Deploy `NQPrecisionBot.cs` as the single strategy module. The panel, drawing dispatcher and risk boxes, account/order transport, exposure protocol, and durable recovery helpers are local to this file. It has no source dependency on any other strategy module.

## Defaults and chart behavior

Defaults match the supplied strategy-properties image: On each tick, lookback 256, bars required 60, Immediately submit, Standard fill processing, limit-on-touch enabled, native slippage 0, one entry per direction, All entries, session-close exit disabled, Per entry execution protection, and GTC. Fixed size is enabled with **one contract**. Signals retain ATR14/50, stop 2.2 ATR, target 0.3 ATR, RVOL14 0.5–1.5, regime 1–2.5, Eastern range 09:30–09:45, trigger 09:59:55 and an eight-minute close.

The primary chart may use another interval, including 5 minutes. Chart bars never generate signals or orders. In tick mode, source ticks construct completed ETH minute OHLCV for indicators/range. When source and execution instruments match, one internal tick series serves both purposes; Nano NQ retains separate NQ source ticks and native execution ticks. Use the same dates, data, instrument and strategy inputs when comparing chart intervals.

`Use tick history for source and fills = true` is now the default. The same source-tick sequence used by the Python audit constructs completed minute bars; stored provider M1 gaps cannot replace that signal history. It retains repeated trades, closes only completed buckets, creates no empty minutes, and consumes each source index once. Source and execution tick history are required. Set it to **false** to retain the explicitly logged **stored-M1 OHLC approximation**, which cannot recover the 09:59:55 print or intraminute order. Live execution processes Last prints in either setting. Tick Replay is not required. Use Standard fill resolution and enable limit fills on touch for the reviewed tick contract.

Saved strategy instances and Analyzer templates can retain the former false setting: explicitly select `Use tick history for source and fills = true` or load a fresh instance. Startup output identifies `NQPB TICK_SOURCE_V2` and the actual source/fill settings. Detailed logs retain fractional timestamps and the time-exit request deadline. No live instance is enabled by updating this file.

Account, chart instrument/expiry, primary chart interval, chart candle colors and the Enabled checkbox are platform instance settings, not hardcoded account identities. The strategy's new-entry control defaults on; deployment does not activate it on a brokerage account. Saved instances/templates can retain old inputs; load a fresh instance to obtain these defaults. Do not replace an active legacy managed instance with an open trade.

## Standalone VPS source and execution visuals

Deploy this folder's `NQPrecisionBot.cs` into a normal NinjaTrader 8 installation. All strategy-specific models, execution/recovery helpers, exposure coordination, drawing queue and panel code are inside that single source. No other strategy module, research Python, or sibling-folder helper is required. NinjaTrader's installed assemblies and native drawing components remain platform dependencies. Runtime journals/leases are created by the strategy; preserve their active paths during a VPS migration.

Execution drawings use the viewing chart's bars: their right edge starts at entry bar +2, follows the open trade at max(entry +2, current bar +1), and on closure becomes max(entry +2, actual exit bar). The projected edge can therefore shrink at closure. Recorded executions and native arrows remain unchanged. Loaded bars determine actual spacing; future time bars use the chart interval, and future non-time bars use the latest observed spacing until real bars exist.

The opening-range box and panel high/low form from each completed source M1 candle, regardless of the viewing chart interval. The range stops expanding at its configured end; chart timeframe changes do not change the trading range.

Range high/low reference lines use the original NT8 horizon: trigger time (or TradeUntil in window mode) + CloseAfterMin + 2 drawing minutes. Defaults end at 10:09:55 New York, approximately 10:10 on an M1 chart. MT5 matches this horizon in broker time. Actual time exits remain measured from the owned fill time; the drawing endpoint does not change entry/exit times.

## Instruments and shared accounts

NQ and MNQ use their own ETH minute history. **NNQ means Nano NQ**: like the portfolio strategies, its signal history comes from the same-expiry NQ contract while orders execute on actual NNQ. Tick size, point value, rounding, commission scope and cash risk always use the execution instrument, even inside a signal-series callback. Historical NNQ tick mode requires actual NNQ ticks; NQ ticks are not substituted as NNQ execution evidence.

Same-direction strategies may hold the same account/contract. Always-on exact-contract and optional broader index exposure guards reject opposite pending intent, opposite netting and unverified/oversized exit orders. Neither account net position nor chart identity establishes ownership. The one-instance lease applies to NQPrecisionBot itself, not all models on the asset. Historical callbacks never reserve live exposure or write the live journal.

## Visuals

`ShowVisuals = true` displays the portfolio panel, Eastern opening-range rectangle/levels, and long/short execution risk boxes with entry lines from the drawing helper. Native `PlotExecutions = MarkersOnly` and `ShowTradeLines = true` preserve platform execution arrows and trade lines. Native fills remain native simulated/executed orders; no custom arrow is passed off as a platform fill. Completed chart sessions are replayed; an incomplete tail is excluded before realtime to avoid carrying invented historical exposure into activation.

Create/update work coalesces by tag and dispatches at Background priority in batches of at most 32, with terminated/detached chart work discarded. Panel drag/minimize behavior follows the portfolio panel. Chart appearance and responsiveness still need observation in the running NT8 application.

## Recovery and deployment

Live journals are under `Documents/NinjaTrader 8/NQPrecisionBot/recovery`, keyed by provider/connection, account, exact contract and NQ model identity. Exclusive journal leases, atomic replacement and a previous generation preserve exact order intent/IDs, cumulative executions, original bracket prices, consumed decision date, first actual fill time, original absolute deadline and pending close intent. The original enabled/disabled time-close contract survives a chart/timeframe replacement and changed inputs. A rejected/inside fixed-trigger decision is also consumed durably. The v3 record refuses an older ambiguous active-trade record rather than guessing its management settings.

The executor retains existing verified broker protection while snapshots, disconnects or fills remain unresolved. A timer retries reconciliation without requiring market ticks. The time-based exit is enforced from prints and from the one-second timer, so a stalled feed cannot delay it past the deadline (broker protection stays in place meanwhile). Replacement attaches exact owned broker objects and does not create historical copies to adopt them. Corrupt/ambiguous evidence pauses mutations; do not delete journals to clear a hold. Broker permission, restricted-account and liquidation-only denials latch durably before error handling; they do not trigger another close or cancel surviving protection. The pre-runtime managed build has no equivalent durable ownership record: unresolved legacy positions are not automatically adopted.

Compile in NinjaScript Editor before loading a fresh instance. Keep this root free of test-double `.cs` files. Deterministic tests and an installed-assembly build do not establish Playback, disconnect/restart, broker acceptance, live readiness or full Roboquant fill parity.

## 2026-10-30 reliability and visuals correction

Source edited and audited by reading; **not compiled in NinjaTrader** (no NT8 assemblies available). Compile in the NinjaScript Editor and run the checks below before loading a live instance.

- **Visuals no longer depend on trading holds.** Range box, levels and execution boxes were hidden (and not drawn) whenever *any* realtime hold was active: suspension, recovery pending/fault, disconnect, warm-up. The panel kept showing, so everything except the panel vanished. Drawings are now hidden only while the signal history is being rebuilt (`historyRepair` / `visualHistoryWaiting`). Holds are shown in the panel status and in Output.
- **Fixed-trigger window.** A decision is made on the first print at/after the trigger. If infrastructure blocks it (range not ready, no eligible filter frame, exposure guard, broker not ready or the platform declining the order), it is retried for `TriggerGraceSeconds` = 5 s, then recorded as `TRIGGER_MISSED` and the day is consumed. Signal rejections (inside range, filter, risk) still consume the decision immediately. Previously the day was consumed *before* the exposure check and order submission, and a started/reloaded instance could enter long after the trigger on its first print.
- **No stranded pending entry.** If `SubmitOwnedOrder` returns null with no journal fault, the pending state, entry count, decision day, exposure reservation and journalled request are rolled back; previously `entryPending` stayed true and blocked the day silently.
- **Stale suspension latch.** `suspended` (order error, OCO race, invalid fill, fill-risk, protection cancelled) was persisted in the journal and cleared only by a technical-protection resume, so one incident blocked every later session. It is now cleared at a session rollover only when flat, settled, reconciled, connected, holding the instance lease and with no recovery fault. Broker-restriction latches and recovery faults are never cleared automatically.
- **Time exit from the timer** as well as from prints.
- **Always-on Output lines** (not dependent on `WriteTradeLog`): `NQPB REALTIME`, `NQPB STATE` on every status change, `NQPB TRIGGER_WAIT`, `SKIP_RANGE`, `SKIP_FILTER`, `SKIP_RISK`, `ENTRY_BLOCKED`, `ENTRY_NOT_SUBMITTED`, `TRIGGER_MISSED`, `ENTRY_SUBMIT`, `SUSPENSION_CLEARED`.

Unchanged by design (verify before relying on them): an unreadable or mismatched recovery journal still latches a permanent fault; `Block opposing index exposure` still checks all visible accounts and index instruments; the recovery journal layout was not touched.

Checks after compiling: (1) panel and Output show `NQPB REALTIME ... status=` at start; (2) range box and levels draw during 09:30-09:45 ET; (3) at the trigger Output shows exactly one of `ENTRY_SUBMIT`, `SKIP_*`, `ENTRY_BLOCKED` or `TRIGGER_MISSED`; (4) on Sim, force a rejected entry and confirm no stuck pending state; (5) run a full Historical/Analyzer pass over a known date range and confirm trade counts match the previous build.

### Round 2 (from the 2026-10-30 NinjaTrader Log)

The Log showed the bot enabled at 8:13 AM, its first order at 11:26:16, a 4 s submit-to-fill latency, and `Close_17` two seconds after `Entry_16` with no stop/target orders.

- **Fill beyond the target is no longer an "invalid fill".** With a 0.3 ATR target, a few seconds of order latency routinely carries the fill through it. The old rule market-closed the position (here at a loss), set `suspended` and blocked later trades. Now only a fill on the wrong side of the stop, or zero risk, is invalid; a fill through the target keeps the normal bracket (the target limit is marketable) and logs `FILL_THROUGH_TARGET`.
- **History/Analyzer speed.** Every historical tick-second ran `Levels()` and `UpdatePanel()`, and every tick ran several `TimeZoneInfo.ConvertTime` calls. Historical replay now draws the range once when its last source minute completes, refreshes the panel once per data minute, caches the Eastern conversion (15-minute buckets with exact fallback across DST; checked against exact conversion for 7 platform time zones, 1.47 M samples, 0 mismatches) and skips the session-replay test before the trigger time. Long tick replays (the Analyzer and the chart's historical phase) should start trading hours sooner and run faster; they are not otherwise changed.
- **Historical suspension reset.** A suspension set during a backtest (for example by the old InvalidFill rule) ended trading for the rest of the run. It is now cleared at the next session rollover when flat and settled, as in realtime.
- **Startup timing in Output:** `NQPB TICK_SOURCE_V2 ... wall=` at load and `NQPB REALTIME ... wall= historicalPrints=` when realtime starts. If those two wall-clock times are hours apart, startup, not trading logic, caused a missed trigger. A start after the trigger window now records `TRIGGER_MISSED` instead of entering late.

### Start behavior, trade CSV, trigger window (2026-10-31)

- **Start behavior no longer aborts the strategy.** A saved instance, workspace or Analyzer template with another Start behavior raised `ImmediatelySubmit is required for independent owned execution` in `State.Configure`. The strategy now sets `ImmediatelySubmit` itself and prints `NQPB START_BEHAVIOR saved value '...' replaced by ImmediatelySubmit`. If NinjaTrader refuses the assignment it still stops with a message naming the saved value. Standard fill resolution is still enforced by an error.
- **Trigger window is 5 s** (`TriggerGraceSeconds`). A decision blocked for more than 5 s after the trigger is recorded as `TRIGGER_MISSED` and the day is used.
- **`WriteTradeLog` defaults on** and each completed trade is appended to `Documents/NinjaTrader 8/NQPrecisionBot_trades.csv`. Runs and Analyzer iterations append to the same file without a run id; archive or delete it between comparisons.

### Legacy identity removal and migration (2026-10-31)

All sibling-strategy names have been removed from the NT8 file, the MT5 engine, its runtime and chart visuals, and this README. The MT5 engine now uses the `NQP` prefix throughout. Points that affect a running or migrating instance:

- **MT5 lock folder** is now `NQPrecisionLocks`. A lock still held in the old `VaultBreakLocks` folder by a pre-rename build blocks startup, so an old and a new build cannot trade the same account at once.
- **MT5 order comments** are now `NQP#<nonce>`. Positions and orders already open with `VB#<nonce>` are still recognised during recovery, so an open trade keeps its ownership. Do not replace an EA with an open position without first checking that it reconciles.
- **MT5 chart objects** use the `NQP_` prefix. Objects left under the former `VB_` and `GT_` prefixes are deleted once at initialisation.
- **MT5 trade export** keeps its `model` column and writes `2`. The `variant` label changes from `funded_60_40_cap3` to `nqp_fixed_bracket`; update any research script that parses that label.
- **Removed dead code** (no callers in the shipped files): the former alternate models, their day setup and drawing, and the unused session-cap and signal-side helpers. Session cutoff is fixed at 870 minutes, and the trade cap at one, which are the values this model always resolved to.
- **Warm-up lead-in** (`NQPWarmupLeadSeconds = 3600`) is kept at exactly the previous value. It loads one extra hour of M1 history before the session start, which seeds the ATR. It is named now but its value is unchanged.
- **Not recompiled.** No MQL5 or NinjaScript compiler is available here. Compile both platforms before loading. Verify the MT5 lock behaviour on a demo account: start the new build while the old build holds its lock, and confirm it refuses to start.
