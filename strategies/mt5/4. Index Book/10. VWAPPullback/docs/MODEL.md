# VWAP Pullback — selected development model

## Restart and outage recovery

The journal uses broker server, account, account mode, symbol and magic plus an exclusive local instance lock. It binds the immutable broker position identifier (two exact 32-bit halves), original R, fill time, costs, highest completed close, consecutive-close counter, trailing latch and last processed M1 source. Entry nonce, bracket, time, costs and consumed attempt are flushed before submission. Interrupted accepted fills are adopted only if broker comment, time and unchanged protection verify that staged intent.

Before amending the bracket to actual-fill geometry, a second commit binds the actual fill, original R, reserved attempt and desired SL/TP. Restart can finish an interrupted amendment, or recognize one already accepted, without deriving R from a trailed stop; an existing tighter SL is retained. Close-recovery code is embedded in this folder's `ExecutionRuntime.mqh`, with no parent-folder dependency, and separately commits closes before submission. Accepted replies still require matching broker history and position-volume acknowledgment; unresolved timeouts block duplicate requests, new entries and trailing. Verified terminal partial fills permit only remaining quantity; definite rejection persists a five-second retry pause and attention.

Historical hydration restores genuine completed-bar trailing progress without replaying an old entry. Existing broker stops are not loosened. A legacy journal needs all four trailing fields and original entry-order SL must independently verify saved original R; a staged order SL that differs from the actual-fill recentered SL cannot prove that risk. Missing/corrupt/ambiguous evidence retains SL/TP and blocks new entries and unverifiable trailing with `Recovery needs attention`. It does not flatten solely because the journal is missing. Normal owned time exits and missing-protection safety still apply. Disconnected callbacks send no orders. Client-side trailing cannot advance during an outage; recovery does not launch MT5 after a VPS reboot. Local locks do not coordinate two VPS machines. Native chart replacement, reconnect and platform-restart proof remains separate from compilation and extracted tests. CFD/futures entry parity remains a separate unresolved task.

ADX display revision (2026-10-11): green requires completed M1 warmup, ADX14 strictly above 20, and ADX14 no higher than its own prior completed M1 observation. Flat is allowed. This matches this model's trigger ADX gate; Vault has no ADX gate and OBRB requires only its ADX15 threshold. Indicator colors do not replace the H/V/R or time requirements.
The updated ADX indicator and the EA that embeds it both compiled with zero errors and zero warnings. Reload the updated EA to load that resource; no separate indicator installation is required. Chart appearance after reload remains a native runtime check.

The selected NT8 1.27R / two-close trail is now ported to MT5 source (2026-10-12). Extracted-source tests compare trail levels with NT8 and execute the MT5 broker adapter. New native tester runs are still required; matching arithmetic is not proof that USTEC CFD history and NQ futures produce identical signals. The user's intended extended VWAP validation split is 2022-2026 development and 2012-2021 OOS; earlier source coverage and prior-use audit are pending. Do not claim completed cross-platform trade parity or OOS validation.

This is the user's chosen model, not a reconstruction of Matteo's transcript.

Tester clock repair (2026-10-11): weekly anchoring now uses the ORB/RBE whole-hour offset inference. A delayed first quote of fifteen minutes no longer shifts the strategy's Central session by fifteen minutes. The existing dated weekly cache still observes genuine whole-hour and seasonal changes; it does not freeze the first detected offset forever. This assumes a weekly reopening near 18:00 New York and resolves historical broker clocks at whole-hour precision. It cannot distinguish an arbitrary fractional-hour broker offset or a long opening-data hole from an offset change without trusted historical UTC metadata. Live server/GMT detection remains unchanged. Extracted-source regression checks fifteen-minute delay, whole-hour shift, winter, spring and autumn dates; native timestamp parity remains a separate check.

Execution repair (2026-10-11): the USTEC tester accepted the first Nov 1, 2021 entry with its intended SL/TP, then rejected an identical modification. That rejection closed the position and blocked every later entry. Actual-fill bracket repair now skips a modification when the owned position already carries those executable prices. A genuine bracket change still requires broker acceptance; failure still closes owned exposure and blocks entries, with existing/requested prices and return code printed to the journal. Entry rules, sizing, risk limits and management remain unchanged. Extracted-source regression covers no-op protection, one-tick repair and real rejection. MetaEditor compiled the repaired EA with zero errors and zero warnings; a new native tester run remains necessary.

## Frozen rules

- Fixed one-minute source bars, independent of the viewed chart timeframe.
- Opening range: 08:30–09:00 Central; 30 consecutive completed M1 bars.
- VWAP: volume-weighted HLC3, anchored at 08:30 Central.
- At/after 09:50 Central, a completed close strictly above the range high earns H only.
- A later completed M1 bar must contact VWAP: low <= current cumulative VWAP <= high. The H candle cannot earn V or R. That later V bar may also reclaim it and earn R if ADX qualifies.
- R requires close above VWAP, ADX14 > 20, and ADX no greater than the prior completed M1 value.
- H and V persist while ADX waits. One long trade per Central session; no synthetic first trade.
- Enter on the next available M1 quote/open. Freeze native Wilder ATR14 from the completed R trigger candle, including that candle. The prior 5-bar high / 20-bar low geometry is retired; it is not part of this selected model.
- Stop: actual fill minus 3 × ATR14, rounded toward entry to an executable tick.
- Target: actual fill plus 1.27 times the rounded initial stop distance, rounded down to tick.
- Last signal candle starts at 15:53 Central. Close exposure at 15:55 Central.
- Trailing: two consecutive completed M1 closes at or above entry + 1R activate it. Retain the highest completed M1 close and propose that close minus 0.25R, with a tick-rounded entry-plus-modeled-cost floor. Tighten only in increments of at least 0.25R; activation remains latched and the stop never loosens. Amendments apply to subsequent quotes, not retroactively inside the completed bar. A crossed proposal closes only owned exposure. Broker stop/freeze constraints or an amendment rejection retain the previous protection.
- No re-entry or alternate user-facing stop/target/trailing inputs. Trail peak, confirmations, activation and last processed bar are journaled for live recovery. Legacy journals without trail fields reconstruct from available completed bars while retaining their original broker target.

