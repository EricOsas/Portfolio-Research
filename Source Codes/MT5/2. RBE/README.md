# Range Breakout EA

## Deployable files

Recompilation requires exactly `RangeBreakout.mq5` and `StrategyEngine.mqh`, `ExecutionRuntime.mqh`, `ChartVisuals.mqh`, all in this folder. Platform trade-library code is embedded locally; no custom or standard include file outside this root is needed. No external visual/ADX EX5 is required. Once compiled, the EA EX5 runs alone.

Layout matches VaultBreak/VWAPPullback/OBRB: the `.mq5` is only a compile entry point; `StrategyEngine.mqh` owns inputs, shared model state, signals and lifecycle orchestration (including the embedded platform trade SDK); `ExecutionRuntime.mqh` owns sizing, broker execution and owned recovery; `ChartVisuals.mqh` owns chart replay/drawing and the panel. All three headers are root-local. News and clock helpers are embedded into these modules; no separate helper header is needed.

MT5 native file APIs cannot write into the Experts source folder. Generated file logs and optional historical-news CSVs therefore use the terminal Common/Files sandbox, with flat strategy-specific names; terminal GlobalVariables retain recovery state. These platform data stores are the unavoidable exception to source-root placement. No DLL filesystem workaround is introduced.

This MT5 Expert Advisor trades a fixed New York evening range on gold. It builds the range from **20:05 to 23:05 NY**, then trades a break above its high or below its low. The minimum range width is **0.4%** of price.

Default cash risk is **$250 per trade**. The initial stop is **0.6%** of the relevant range-side price. Trailing activates after a **2.6%** favorable move and follows at **0.6%** of entry price, moving only when improvement exceeds **$1**. The model has no profit target or ordinary break-even rule; the separate optional news action can request cost-covered BE. Remaining positions close at **11:55 NY** the next day.

The EA sizes positions using the symbol's contract specifications, broker volume limits, and configured costs. The broker's minimum volume can exceed the requested risk budget. Trade direction selects Both, LongOnly, ShortOnly or Off; daily limits are fixed at one trade per enabled side.

The chart shows the current NY session and the two most recent sessions with data, including their ranges, touched lines, and execution objects. Historical touches appear as labeled synthetic markers; they do not place broker orders. Existing touches are consumed on startup, and new broker entries require a later live tick on an unbroken level. Stop and profit outcome boxes use ORB_MarketExec's outlined colors. Stops freeze at their actual exit; surviving trades resolve at the 11:55 NY candle close.

The chart panel has a header button to collapse it to the title bar and expand it again.

The NY clock and session conversion are built into the EA. In the tester, a weekend market-open bar establishes the broker-to-NY offset; if that history is unavailable, trading waits for it. No time or DST settings are exposed. The EA manages only its own symbol and magic number; give independent instances distinct magic numbers.

Pending entries carry a broker-side 11:55 NY expiration. If the symbol does not support exact pending-order expiration, the EA skips new entries rather than leaving good-till-cancelled orders. Changing chart timeframes restarts the EA but preserves valid pending entries; old or incorrectly timed entries are canceled. Position stops remain at the broker, while the timed 11:55 market close needs the EA running and connected. On restart the EA retries any overdue close on its own positions.

On startup, the EA cancels any retained pending order whose side was already consumed in replay or is already beyond its level. On each fresh live tick, it compares its pending orders with the current range, risk, stop, trade limits, and expiry settings. It replaces an outdated order after its cancellation succeeds, and restores a manually removed order only if that side has not already been touched or traded and the entry window remains open. A level crossed before initialization, during a gap, or while trading was disabled stays consumed even if settings later change. Matching orders are left alone; duplicate orders on the same side are removed.

ForexFactory's current-week feed supplies live USD news to both platforms. Red-impact events are guarded by default; the selectable total windows are 5 (2m30s each side), 10 (5m/5m), 14 (7m/7m), and 20 (10m/10m) minutes. Pending entries are canceled during a known blackout. A side touched during the blackout is consumed; an untouched side can be placed again afterward. The default news action tries to move an open position's stop to a cost-covered price before the release; the broker can accept that stop only after price has moved far enough. Optional flattening is off by default. Impact corrections follow ORB_Scalper for home-sales and oil-inventory releases.

