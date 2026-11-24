# NoiseBandMomentum — model and implementation

| | |
|---|---|
| File | `NoiseBandMomentum.mq5` (shell) |
| Modules | `StrategyEngine.mqh` (session, signal, sizing), `ExecutionRuntime.mqh` (orders, exits, trailing) |
| Magic | `260601` |
| Timeframe | M30 fixed (`#define TF PERIOD_M30`), independent of the chart timeframe |
| Instruments | any US index CFD the broker names in `InpSymbols` (default `NAS100,SP500`) |
| Direction | long and short, symmetric |
| Positions | at most one per symbol per EA instance, no pyramiding, no averaging |
| Take profit | none — exits are time-based and trailing |
| News filter | none |
| Visuals | none (this EA draws nothing, so it has no `ChartVisuals.mqh`) |
| Clock | standard (`CLK-CORE` 1.2 in `StrategyEngine.mqh`, `CLK-ADAPTER` 1.2 in `ExecutionRuntime.mqh`); the session is stated in New York time, never in server hours |

---

## 1. The idea it trades

After the New York cash open, an index does not immediately pick a direction: it wanders inside a
**noise band** whose width grows with the square root of elapsed time, because that is how a random
walk's dispersion grows. A move that stays inside that band is noise. A move that leaves it is
information, and the model bets that it continues into the session's close rather than reversing.

The band is measured in units of current volatility (ATR), not in points, so the same `k` means the
same thing on NQ, on ES, or on a quiet Tuesday versus a CPI Wednesday.

This is a **session-continuation / breakout-of-noise** model, not a mean-reversion model and not a
stop-hunt detector. It deliberately holds nothing overnight: the edge is intraday continuation, and
an overnight gap has nothing to do with it.

The header cites the research lineage (Zarattini, Aziz & Barbon 2024; Chuk 2026). Nothing in the
implementation depends on that — the rule below is complete on its own.

## 2. The rule, exactly as implemented

All times are **New York wall time**, resolved through the clock adapter. `open` is
`InpOpenNYMinute` (default 570 = 09:30 NY) and `TF = M30`. No server hour appears anywhere in the
EA, so the same inputs mean 09:30 New York on every broker.

**Reference.** The close of the M30 candle that *ends at* the open — the last print before the
session's first half hour. In code this is `iClose(sym, TF, 1 + K)` at checkpoint `K`; that shift
always lands on the same pre-open candle, it does not drift with `K`.

**Checkpoints.** A checkpoint is the close of each M30 candle that opens at `open + (K-1)·30 min`,
for `K = 1 … InpCheckpoints` (default 11, so the last checkpoint closes 5.5 h after the open).
Evaluation happens once per new M30 candle, on the first tick after it closes, and only when that
candle is *the* candle that just closed (`iTime(0) - iTime(1) == 30 min`). Without that guard a data
hole leaves the newest closed bar hours old and the EA acts on a stale signal outside the session —
on USTEC 2024.05.27 there were no M30 bars between 20:00 and 01:00, and checkpoint 7 fired at 18:00
New York.

**Signal at checkpoint K**

```
ATR      = ATR(InpAtrPeriod) of M30, read at shift 1 (the candle that just closed)
move     = (close(K) - reference) / ATR
threshold = round_to_0.05( k · sqrt(K) )        k = InpBandK (default 1.4)

move >  threshold  -> buy
move < -threshold  -> sell
otherwise          -> no trade
```

Three details that matter:

* **`sqrt(K)` scaling.** The band widens with the square root of the number of half hours elapsed,
  so a breakout is judged against the dispersion *available* at that moment. Without it, early
  checkpoints would almost never fire and late ones would fire constantly.
* **Threshold rounding.** The threshold is rounded to 0.05 ATR (`MathRound(x*20)/20`) so that the
  decision is stable and reproducible rather than sitting on a floating-point knife edge.
* **Strict inequality.** Equality is not a signal.

**Entry.** Market order at the checkpoint, no limit and no pullback wait. The initial stop is
`InpStopAtr · ATR` (default 2 ATR) from the fill quote; there is no take profit.

**Exit, in this priority order, on every tick**

1. **Session close.** Close when the server hour reaches `InpCloseHour` (default 23) or when the
   position's entry day differs from the current day. Nothing is carried overnight.
2. **Maximum holding time.** Close after `InpMaxBars` M30 candles (default 20) have elapsed since
   the entry candle.
3. **Trailing stop.** From `InpTrailStartR` R of profit (default 1 R, where 1 R is the initial stop
   distance), follow the best price reached at `InpTrailAtr · ATR` (default 2 ATR), updated at most
   once every `InpTrailSeconds` (default 300 s) and only in the profitable direction. The stop is
   never loosened and never moved behind the entry from the wrong side.

## 3. Sizing

```
risk_cash = AccountInfoDouble(ACCOUNT_BALANCE) · InpRiskPercent / 100      (default 1 %)

loss_per_lot = |OrderCalcProfit(BUY, 1.0 lot, quote, quote - stopDist)|
               (fallback: stopDist / tickSize · tickValue if OrderCalcProfit fails)

lots = floor( min(risk_cash / loss_per_lot, VOLUME_MAX) / VOLUME_STEP ) · VOLUME_STEP
```

