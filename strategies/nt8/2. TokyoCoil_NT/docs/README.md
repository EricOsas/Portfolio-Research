# TokyoCoil NT8 port

2026-10-23 safeguards: exact account/contract entry reservations allow verified same-direction foreign exposure while blocking opposite or ambiguous orders. A paired coil setup reserves both directions atomically; only exact owned entry objects are excluded when renewing the pair. FX/metals never reserve index direction. Native and recovered protective orders publish exact-object exit proof. Restrictions such as liquidation-only are durably saved before pausing; no blind corrective close cancels surviving protection. Reconnect alone does not clear broker permission restrictions. Signal, news, sizing and native historical execution contracts are unchanged.

Proof: `validation/test_shared_contract.py` executes 36 production guard scenarios; `validation/test_dynamic_recovery.py` executes pending/history/ownership recovery. Native compile and broker/VPS runtime acceptance remain separate.

Current UI (2026-10-16): Enable new trades is in the top Trading group. Broker close confirmation is no longer a configurable or serialized input. Automatic exact-owned recovery remains active; incomplete evidence pauses new exposure. Earlier manual-confirmation instructions below are historical and no longer available through settings.

## Deployable files

Only `TokyoCoilNT8.cs` is required as project source. No other strategy, helper source, validation file or subfolder is needed for compilation or visuals. Installed NinjaTrader/.NET/SharpDX assemblies remain platform requirements. Remove the previous split helper files and their project entries on the VPS before compiling the consolidated module; leaving them creates duplicate types.

New audit logs and news-cache/calendar files use this strategy source folder. Optional historical news CSVs must be placed here (TuesdayTurnaround resolves a supplied path to its filename). Existing account recovery/risk journals remain in their original NinjaTrader user-data locations to preserve active ownership and restart compatibility; they are generated runtime state, not deployment source dependencies. Do not delete them when replacing code.

One self-contained source file: `TokyoCoilNT8.cs`. Included in NinjaTrader.Custom.csproj. Select TokyoCoil in NT8.
Defaults retain 1% balance risk, inclusive 20-trade/-4R half-risk brake, news OFF,
five-minute optional news lead and no BE/trailing. No C3, clock-profile, unused
optimization or legacy preset controls.

Connection-loss default is KeepRunning. Every owned submit/cancel/protection/close
path checks the account connection. The one-second timer sends no order actions
while disconnected; deferred protection and closing intent resumes after return.
Reconnect after range lock consumes the stale setup; reconnect before range lock
allows that evening's fresh setup. Entry plans retain their original session/stop
for delayed execution callbacks. Existing saved instances/templates can retain
the old connection-loss setting; set their Connection loss handling to KeepRunning.
This does not automatically restart a terminated platform or reconnect a login.

The RBE dashboard renderer, fonts, row coordinates, collapse/drag and DPI handling
are copied inside TokyoCoilNT8.cs. The background is fully opaque to cover objects.
Clock selection matches RBE: historical bar time, Playback clock, otherwise UTC
converted to DST-adjusted NY. All runtime project code is embedded in this one source module.

## Data and execution contract

Primary chart can use minute bars. Added M1 bars build the 20:00–23:00 NY box;
ordered 1-tick Last bars drive entries/exits. Download at least 30 prior NY
sessions for warmup. Only Sunday–Thursday boxes with >=30 M5 buckets and a
USDJPY-equivalent width >=0.02 qualify. Median uses valid boxes within the
preceding 20 observed NY sessions, minimum ten valid boxes. Historical minute
timestamps mean bar close; range contents are the preceding minute.

USDJPY is the source-parity instrument. Historical Forex Last prices are treated
as bid, with the declared Historical Forex spread in ticks added to obtain ask.
That assumption must be reconciled with the actual feed. NT8 Last ticks are not
MT5 generated ticks; matching signal logic alone cannot establish fill parity.

6J is a separately labeled futures adaptation. Its reciprocal price represents
USDJPY for the width filter: 1/low - 1/high. Native 6J high breakout buys 6J
(equivalent to selling USDJPY); native low breakout sells 6J. Entry buffers use
native tick size/spread and stops use the opposite native box side. Contract
sizing uses native point value; quantity is rounded DOWN, capped by Maximum
futures contracts. Enforce risk budget defaults ON: risk below one contract
skips the trade. With it OFF, minimum quantity is used when the applied budget
cannot fund it; planned stop risk can exceed the requested amount. Normal
quantities still round down. The equity brake applies before this decision.
This controls planned stop risk; slippage/fees can increase realized loss. USDJPY quantity is
rounded down to 1,000 units, converting yen stop risk to USD at entry price and
realized yen PnL at exit price. This is not a claim of economic or performance parity.