On MT5, allow `https://nfs.faireconomy.media` under Tools > Options > Expert Advisors > Allow WebRequest for listed URL. The feed is held in memory; no news file is needed. It is checked for offset-qualified times, the current New York week, and a one-hour lifetime. If unavailable or stale, the live guard blocks *new* entries and retains an already valid broker-expiring order. MT5 Strategy Tester cannot call WebRequest, so tester runs omit the live news guard and print that they exclude news blackout, news BE, and news flattening. A news-enabled historical performance claim needs a dated calendar source and separate validation.

RBE keeps its live calendar in per-instance memory; it does not share a file cache with TokyoCoil. All helper code is embedded during compilation. HTTP 429 uses a fifteen-minute backoff. Snapshot age is never reset merely by a failed refresh or a cache read. A previously validated same-week event remains eligible for tightening-only news BE during a temporary stale-feed interval; new entries remain blocked and stale schedules do not authorize flattening. Settings and event/position outcome transitions are logged without per-tick or hourly refresh spam. Accepted closing requests wait for broker settlement before any retry; pending cleanup excludes market orders.

The NT8 port uses the same current-week online feed in memory, with no calendar file. It rejects dates without explicit offsets and a wrong-week payload, and blocks new entries when the feed is missing or stale. Its chart history remains unfiltered, and Strategy Analyzer requires News impact Off until a dated historical news source is available. These guards and the news cost stop have compiled, but have not yet passed live-feed/Playback order-lifecycle validation on either terminal.

There are no custom research logs, CSV exports, or optimization diagnostics. Use MT5's trade history and Strategy Tester reports to review or export results. To run on another machine, copy only `RangeBreakout.ex5`. To recompile, keep `RangeBreakout.mq5`, `ChartVisuals.mqh`, `ExecutionRuntime.mqh` and `StrategyEngine.mqh` together in the strategy root folder. All custom code is embedded in the EX5; no shared folder, subfolder, calendar file or helper file is needed at runtime. The platform trade-library implementation is embedded locally.

Version 1.13 keeps the ForexFactory calendar in this EA instance's memory, with a 30-minute refresh and a 15-minute retry backoff for HTTP 429. Refresh failure never resets the snapshot's age. News still requires internet access and the allowed WebRequest URL `https://nfs.faireconomy.media`; the EX5 contains the code, not a future news calendar. Removing/reloading the EA starts a fresh memory cache.

ForexFactory prints its availability or readiness once per EA launch. Refreshes and retries continue silently; freshness checks and blocked-entry behavior remain active.

Version 1.14 fixes repeated news-BE status messages while flat: quote availability is reported only for an explicitly owned position. Without one, `no_owned_position` remains the stable once-per-event outcome. BE retries and quote-freshness checks remain active for owned positions.

Version 1.15 separates retaining an armed pending order from placing a new one. A matching order whose setup timestamp precedes the first level touch may complete its trigger; an already consumed level still cannot acquire a new order. Session, news, risk, trade-count, duplicate and settings checks remain. Missing/ambiguous touch timing does not authorize retention. Failed pending-update cancellations include a reason. Fill-recenter success requires an accepted broker return code and matching SL/TP readback, rather than only the CTrade Boolean return.

Version 1.11 uses the session date when converting historical server times to New York across DST changes, while retaining ORB_Scalper's live calibration. The clock fixture passes 64 checks. This fixes a cross-DST rebuild defect; it does not establish the cause of the October 7–9 cross-platform range differences, which still require source-minute comparison.

The panel disables foreground candles while attached and redraws after foreign chart objects are created so newer execution drawings do not cover it. Prior chart settings are restored on removal. Occlusion of MT5's built-in trading overlays still requires a terminal visual check.

## Fixed configuration and recovery (October 13, 2026)

### October 23 execution safety