* `OrderCalcProfit` prices the loss in the **account's own currency**, so the sizing is correct on a
  USD account, a EUR account and on any cent account without a factor. Nothing here assumes USD.
* If the computed size is below `SYMBOL_VOLUME_MIN`, `InpAllowMinLotOverride` (default `true`)
  decides once for the EA, the same volume rule every EA in the book uses:
  * `true` — take the **broker minimum** and log `MIN_LOT_OVERRIDE … lots=… estimatedRisk=…
    intendedRisk=…`. On a cent account with a tight stop this is the normal case, not an error; read
    that line before concluding the risk is what you set.
  * `false` — drop the signal and log `RISK_BELOW_MIN_LOT budget=… < broker minimum … lots`, for an
    account where the intended risk is a hard limit rather than a target.
* Sizing is percentage-of-balance only, so it needs no money-unit declaration: there is no
  fixed-cash input to express in a denomination, and `OrderCalcProfit` already answers in the
  account's own currency. Same convention as the other EAs, minus the unit inputs their
  cash-denominated settings need.
* The EA never trades a size it could not size: if inputs or the broker's volume contract are
  invalid, the signal is dropped with an explicit line instead of being sent at a guessed size.

## 4. Restart and recovery behaviour

A restart must not restart the trade, so the per-symbol state that cannot be reconstructed from
the position is persisted to terminal `GlobalVariables`, keyed `NBM_<magic>_<symbol>_<field>`:

| Field | Key suffix | Why the position cannot supply it |
|---|---|---|
| entry time | `entry` | the position gives the fill time, not the checkpoint candle the rules use |
| initial risk (1 R) | `risk` | `POSITION_SL` moves with the trail; the original distance is gone |
| best price | `best` | the high-water mark since entry is stored nowhere |
| last trail update | `trail` | the throttle timestamp is memory only |

Written on entry, on every new best price and on every stop modification; deleted when the position
closes, so a later trade on the same symbol can never inherit it. A restored trade therefore trails
from the true best price: a position that had run 3 R resumes trailing at 3 R, not at 1 R.

Fallback, and the only case where the old behaviour remains: when no saved state exists (first run
after this upgrade, or a deleted data folder) the EA rebuilds `entryTime`/`stopDist`/`best` from the
position and logs `NBM_STATE_NEW … re-armed trailing at the entry price`. That is a one-time
degradation, never a silent one.

Session-close and max-hold exits are unaffected either way, because both derive from the entry
candle, which is recovered exactly.

Coverage, stated honestly: the save path runs on every entry and every trailing update (192 round
trips in the reference year) and the build compiles clean, but MetaTrader's strategy tester cannot
restart an EA mid-trade. The restore path is exercised only by a live/demo restart — do that once on
the target account before trusting a long-running deployment.

Ownership is `symbol + InpMagic`. There is no adoption of foreign positions, no netting logic and no
partial-close handling: this EA opens one position and closes it as a whole.

## 5. Inputs

| Input | Default | Meaning |
|---|---|---|
| `InpSymbols` | `NAS100,SP500` | Comma-separated list; each symbol is selected in Market Watch, gets its own ATR handle and its own position. The chart symbol is irrelevant — attach the EA anywhere. |
| `InpOpenNYMinute` | `570` | Session open in **minutes after New York midnight** (570 = 09:30 NY) — a New York wall time, not a server hour. |
| `InpCheckpoints` | `11` | Number of half-hour checkpoints; 11 = evaluation until +5.5 h. |
| `InpCloseNYMinute` | `960` | New York minute from which positions are closed (960 = 16:00 NY, flat into the close). A New York date change closes them too. |
| `InpBandK` | `1.4` | Band width. Lower = more trades and weaker ones; higher = fewer, stronger. |
| `InpAtrPeriod` | `14` | ATR period on M30. |
| `InpStopAtr` | `2.0` | Initial stop in ATR (also the definition of 1 R). |
| `InpTrailAtr` | `2.0` | Trailing distance in ATR. |
| `InpTrailStartR` | `1.0` | Profit in R at which trailing begins. |
| `InpMaxBars` | `20` | Hard exit after this many M30 candles. |
| `InpRiskPercent` | `1.0` | Risk per trade as a percentage of **balance** (not equity). |
| `InpAllowMinLotOverride` | `true` | `true`: take the broker minimum when the budget is below it and log the real risk. `false`: skip the signal instead. |
| `InpMagic` | `260601` | Ownership tag. |
| `InpSlippage` | `30` | Max deviation in points. |
| `InpTrailSeconds` | `300` | Throttle between trailing-stop modifications (broker-friendly). |
| `ClockMode` | `CLK_MODE_AUTO` | Standard clock: `AUTO` uses the registry profile, else live/evidence inference; `MANUAL` uses the three inputs below. |
| `ManualDstRule` | `CLK_RULE_US` | `MANUAL` only: the broker's server follows US DST, EU DST, or a fixed offset. |
| `ManualBaseMinutes` | `120` | `MANUAL` only: server minus UTC in standard time, in minutes. |
| `TesterClockAnchor` | `CLK_ANCHOR_AUTO` | `AUTO` proves the absolute base from weekly open stamps; `OFF` requires a registry profile. |
| `ClockEvidenceSymbol` | `""` | Symbol whose history proves the DST rule (`""` = the chart symbol). |

