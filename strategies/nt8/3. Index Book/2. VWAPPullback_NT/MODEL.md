# VWAP Pullback — selected development model

Native chart history correction 2026-10-17: an existing recovery journal must not suppress historical strategy orders. The recovery pending/fault entry gate now applies only in realtime. Completed chart sessions execute through NT8's existing native M1 fill engine, supplying platform execution arrows and trade lines; these are simulated historical fills, not reconstructed broker fills. As in RBE, the incomplete tail session is excluded from chart order simulation until the loaded execution bars extend at least two minutes beyond the strategy cutoff, preventing historical exposure from entering live recovery. Analyzer behavior is unchanged. The existing realtime journal load, ownership checks and historical-flat transition refusal remain intact. Chart/VPS visual acceptance remains separate from compilation and gate fixtures.

Recovery lifecycle correction 2026-10-16: never add a replacement leg to an existing OCO group. Retain surviving protection and wait for missing/cancelling broker evidence. Restore a fully settled bracket stop-first with a fresh durable OCO intent only after owned fills reconcile. Live technical protective cancellation requests recovery rather than a forced early exit. A saved ProtectionCancelled state resumes only with consistent owned fills and no pending/partial/rejected close; genuine strategy exits retain precedence. Delayed equal-fill callbacks cannot regress terminal/cancelling state. Manual closes lacking attributable execution evidence remain pending on shared accounts; account flatness does not fabricate an exit. Native compilation and fixtures are separate from VPS restart acceptance.

Recovery update 2026-10-16: temporary Account.CreateOrder IDs are replaced with provider IDs from the exact registered order callback before reconciliation. Legacy temporary-GUID protective bracket IDs may bind only to one matching acknowledged broker order, with exact account/contract/owner/OCO, direction, type, quantity, prices and fill bounds. The original journal is backed up as .before_provider_id_<UTC ticks>; success logs RECOVERY_PROVIDER_ID_BOUND. Binding sends no broker orders. Assigned-ID conflicts remain blocked. Source fixtures and native compilation do not establish VPS runtime acceptance.

Current runtime recovery (2026-10-15): [RECOVERY.md](RECOVERY.md) specifies automatic mismatch detection, retry on delayed owned broker evidence, and the case-specific external-close confirmation fallback. This supersedes older restart/ownership limitations below. Trading model parameters are unchanged.

This is the user's chosen model, not a reconstruction of Matteo's transcript.

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
- Trailing: two consecutive completed M1 closes at or above entry + 1R activate it. Keep the highest completed M1 close; propose that close minus 0.25R, with a tick-rounded entry-plus-modeled-cost floor. Tighten only in increments of at least 0.25R. Activation remains latched after confirmation; the stop never loosens. Changes apply to subsequent prices, not retroactively inside the completed candle. A crossed proposed stop queues an owned market close. No historical ticks or new user-facing exit inputs are required.
- Last signal candle starts at 15:53 Central. Close exposure at 15:55 Central.
- No re-entry or user-facing stop/target/trailing model inputs. Exit constants are internal.

NT8 uses NQ signal/volume data for NQ, MNQ and NNQ execution. Matching expiry is required.
The selected chart contract owns sizing, orders and costs. MT5 uses its chart symbol's M1 bars;
real volume is used when supplied, otherwise tick volume. CFD results are separate from NQ evidence.
The October 11 NT8 exit revision was ported to MT5 source on October 12: 1.27R target,
two completed closes at or above 1R activate the 0.25R distance/step trail, with
journaled management state. Extracted source, trail-price and broker-adapter tests
pass; a fresh native MT5 tester run and cross-feed trade comparison are still required.

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