Broker close-only/trading-disabled responses persist a pause scoped to server, account, symbol and magic. Daily resets and reloads do not clear it. Existing broker stops remain untouched. The embedded trade transport records the response synchronously, before another tick can send a corrective request. Netting accounts refuse mixed opening ownership and foreign symbol allocations; hedging positions continue using explicit tickets.

Close intent and acknowledged order identity are saved before/after submission in flat strategy-prefixed native Common/Files data. Reloading cannot silently forget an unsettled close and submit another. A request interrupted before its broker order ID was acknowledged remains pending; missing evidence is not permission to guess a duplicate close. Corrupt close records retain protection and block that close. These platform data files are not compilation/deployment dependencies and must not be deleted to force recovery. The EX5 remains standalone.

Offline compilation and fixtures do not establish VPS disconnect/restart acceptance. An unresolved pre-acknowledgement close remains an explicit limitation requiring broker evidence.

Range filtering, initial stop, trailing and daily trade limits are fixed model constants. User inputs cover cash risk, modeled costs, direction and news protection. Magic remains configurable because it proves order ownership; independent instances require distinct values. Display/model selectors are no longer inputs. Existing presets cannot override the fixed stop/trailing settings; reselect direction explicitly when migrating an old Max_Buy/Max_Sell preset.

Recovery reads broker position identifiers, owned history and accepted stops before fresh pending placement. It restores session fill counts and consumed sides, retains existing SL/TP and only reconstructs a missing stop; overdue owned closes are retried after reconnection. Fresh quotes are required for trailing and new entries. The EX5 includes its helper code and needs no external deployment file. Native outage/restart verification remains required; compilation and source fixtures are not live runtime proof.

## Tester close-retry correction (2026-10-31)

Strategy Tester reports (`MT5_RBE_Trades_2.xlsx`, 2020-2026) showed positions that reached the 11:55 NY cutoff but stayed open until their stop, sometimes weeks, months or years later, accumulating swap of thousands of dollars. Only 5 of 56 paired positions closed by time. Root cause in `RBECloseOwned`: a close that was sent without an acknowledged order (no `ResultOrder`, or no history entry) left a durable intent with order=0, and the function returned "in flight" on every later tick, so no retry was ever sent.

- **Tester only:** a close sent in this run is sent again if the position is still open 3 simulated seconds later. The order-history variant of the same wait is covered too.
- **Live unchanged:** the rule that missing acknowledgement is never a reason to send a second close still applies, and checkpoints loaded from disk keep the original behaviour.
- The EA prints `[RBE] Owned close retry` when a close is refused. Those lines in the tester Experts log are the diagnostic to check: if you see none and positions still stay open past 11:55 NY, the cause is elsewhere, probably in ownership (`RBEOwnedSelectedPosition`) on a netting account or in the tester's tick flow, and the Experts log should be sent.

Not compiled here; run a short tester pass over 2020-01-01 to 2020-03-31 and confirm every non-stop exit falls at 18:55 server time (11:55 NY).

## Missed 11:55 NY cutoff: diagnostics and tester fallback (2026-11-01)

The 2026-10 tester log showed some positions closed at 18:55 server time (11:55 NY) and others, such as #2, #6, #17 and #23, left open until their stop days later. For those, `PositionClose` was never called and no `Owned close retry` line was printed, so `RBECloseOwned` returned through one of its silent guards (restricted account, ownership check, or close-checkpoint state).

- `ClosePosTime` now prints one line per position the first time it is due and still open, with: owned, restricted, checkpoint volume/order, due time and current time. Search the Experts log for `Cutoff due but position`.
- Strategy Tester only: a position still open 5 seconds after its cutoff is closed directly with `g_trade.PositionClose`, logged as `Tester forced cutoff close`. Live trading is unchanged and never sends a second close on missing acknowledgement.
- Not compiled here. Check: run 2026-10-01 to 2026-10-31 on XAUUSD and confirm every non-stop exit is at 18:55 server time. If `Tester forced cutoff close` appears, send the matching `Cutoff due` lines: they identify the guard that fails.