## 6. Limitations, stated plainly

1. **The session depends on the clock being resolvable.** The session is stated in New York time
   and the adapter supplies the server→UTC mapping, from the registry profile, from the price
   evidence, or from the `MANUAL` inputs. If none of them can prove the mapping the EA does not
   guess: it logs `CLK_*`, refuses to trade, and in the tester removes itself. In the tester the
   absolute base must be anchored (`TesterClockAnchor=AUTO`), which is why the reference run logs
   `CLK_ASSUMPTION US-DST +120m [ANCHORED]`.
2. **Balance-based sizing.** Risk is recomputed from balance on every signal, so a winning streak
   increases size and a losing streak decreases it. Equity-based sizing (which also accounts for open
   risk) is not implemented.
3. **No news awareness.** A checkpoint that lands inside an FOMC release will trade like any other.
   This EA is for testing the session-continuation edge, not for production news governance.
4. **The restart path is persisted, not reconstructed.** `best`, 1 R and the entry candle survive a
   restart through terminal `GlobalVariables`; only a missing state file degrades to entry-price
   trailing, and it says so in the log (section 4).
5. **One position per symbol, no re-entry after a stop-out** on the same day beyond the checkpoint
   schedule: after an exit, a later checkpoint may open a new trade, but there is at most one at a
   time per symbol.

## 7. Testing it

* Strategy Tester: `Symbol=USTEC` (or your broker's name), `Period=M1` or `M30`, `Model=1` is enough
  for direction and trade counts; use `Model=4` when tick precision matters. The EA decides on M30
  closes, so a candle-model run reproduces the same decisions.
* Give the test enough warm-up: it reads `ATR(14)` on M30 and up to 12 candles back for the
  reference, so the first day of an empty history will not signal.
* Sanity checks worth running once per broker: (a) the first trade of a day appears on the first
  tick after a checkpoint close and never between them; (b) no position survives past
  `InpCloseHour`; (c) the log line `BUY/SELL at checkpoint K: move … threshold …` matches what you
  can recompute by hand from the chart at that timestamp.
* There is no `.set` preset in this folder yet: the defaults above are the documented run.
* **Clock-migration parity, 2024.01.02–2024.12.31, USTEC M1, `Model=1`, deposit 25 000 USD.** The
  pre-migration build (server-hour inputs `InpOpenHour=16`, `InpOpenMinute=30`, `InpCloseHour=23`)
  and 1.20 (New York inputs `InpOpenNYMinute=570`, `InpCloseNYMinute=960`) were run from the same
  `.ini` and compared trade by trade:

  | | baseline 1.10 | 1.20 |
  |---|---|---|
  | round trips | 192 | 188 |
  | deals | 384 | 376 |
  | final balance | 33 277.49 | 34 162.15 |

  * Session boundary: the first entry of the day has the **same clock time on all 159 trading days**.
    The tester broker's server is genuinely New York + 7 h with US DST, so the hard-coded 16:30 had
    been right by coincidence, not by construction.
  * 188 trades are common to both runs. 130 are identical in entry time, exit time, exit price and
    lot. 58 differ **only in lot size**, because the removed trades moved the balance the sizing
    reads. **No trade differs in entry time, exit time or exit price.**
  * 4 entries exist only in the baseline, all at `01:00:00` server: `2024.05.28`, `2024.07.04`,
    `2024.12.02`, `2024.12.26`. Each is a stale-checkpoint entry taken after a data hole, hours
    outside the session; the fresh-bar guard in 1.20 refuses them. No entry was added.

  The two deal lists are kept beside this file: `nbm_baseline.csv` (1.10) and `nbm_after.csv`
  (1.20), as captured from the tester agent log.

## 8. Change log

| Version | Change |
|---|---|---|
| 1.20 | Session moved to New York time through `CLK-CORE`/`CLK-ADAPTER` 1.2 (`InpOpenNYMinute` 570, `InpCloseNYMinute` 960) — no server hour remains. Restart state (entry candle, 1 R, best price, trail throttle) persisted to `GlobalVariables` and cleared on close, so a restart resumes trailing at the true best instead of re-arming at the entry. `InpAllowMinLotOverride` (default `true`) applies the standard volume rule. Fresh-bar guard refuses a checkpoint read from a stale bar after a data hole. Parity vs 1.10 over 2024: 188 common round trips, 0 differing entry/exit times or prices, 58 volume-only differences, 4 stale entries removed, 0 added. Compiles 0/0; `clk_verify` PASS. |
| 1.10 | Split the single-file build into shell + `StrategyEngine.mqh` + `ExecutionRuntime.mqh`. Logic copied verbatim: identical signals, exits, trailing arithmetic and log text. No behaviour change; compiles 0 errors, 0 warnings. |
| 1.00 | First release. |
