# Range Breakout NT8

October 23 safety alignment: exact account/contract reservations now protect pending entry intent while allowing verified own reversals. Both range sides reserve atomically; same-direction foreign positions are permitted only when all remaining protection is covered and no opposite entry can net their allocation. The default `Block opposing index exposure` also checks eligible index products; gold/FX do not publish index direction. Exact-contract checks remain active when that option is disabled.

Native and recovered account transports share the live owned/account evidence boundary before submissions, changes and cancellations. A stale native position after external closure cannot trigger guessed corrective orders. Broker liquidation-only/trading-disabled errors persist their pause before faulting; existing stops are retained and restart cannot silently unlock the pause. Historical native simulation remains independent of live reservations. Extracted production transport and reservation fixtures are offline proof, not VPS restart acceptance.

Current UI (2026-10-16): Enable new trades is in the top Trading group. Broker close confirmation is no longer public, configurable or serialized. Automatic exact-owned recovery remains active; incomplete evidence pauses new exposure.

## Deployable files

Only `RangeBreakoutNT8.cs` is required as project source. No other strategy, helper source, validation file or subfolder is needed for compilation or visuals. Installed NinjaTrader/.NET/SharpDX assemblies remain platform requirements. Remove the previous split helper files and their project entries on the VPS before compiling the consolidated module; leaving them creates duplicate types.

New audit logs and news-cache/calendar files use this strategy source folder. Optional historical news CSVs must be placed here (TuesdayTurnaround resolves a supplied path to its filename). Existing account recovery/risk journals remain in their original NinjaTrader user-data locations to preserve active ownership and restart compatibility; they are generated runtime state, not deployment source dependencies. Do not delete them when replacing code.

Install only `RangeBreakoutNT8.cs`. All project types, visuals, news and recovery code are embedded; validation files are not installation dependencies.

NetExposure is the only execution model. Both directions retain independent internal long/short trades and submit their combined signed broker exposure. Equal quantities can leave the broker flat while both internal trades remain active. Native NT8 execution markers and Analyzer results represent physical broker orders; custom execution boxes also represent internal trades. Those counts need not equal the MT5 hedged ledger. MT5's existing hedging behavior is preserved.

The model is fixed: NY range 20:05–23:05, minimum width 0.4%, initial stop 0.6% of range-side price, trailing trigger 2.6%, trailing distance 0.6%, improvement threshold 1.00 price, cost-coverage multiplier 1.25, exit 11:55 NY. These settings cannot be edited or optimized in the strategy dialog. Old templates cannot override them.

User controls are risk/direction, costs and news guard. Default risk is $500; strict modeled risk is enabled and maximum contracts defaults to one. Native instrument tick size and point value support MGC, GC and 1OZ; set the selected contract's actual commission. Commission defaults to $3 round trip and one assumed tick per fill. Existing live checkpoints retain their saved settings, including older commissions. Analyzer commission inclusion/template must also match. LongOnly, ShortOnly and Off remain available. Legacy hidden side limits preserve NT8 template direction; audit export and display settings are hidden compatibility controls, audit disabled by default.

Historical execution uses the internal one-minute series across loaded history; custom ranges/boxes retain today plus two prior sessions. Incomplete chart-tail sessions consume historical touches without placing hindsight broker entries. Live entries use fresh eligible Last ticks; trailing uses current bid/ask. ImmediatelySubmit remains required. The dashboard design is unchanged, and drawing mutations dispatch to the chart thread.

News guards use the current-week ForexFactory USD feed. Red-only, ten-minute total blackout and cost-covered BE are defaults; news flattening is off. Missing/stale live news blocks fresh entries. Analyzer and Playback do not have a dated historical news feed; use News Off for the frozen parity test. Costs affect sizing and stop coverage rather than directly deducting Analyzer commissions.

