# NT8 port gate — 2026-10-05

Status: port candidate. Native project compilation and deterministic calculations
pass. Native runtime, platform parity and live readiness are unproven.

## Frozen scope

Appendix entries/median, C1 only, no trailing/BE. Default 1% risk, rolling last
20 price-R values, half risk at <=-4R, restore above -4R. Optional fixed cash
risk follows the same brake. News OFF by default; configurable five-minute lead.
USDJPY is the source comparison; native 6J is a separately labeled adaptation.
Source parity uses IC NY+7 timestamps. No inspected years are relabeled unseen.

## Completed proof

- Full installed NinjaTrader.Custom.csproj Release build: exit 0, zero errors,
  746 project warnings (primarily installed vendor/source type conflicts).
  This is a build against native NT8 assemblies, not a DataLoaded/Analyzer run.
- C# model fixture: 61,390 checks, zero failures. Prior observed-session median,
  minimum box count, appendix buffers, one consumed trigger, inclusive brake
  and recovery, 3-to-2-bar right anchors, USDJPY cash conversion, 6J point value,
  hourly 2020–2026 UTC/NY conversion and explicit DST transitions.
- C# calendar fixture: eight checks, zero failures. Coverage endpoints, earliest
  pre-12:00 event, unfetched live feed unavailable, diagnostic coverage rejection
  and event outside declared coverage rejection. Test-only temporary files were
  removed; no fabricated historical archive was installed.
- Comparison utility syntax passes. It has NOT been run against native NT8
  trades, because no TokyoCoil Analyzer run has been completed.
- Read-only review found managed-entry incompatibility, stale-first-quote exit
  delay, wrong-week news acceptance and asynchronous OCO race handling. Adapter
  now uses unmanaged OCO, per-fill stops, acknowledged cancellation before close,
  clock-driven live deadlines, payload-week validation and owned net fail-close.
  These changes still require native order-lifecycle tests.

## Source identity

TokyoCoilModel.cs SHA256:
5B0DB9BDCBF3D0BB6FCAF0D7CA8484AE03D33A643BF5BA99E1D683B81A051A78

TokyoCoilNews.cs SHA256:
2098680277FFBFD23C4890E220C300D7596F3B8C73CDBC58E8ECC663B4D561B5

TokyoCoilNT8.cs SHA256:
C1A02BBDBC1D8C1585E61270B5D7433EEADCDA3383E2EFEF505D486F670DE292

## Next gates, in order

1. Load the compiled strategy in NT8. Frozen-default USDJPY diagnostic first:
   September 2020 with sufficient warmup, then the requested 2020–2025 matrix.
   Reconcile M1 bars, observed sessions, spread, armed levels, tick order,
   direction, fill time/price, original stop, exit and cash sizing. The existing
   MT5 September control contains eight trades; it is a regression fixture,
   not evidence of an edge. Use compare_mt5.py only on USDJPY.
2. Fail on first unexplained difference. NT8 Last ticks cannot silently stand
   in for MT5 bid/ask generated ticks. Historical Forex quote semantics, native
   stop trigger/fill conventions, financing and commission remain open.
3. Native 6J contract-specific audit and Analyzer/Playback cases: entry OCO,
   partial fill, initial stop, cancellation race, stop versus timed exit,
   opposite-side late fill, rejection, reconnect at cutoff/12:00, restart,
   account/instrument ownership and simultaneous instances. Same-account,
   same-instrument overlapping positions need coordination before deployment.
4. Inspect chart screenshots for panel occlusion, anchors, synthetic/broker
   distinction and completed 12:00 M1 references. No new screenshot proof yet.
5. News ON historical work requires the complete, audited 2020–2026 calendar;
   weekly ForexFactory live JSON is not that archive. Actual live retrieval,
   stale/malformed/current-week payload cases remain native runtime gates.
6. Only after parity, costs and 6J risk feasibility: frozen historical robustness,
   Sim forward run and the Tradeify Growth SOP. No payout forecast is supported
   by these implementation checks.

Do not enable this candidate on a funded/live account yet. No live orders were
submitted during this port work.