Orders use unique per-instance/session names, unmanaged OCO breakout entries,
native protective stops for each fill and strategy-owned cancellation/exits.
Timed/news exits wait for entry/stop cancellation acknowledgments and processed
fills before submitting the remaining market quantity. Chart history draws shadow trades
without submitting orders. Analyzer uses native orders. Realtime requires a
fresh quote; missing/reconnect history or an already crossed trigger consumes
the session conservatively. Historical references are remapped at transition.
Same-account overlapping strategies on the same futures instrument require a
coordination policy; this port does not pretend independent offsetting exposure.

Analyzer capital is explicitly used for percent sizing; live uses account USD
cash balance. Brake R is price return/original stop risk, matching MT5, excluding
costs. Analyzer capital changes use passed fills and commissions. Forex swap
and broker-specific commission/quantity semantics remain feed gates. Live R
ledger is account/instrument scoped under Documents/NinjaTrader 8/TokyoCoil;
it restores this port's previously recorded trades across 6J contract rolls, not
unknown pre-port trades. A late opposite-side OCO fill suspends new entries,
cancels owned working orders, reconciles passed fills and closes only the owned
net exposure after acknowledgments. This path still needs native Playback proof.

## News and visuals

Live optional news uses ForexFactory weekly JSON: USD/High events with explicit
offset timestamps, converted to NY. No timezone guessing. Fetches are throttled
to 30 minutes after success, with five-minute retries after failure and a five-second
HTTP timeout. Snapshot expires after one hour and payload dates must match the
current NY week. HTTP headers request JSON with a browser User-Agent. Failed
requests preserve only a still-valid snapshot. Missing/stale calendar blocks
entries and exits owned exposure. Weekly feed is not a historical archive.

Historical news ON requires an audited NY timestamp file in
the strategy root beside `TokyoCoilNT8.cs` and a `.coverage.csv` sidecar containing
`yyyy.MM.dd,yyyy.MM.dd,COMPLETE`. Sparse fixtures cannot claim complete coverage.
The complete 2020–2026 archive is still missing; news-enabled historical parity
is not available. News OFF has no file or network dependency.

Native drawings retain all historical ranges/trades. Range levels use RB colors,
dashed until touch, solid through fill candle, expired unused levels removed.
Entry starts at first touch/fill, right edge leads three bars then tracks two.
Scheduled visual endpoint is 12:00:59 NY, adjusted only when completed M1 close
is available; historical trading exits on the first eligible 12:00 tick. Live
deadlines use a one-second NY clock event, so a tick outage does not postpone
the exit request. Cancellation acknowledgments and execution still determine
actual fill time. Dark-gray SL
and blue positive outcome boxes match RB. Synthetic entries are dashed.

## Gates

This is a port candidate, not live-ready. Required next proof: native compilation,
fixed-size USDJPY row-by-row 2020–2025 signal/fill comparison with MT5, native 6J
contract/tick/cost audit, Analyzer and Playback order lifecycle, Sim forward run.
Do not interpret retrospective 2024–2026 results as untouched validation.
Tradeify SOP and payout estimates wait for native 6J evidence.

## Recovery

The durable journal is under `Documents/NinjaTrader 8/TokyoCoil/ownership`, scoped by account and exact instrument. A replacement chart acquires the same exclusive journal lease. Deploy all strategy source files together; never copy/delete a live journal to bypass a warning.

Unknown broker states, reconnects and owned/account quantity disagreement enter a retryable recovery wait. The timer checks once per second. Exact owned broker order/execution snapshots can complete a delayed exit and resume automatically. Existing stops are preserved; no new/cancel/replacement/close action is sent from an uncertain snapshot. Foreign orders are excluded.

If the broker has actually closed the trade but NT8 has no exit evidence, the Output window prints `TokyoCoil RECOVERY_CASE ... confirmation=CLOSED <case> NO_ORDERS`. Verify closure and no remaining owned orders on the broker's own screen. Disable the strategy, set **Enable new trades = false**, enter that exact text in **Broker close confirmation**, then re-enable. The executor first retries native evidence and refuses confirmation with known live owned orders or a non-flat exact contract. Successful retirement archives `.settlement_<case>.before` and `.receipt`, rotates the owner and preserves the consumed session without inventing PnL. Clear the confirmation and re-enable new trades after the panel reports settlement. A later trade needs its own case.

Validation: `validation/test_dynamic_recovery.py`, installed-assembly compile and the coding contract at `../CODING_RECOVERY.md`. Source/build checks are separate from live VPS restart/disconnect acceptance.