Another strategy may trade the same account/contract. RBE never adopts total account position or cancels foreign orders. The durable recovery key uses account, exact contract and direction, independent of chart ID. State is automatically stored under the NinjaTrader user-data RangeBreakoutNT8/recovery folder; keep that runtime state when moving an active lifecycle to another machine.

Recovery persists both books, initial/current stops, consumed sides, owned intent/order IDs and processed executions. A replacement instance with unsettled saved ownership uses account-API recovery on every account. It skips native historical orders, restores the exact owned broker objects and preserves tighter accepted stops. Missing or ambiguous evidence remains pending. Historical reports and non-recovered instances retain native execution. Historical recovery-design documents describe the superseded bootstrap path; see the current contract below.

KeepRunning handles a surviving executor's connection outage; order errors retain StopCancelClose. Broker-accepted hard stops can survive an outage, subject to provider policies. Client trailing, news actions and timed exits need a connected, running strategy. Chart removal and NT8 global order-cancellation policies must be tested before relying on recovery.

The frozen parity comparison and remaining source-data gaps are preserved in [VALIDATION_CHECKPOINT.md](validation/VALIDATION_CHECKPOINT.md). No parameter optimization was performed during these repairs.

## Recovery

See [dynamic recovery and native limitations](validation/DYNAMIC_RECOVERY_2026-10-15.md) and the [mandatory coding contract](../CODING_RECOVERY.md).

When a journal contains an active book or unsettled order, recovery subscribes to account events before reading the broker snapshot and retries missing/Unknown evidence once per second. It does not stage historical entry seeds, submit copies of protection, or rely on native GetRealtimeOrder adoption. Every recovered order must match the saved account, contract, owner/name, broker ID, type, quantity, prices and accounted fills. Sell/SellShort and Buy/BuyToCover are accepted as provider aliases for the same transaction direction; opposite directions remain invalid.

The saved books and original risk/trailing state are restored first, then exact broker order objects are registered with their processed fill counts. This recovered instance uses account CreateOrder/Submit/Change/Cancel and account execution callbacks for its remaining lifetime. Account net position is only a consistency check. New entries, changes and quantity-dependent exits remain blocked while evidence is incomplete. The existing broker stop is not replaced during handoff. Removing the chart unsubscribes callbacks and keeps durable ownership and account-owned protection.

Recovered account orders may have a blank native Strategy column and native strategy Position/SystemPerformance do not represent this recovered book. Use the RBE panel, journal and audit for its owned lifecycle. No account-wide cancel/flatten or manual confirmation field is used.

A previously failed native startup can leave a duplicate stop with the same name but another broker ID. A live conflicting copy blocks recovery; it is never adopted or automatically cancelled. Only a terminal, unfilled different-ID copy is ignored. Do not delete or alter the original journal to bypass a conflict.

Verification: `validation/test_account_recovery_bridge.py`, `test_live_recovery.py`, and the shared `validation/test_broker_action_normalization.py`, plus the full installed-assembly build. Broker/VPS chart replacement, trailing, partial-fill and disconnect acceptance are separate from these fixture/build checks.

## Audit file fix (2026-10-31)

The strategy created a folder named after its source root, with files such as `RBE<guid>.csv` inside, on every Configure. The audit writer used a hard-coded path on one machine, and each run created a new GUID-named file. Saved instances with `WriteAudit=true` from earlier builds repeated this.

- The audit writer is removed from this build. A saved `WriteAudit=true` is ignored and prints one notice. No CSV or folder is created.
- Live recovery records are unchanged and remain under `Documents/NinjaTrader 8/RangeBreakoutNT8/recovery`. Do not delete them to clear the folder issue.
- Delete any old `RBE*.csv` files and the leftover folder from the strategy directory by hand; the strategy no longer creates them.

Not compiled here. Check: load an instance with a saved WriteAudit=true, run it, and confirm no new file or folder appears in the strategy directory.

## Analyzer run is silent because strict risk skips every entry (2026-11-01)