NT8 uses NQ signal/volume data for NQ, MNQ and NNQ execution. Matching expiry is required.
The selected chart contract owns sizing, orders and costs. MT5 uses its chart symbol's M1 bars;
real volume is used when supplied, otherwise tick volume. CFD results are separate from NQ evidence.

## Inputs and visuals

Vault/Overnight-style groups: trading, cash/fixed quantity risk, commission fallback,
modeled slippage, display and detailed logging. Fixed sizing defaults off; slippage defaults 3
(each point = 0.01 price), detailed logs default off. NT8 cash default $250, fixed quantity 1,
commission fallback $4/contract round trip. MT5 cash default 100 account-currency units,
fixed lots 1, commission fallback 7/lot round trip.

Commission falls back until completed live execution/history charges are available.
Slippage remains a fixed reserve; it does not change native Analyzer fill simulation.
NT8 uses KeepRunning and guards timer/order operations while disconnected. Both ports
consume old signals during attachment/history recovery and wait for a fresh completed signal.
If the day's canonical R already completed while loading/offline, that opportunity is skipped;
it cannot become a delayed fill on a later candle.
The MT5 ownership runtime requires a hedging account; it never adopts other EAs' positions.
Detailed logging now records earned H/V/R gates with source server/Central timestamp, OHLC, range high, VWAP, ADX/prior ADX and ATR. Use these rows to locate the first signal divergence; different dollar sizing is not a signal mismatch.
Nonvisual tester readiness now caches a successful 100-bar M1 read for the same completed source minute, while rechecking synchronization and clock validity. A new source minute, failed read or lost synchronization forces a fresh check; failures retry within the minute. Live history/disconnect behavior is unchanged. The extracted-source fixture reduces 1,000 same-minute successful tester calls from 1,000 CopyRates requests to one; native elapsed-time improvement has not been measured. Tester initialization already skips timer creation.

The compact panels follow each platform's existing reference style: NY/CT clock, range,
position, Trades 0/1, risk/costs and ADX/HVR state. VWAP is dotted. ADX is added automatically
and green only above 20 and nonrising. H/V/R labels, native NT8 execution arrows/trade lines,
and reference execution boxes show the sequence. No entry text labels or fabricated arrows.
MT5 embeds its ADX pane in the EA binary; NT8 is a single strategy source file.

## Evidence and next gate

Selected NQ development replay: 2022-01-06 through 2026-09-24, one contract, gross before costs.
428 trades; $56,470; PF 1.394; daily annualized Sharpe 1.252; monthly Sharpe proxy 0.324;
85 outliers under the full-period mean ± one sample standard deviation definition.
2025: $22,570. 2026 through September 24: $6,490. This does not meet the original $80k target.

The development replay excludes 98 incomplete full-session datasets. Production cannot
know that a future minute will be missing: it validates observed opening-range/data availability.
Native Analyzer counts can therefore differ on incomplete sessions and contract merge settings.
Source-core comparisons, compilation, native Analyzer/Playback execution, and live readiness
are separate gates. Do not describe this development selection as unseen validation.

Old parity harness and exports are archived outside the NT8 Custom project in the research
directory. Copy VWAPPullbackNT8.cs for NT8 installation; copy VWAPPullback.ex5 for MT5.

## Build verification — 2026-10-11

- Native MetaEditor: EA and embedded ADX pane compile with 0 errors / 0 warnings.
- Native NinjaTrader.Custom project: 0 errors; one existing CS8012 WPF processor warning.
- Fresh extracted C# fixtures: H-only, later V/R, ADX slope, cutoff, one/day, native seeds,
  ATR/ADX recurrence, rounded 1R geometry, broker boundaries, idempotent fee observer,
  and actual-fill risk guard pass.
- Full-source compiled C# core: 1,695,524 NQ bars, 1,133 complete sessions, all 428 selected
  development signal timestamps match. Maximum ADX and ATR differences: zero.
  Maximum VWAP difference: 8.37e-11.
- MT5 and NT8 extracted arithmetic/sequence cross-check passes. This is a helper
  translation proof, not native MT5 execution or cross-feed PnL parity.
- Old research harness/exports preserved at research/vwap_pullback/nt8_parity_harness.

Pending: native Analyzer on NQ M1, fixed one contract, 2022-01-06–2026-09-24;
then Playback/Sim for partial fills, ownership, startup during a historical open trade,
connection recovery, and broker fees. The live chart startup guard refuses unresolved
historical exposure rather than promoting that old position to live orders.

Both ports block existing opposing local exposure by default. NT8 reuses the shared index
admission guard. MT5 checks the current account's chart symbol and identifiable equity-index
positions/pending entries. It cannot govern another EA that does not use the same guard,
another terminal, or an account not visible to this process.