The compact panels follow each platform's existing reference style: NY/CT clock, range,
position, Trades 0/1, risk/costs and ADX/HVR state. VWAP is dotted. ADX is added automatically
and green only above 20 and nonrising. H/V/R labels, native NT8 execution arrows/trade lines,
and reference execution boxes show the sequence. No entry text labels or fabricated arrows.
MT5 embeds its ADX pane in the EA binary; NT8 is a single strategy source file.
ADX color also requires completed-source warmup. NT8 stores each M1 ADX together with that same observation's prior M1 ADX and readiness; a larger chart bar or source gap cannot turn a rising observation green by looking up the same value twice. MT5 likewise uses its paired M1 values and readiness. This is display eligibility only; H/V/R and trading gates are unchanged.
Verification of this display revision: `tests/test_adx_display.py` compiles the production history helper and verifies rising/falling/flat values, threshold equality, warmup, larger chart timestamps, reload and numeric VWAP-history compatibility. Full NinjaTrader.Custom rebuild passed with zero errors and the existing CS8012 WPF warning. MT5's updated embedded indicator and EA compiled with zero errors/warnings. Native chart appearance after reload is a separate check.

## Evidence and next gate

Latest frozen-entry exit research: January 6, 2022 through September 24, 2026, 455 native one-contract NQ entries. The original 1R control reproduced every exported exit price/time exactly ($61,925). A 702-case percentage-stop/trailing sweep selected the internal rule above: $74,940 gross, $73,256.50 after a $3.70/trade reserve, PF 1.473 before reserve, monthly Sharpe proxy 0.393, closed-trade drawdown $9,460, 88 outliers under mean +/- one sample SD. 2025 gross $25,405; 2026 gross $3,675. It improves full-period profit and PF but worsens drawdown and 2026 profit versus the original 1R control. No tested case achieved the combined $80k / 0.50 monthly proxy goals. Native Analyzer must confirm the revised NT8 exit execution; Python is not that proof. Full matrix, selected ledger and source hashes: `C:/Users/Administrator/Documents/Strategies/Conte_Research_Strategies/research/vwap_pullback/PERCENTAGE_TRAILING_RESULTS.json`; interpretation: `PERCENTAGE_TRAILING_REVIEW.md` beside it.

Earlier initial-model NQ development replay (superseded NT8 exits): 2022-01-06 through 2026-09-24, one contract, gross before costs.
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

## Revised exit verification - 2026-10-11

Planned extended validation split, clarified by the user: 2022-2026 development; 2012-2021 intended OOS, with the full 2012-2026 period also reported. The selected NT8 constants above must stay frozen during OOS evaluation. Confirm source coverage, rollover/session conventions, costs and whether any of the earlier period was previously used before calling it untouched OOS. Older-period validation has not run yet. MT5 has the selected exit port in source; native execution and cross-feed trade comparisons remain pending.

- Full NinjaTrader.Custom build to an isolated temporary output: 0 errors, one existing CS8012 WPF processor warning. No running platform was restarted.
- Compiled extracted C# production math/runtime checks pass, including 1.27R rounding, quarter-R trail, modeled-cost floor, broker guard preservation and two-close activation wiring.
- Python exit engine: 16 focused tests pass. Original 455-trade native-export control prices/times all match. New trail still needs native Analyzer execution comparison.

## Earlier initial-model verification — 2026-10-11

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

October 12 callback repair: the strategy and hosted ADX bar callbacks now reject
loading/terminated states, missing initialized model state, and unavailable series
before accessing bars. A focused harness executes the actual callback bodies and
reproduces a null reference before the guards; afterward it verifies unload no-ops
and unchanged historical, transition, realtime, and disconnected behavior. The
reported October 11 `EventHandlerBarsUpdate` exception has no retained stack in the
available logs, so its exact origin remains unconfirmed. Native chart reload and
reconnect still require verification. Entry gates and exit geometry are unchanged.

### Analyzer fill audit fields - 2026-10-12

Enable **Write detailed decision and trade log** before running Analyzer. Each run writes a separate `C:/Users/Administrator/Documents/NinjaTrader 8/VWAPPullback/logs/VWP_<run-id>.csv`. Real fills are `ENTRY` and `EXIT`; join them by the stable `tradeId` (entry order name). `executionId` distinguishes partial executions. The row timestamp and detail `time` are execution callback times in Central time. `price`, `qty`/`quantity`, and `direction` describe each fill; exit direction remains the original trade direction, not the closing order side. `initialStop` is the executable initial bracket stop captured at entry, never the later trailing stop; `initialTarget` is recorded on entry. Repeated exit `initialStop` preserves that original value. Existing logs are unchanged; rerun to obtain these new fields.
