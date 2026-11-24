# TuesdayTurnaround NT8

2026-10-23 safeguards: shared-account exact-contract reservations permit verified same-direction exposure and block opposing or ambiguous orders. Fresh and recovered owned exits publish exact-object proof; exit coverage uses full account net and OCO alternatives count once. Broker restrictions persist through an optional validated ledger suffix while unrestricted legacy ledgers retain their format. Restriction pauses retain protection and do not auto-clear on reconnect. Signal, daily-bar, news, sizing and historical execution contracts are unchanged.

Proof: `../3. TokyoCoil_NT/validation/test_shared_contract.py` executes the identical production guard for both families. Native compilation and broker/VPS acceptance remain separate.

Current UI (2026-10-16): Enable new live trades is in the top Trading group. Broker close confirmation is no longer a configurable or serialized input. Automatic exact-owned recovery remains active; incomplete evidence pauses new exposure. Earlier manual-confirmation instructions below are historical and no longer available through settings.

## Deployable files

Only `TuesdayTurnaroundStrategy.cs` is required as project source. No other strategy, helper source, validation file or subfolder is needed for compilation or visuals. Installed NinjaTrader/.NET/SharpDX assemblies remain platform requirements. Remove the previous split helper files and their project entries on the VPS before compiling the consolidated module; leaving them creates duplicate types.

New audit logs and news-cache/calendar files use this strategy source folder. Optional historical news CSVs must be placed here (TuesdayTurnaround resolves a supplied path to its filename). Existing account recovery/risk journals remain in their original NinjaTrader user-data locations to preserve active ownership and restart compatibility; they are generated runtime state, not deployment source dependencies. Do not delete them when replacing code.

Run one strategy instance per model (T1-T4). The signal source is NT8's added native Daily series; orders execute on the added 1-minute series.

Both internal series are pinned to `CME US Index Futures ETH`; changing the primary chart interval or its display template cannot change strategy OHLC, IBS, signals, or fills. Current source build is `2026-10-10q`.

The dashboard uses the RBE dimensions, Segoe UI fonts, colors, New York clock, and drag/collapse controls. Its one-second timer publishes display state and retries owned recovery/management work when connection evidence permits. Default connection-loss handling is Keep running. Execution callbacks pause order actions unless the account connection is Connected. Existing saved strategy instances must select Keep running if they retained another setting. This setting does not suppress unrelated order rejection or runtime-error shutdowns.

For VPS deployment copy only `TuesdayTurnaroundStrategy.cs`, then compile in NinjaScript Editor. RBE is not required on the VPS. Sim verification still required: disconnect with an owned position, cross an exit/blackout cutoff, reconnect, confirm no order calls during the loss and exactly one appropriate action when callbacks resume.

Asset presets are automatic: ES/MES use Monday low minus 0.50 Monday range; MNQ uses minus 0.75 range; NQ uses one tick below Monday low and moves its stop to cost-covered break-even after +1.5R. These are the geometry-validation candidates, not frozen-holdout results.

For Python parity use `FixedOneContract`, set the Strategy Analyzer commission template separately, and provide a unique CSV audit path per run. Every native Daily bar is exported as `DAILY` with its full OHLC. Python must load these rows rather than reconstruct its signal bars from minutes. Compare `DAILY`, `SIGNAL`, actual `ENTRY`/`EXIT` fills, and chart arrows. `RiskBudget` sizes to at most $500 using the Monday-close estimate, point value, and the validated round-turn friction schedule.

The chart panel shows source, engine, model, risk mode, and state. Gold arrow = Monday setup; blue arrow = entry fill; orange arrow = exit fill; trade line is green/red. Risk sizing uses the first available Tuesday-session minute price estimate and skips an entry that opens through its stop.

Execution geometry is self-contained while retaining the ORB palette: entry RGB 214/218/224, SL box RGB 55/57/68, and trailing line RGB 162/138/88. The Friday-open reference runs from the Friday session open through the actual exit, or follows the chart edge while unresolved. Stops shorten the object immediately; time exits end it at the model's executable close.

Daily callbacks calculate signals; entries execute on the 1-minute series. `StartBehavior` defaults to `ImmediatelySubmit`. On a live chart, historical bars calculate visuals and audit rows but cannot create historical orders or positions. Transition clears pending requests and remaps any owned realtime order references. Strategy Analyzer retains full historical trading. Live trading starts with the next fresh realtime Monday signal.

The forming Monday O/H/L/C and IBS now update from the internal 1-minute series on every tick. This preview is visual only. The completed native Daily bar remains the sole signal source; a failed rule removes the preview automatically at Monday close.

The ForexFactory filter defaults to USD red-folder events with RBE impact classification and a 10-minute total blackout (5 minutes before and after). Total presets 5/10/14/20 minutes give 2m30s/5m/7m/10m per side. Pending entries are cancelled and ordinary trailing changes freeze by default; the resting stop remains active. Cost-covered news BE defaults on and only tightens a valid stop before a selected event. Round-turn commission is assumed per asset until completed live trades supply it; assumed slippage remains configurable per side. Flattening an open owned position defaults off. Missing data blocks entries but cannot trigger flattening or BE. This strategy uses one-shot market entries: blocked/cancelled setups are consumed and never replaced after news; cancellation-race fills are unwound. Live data must cover the current NY week and satisfy the cache-age limit. Analyzer runs require `Historical news CSV`; set `News folders = Off` for unchanged baseline parity.

Native Exit on session close is disabled for every model because it suppresses T1/T2 entries submitted at the completed Monday session boundary. T1/T2 submit their base exit from the 1-minute series before the first execution session ends. T3/T4 use completed native Daily sessions: after Tuesday, Wednesday, and Thursday complete, the minute series stages the Friday deadline. A T4 close-rule signal exits at the next tradable minute because the completed close cannot be known earlier.

`Enable fixed self-close` overrides native session-close handling and defaults off. Its default cutoff is `164455` New York time, converted from NinjaTrader's configured platform timezone. Historical Analyzer submits during the 16:44 minute for a 16:45 fill; realtime submits on the first Last tick at or after 16:44:55. This option makes T1/T2 Tradeify-compatible on regular sessions; holiday early closes still require the announced holiday cutoff.

Historical chart and Playback preload fills use a separate visual-only shadow simulator. It draws the same ORB-style entry, risk, stop, BE/trail, Friday-open, and exit objects without creating managed orders that `ImmediatelySubmit` could transmit. Playback realtime signals continue through the real order path.

## Recovery

Unknown/missing broker snapshots, delayed exact owned fills and connected account/owned quantity disagreement now pause and retry. They do not poison the durable ledger. Exact ID/fingerprint conflicts still block. Existing broker protection remains; foreign same-contract orders stay outside ownership.

The Output window prints `RECOVERY_CASE` with the exact confirmation when unresolved owned exposure remains. For a broker-confirmed external close with missing NT8 evidence: disable the strategy, set **Enable new trades = false**, enter the exact confirmation in **Broker close confirmation**, then re-enable. It requires a connected flat exact contract and no known active owned orders; exact owned executions are reconciled first. The built-in settlement archives original state/receipt, retires the old trade tag and preserves consumed Monday/cost history. It does not fabricate an exit or PnL. Old tags and old confirmations cannot affect a later trade.

Tests: `validation/test_broker_reconciliation.py`, `validation/test_owned_recovery.py`. See `../CODING_RECOVERY.md` for the mandatory new-strategy contract and separate VPS acceptance cases.