The Analyzer was not stopping at startup. Output showed all 2.4 million minutes processed (2020-01-01 to 2026-10-29), then termination. Every entry was skipped, silently, by strict modeled risk:

- Instrument GC ($100 per point), risk $500, initial stop 0.6% of price, modeled friction $23.
- One GC contract needs about $953 (2020) to $2,513 (2026) of risk budget. `Quantity` returns 0, so the skip counter increments and nothing is printed.
- The skip is now printed (first five, then counted), a startup line warns when the loaded prices make one contract exceed the budget, and Output ends with `Analyzer run summary: N minutes; E entries; S risk skips`.
- To trade: use MGC (10 oz, about $96 to $252 per contract at the same stop), or raise Risk above the figure printed in the warning. Strict risk was not loosened.
- The 480-line progress listing is reduced to the first minute and every 500,000 minutes.

Not compiled here. Check: Output shows the startup WARNING for GC, `RISK SKIP` lines, and the final summary. On MGC with $500 risk, the summary should show entries greater than zero.

## Rebuild with restored fixes, session-roll settling, fixed contract (2026-11-01)

- **Restored fixes.** Three earlier fixes were missing from the previously delivered build, because later patches were applied to the original upload instead of the patched file: the audit-writer removal, Analyzer news forced Off, and the Analyzer open-net-book transition. All three are reapplied. The audit writer was the source of the recurring `2. RBE_NT` folder and `RBE<guid>.csv` files: it ran on every Configure, including each NinjaTrader launch with a saved instance. After compiling this build, delete the old folder once; it is not recreated. Live recovery files remain under `Documents/NinjaTrader 8/RangeBreakoutNT8/recovery`.
- **Session roll no longer aborts the Analyzer.** `NET_ERROR Prior session has unsettled owned exposure or orders` ended the run when anything was still open at the 17:00 NY roll. Realtime already closed such exposure first and deferred the new session; historical runs now do the same. The first occurrence prints `Session roll ... settling it before the new session` with the executor state (net position, book legs, closing/reconciling flags, pending order names and states). If the exposure is still not settled after 240 quotes the run fails with that same state text, so the cause is visible instead of silent.
- **Enable use of fixed contract** (new, group 1. Risk and direction). When on, every entry uses `Fixed contracts` and ignores Risk per trade, Enforce risk limit and Maximum contracts for sizing, whatever their values. The executor's cap check uses the larger of Maximum contracts and Fixed contracts. Default is off. The recovery settings fingerprint is unchanged.

Not compiled here. Checks: (1) Output shows no `WriteAudit` file and no new `2. RBE_NT` folder after a restart; (2) a GC run with fixed contract on shows `FIXED CONTRACT mode` in the banner and entries greater than zero in the summary; (3) a run that previously failed at the roll now prints the `Session roll` line and continues, or fails with a state line.

## Historical entry rejected by NinjaTrader (2026-11-01)

A run reached 2023-07-24 and stopped with `An order has been ignored since the stop price '1964.8' ... is invalid based on the price range of the bar`, then `NET_ERROR Unmanaged Entry returned no order`. The local stop-validity guard had passed, so NinjaTrader's own historical bar-range rule is stricter than the guard.

- A refused historical entry no longer fails the run. The side is treated as already crossed for that session (the same rule used for a level crossed during a gap) and no trade is taken on it. Live and recovery behaviour is unchanged: a missing order there still fails closed.
- The first ten occurrences print `Historical entry ignored by NinjaTrader` with the stop, the current bar high/low/close, the previous bar high/low and the range. The run summary reports how many entries were ignored. Send those lines if the count is more than a handful: they identify the exact rule so the guard can be corrected instead of skipping trades.
- The earlier `Session roll ... settling` message at 2020-10-25 18:00 NY showed a short still open with `cutoff=False`: the 11:55 NY cutoff never fired that session, most likely because the one-minute data has a gap after Friday's open. The position was closed at the first quote after the gap.

Not compiled here.

