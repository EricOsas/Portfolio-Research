# Tuesday Turnaround MT5

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
