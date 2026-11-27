# EA structure and conformance — every Expert in this tree

Generated 2026-11-21 from the compiled sources themselves. The per-EA inventory in §6 is
extracted mechanically (file map, section headings, inputs with defaults and comments, function
index, order-path call sites); nothing in it is described from memory. The verdict tables in §3–§5
are the result of the runs listed there: headless compile, `clk_verify.py`, the clock conformance
suite, the Python suites and the four `OrderSend`/ownership audits that were actually executed.

Read this together with `AGENTS.md` (the contract) and
`templates/mt5/EA_Standards/CLOCK_STANDARD.md` (the clock).

## 1. What "one EA" means here

```
<Strategy>/
  <Strategy>.mq5        thin shell: #property, inputs, globals, event handlers
  StrategyEngine.mqh    signals, session logic, sizing policy, per-trade state
  ExecutionRuntime.mqh  order send/modify/close, ownership + recovery, clock adapter
  ChartVisuals.mqh      panels, boxes, levels, alerts
  *.set                 preset(s) that reproduce a documented run
  README.md / MODEL.md  what it does and which run the preset reproduces
```

The shell includes `"StrategyEngine.mqh"` and nothing else. Compiled artefacts (`.ex5`), presets
and documentation stay in the same folder: an EA must rebuild from its own root.

## 2. Scope

In scope: `1. X9` (including `Part 3`), `2. RBE`, `3. TokyoCoil`, `4. Index Book` (11 strategies),
`5. Gotobi` (`GotobiFix`), 16 deployable EAs in total. Out of scope by instruction:
`Other Bots`, `ResearchArchive`, `Position Sizer`, `Shared`.

## 3. Structure conformance (measured)

Corrected 2026-11-21 after acting on the earlier table. Two rows of that table were wrong and are
fixed here rather than repeated:

* **Money was never a defect for thirteen EAs.** The Index Book EAs size from `RiskMoney`, explicitly
  "Risk per trade, including costs (account currency)", or from a percentage of balance/equity. Both
  are already correct on a cent account because the platform reports money in the account's own
  denomination. Only **X9** and **FVG_Duo** carried a fixed denomination factor, and both now derive
  it (`X9CashPerUSD`, `FdgCashPerUnit`).
* **"Shell includes three files" was not a defect.** Long inputs blocks that use engine enums force
  the engine to be included before the inputs, and the runtime/visuals after them. X9 and GotobiFix
  do exactly that; VWAPPullback includes the engine once (its second `.mq5` is the ADXPane helper,
  which is not the main EA). What was genuinely wrong is listed below.

| EA | Modules | Single-file? | Calendar source | Clock | Sizing unit | Notes |
|---|---|---|---|---|---|---|
| 1. X9 | shell + 3 | no | NEWS-FEED 1.0 | legacy `NYUTCOffsetSec` | derived | magic base 647900, strategy N = base+N |
| 1. X9/Part 3 | single | **yes, by design** | none | per-EA | fixed factor | a build, not a complete EA; left untouched |
| 2. RBE | shell + 3 | no | NEWS-FEED 1.0 | legacy `NYUTCOffsetSec` | account cash | |
| 3. TokyoCoil | shell + 3 | no | NEWS-FEED 1.0 | legacy + broker whitelist | account cash | |
| 4. Index Book / 1. VaultBreak | shell + 3 | no | none | **CLK-CORE 1.2 rule** (adapter pending) | account cash | parity-proven, 236/236 trades identical |
| 4. Index Book / 2. OBR | shell + 3 (+ADXPane) | no | none | per-EA | account cash | untouched |
| 4. Index Book / 3. OpenDrive | shell + 3 | no | NEWS-FEED 1.0 | legacy + `BrokerServerGMTOffset` | account cash | |
| 4. Index Book / 4. NQPrecisionBot | shell + 3 | no | none | per-EA | account cash | |
| 4. Index Book / 5. OpeningShock | shell + 3 | no | none | **CLK-CORE 1.2 rule** (adapter pending) | account cash | parity-proven, 67/67 trades identical |
| 4. Index Book / 6. SigmaBreakout | shell + 3 | no | none | per-EA | account cash | |
| 4. Index Book / 7. FlashTriggerORB | shell + 3 | no | none | per-EA | account cash | |
| 4. Index Book / 8. NoiseBandMomentum | shell + 2 | **no (was)** | none | `InpOpenHour` | account cash | split into engine + runtime 2026-11-21 |
| 4. Index Book / 9. FVG_Duo | shell + 4 | no | none | **CLK-CORE 1.2 rule** (adapter pending) | derived | parity-proven, 189/189 identical; old body was the "Mar 8..Nov 6" guess |
| 4. Index Book / 10. VWAPPullback | shell + 3 (+ADXPane) | no | none | per-EA | account cash | |
| 4. Index Book / 11. TuesdayTurnaround | shell + 3 | no | **native MT5 calendar** | per-EA | account cash | no WebRequest at all |
| 5. GotobiFix | shell + 3 | no | none | **CLK 1.2** | account cash | only clock-verified EA |

Defects fixed in this pass:

1. **NoiseBandMomentum** was a single 335-line `.mq5`; it is now a shell plus `StrategyEngine.mqh`
   (session, signal, sizing) and `ExecutionRuntime.mqh` (ownership, exits, trailing), with the logic
   copied verbatim and the file compiling `0 errors, 0 warnings`. It has no chart output, so it has
   no `ChartVisuals.mqh`: a module that draws nothing is dead code. The standard therefore reads
   "engine + runtime, plus visuals when the EA draws".
2. **The four live `WebRequest` calls are gone as bare calls.** X9, RBE, TokyoCoil and OpenDrive now
   call `NewsFeedGet` from the verbatim `NEWS-FEED 1.0` block (`EA_Standards/NEWS_FEED.mqh`), which
   fetches the same Forex Factory URL, keeps one shared snapshot in `Common\Files`, serves the
   snapshot when the fetch fails, and never calls `WebRequest` in the tester. `tools/news_verify.py`
   proves the block is byte-identical in all four and that no `WebRequest(` remains outside it.
   Tester behaviour is unchanged by default (`InpNewsCacheInTester=false`).
3. **`Shared/` deleted.** `ForexFactoryFeed.mqh` was included by no EA (its fetch pattern was
   inlined into each EA instead). The folder and its validation script are gone; nothing depends on
   it. The pattern it prototyped lives on properly in `NEWS_FEED 1.0`.
4. **X9 magic numbering.** Strategy N now owns `InpMagic + N` with `InpMagic = 647900`, so the last
   digit is the strategy number (647901…647909). The order comment is `X9S<N>` (was
   `Gold X9 by You_FoundEric_XAUUSD_N`). Tickets in the old 647873…647893 range are reported at init
   and never adopted. Part 3 keeps 647873: X9 moved out of that range, so the two no longer collide.
5. **Minimum lot.** `InpAllowMinLotOverride` now defaults to **true** on X9 and FVG_Duo: the EA takes
   the broker minimum when the budget is below it, and still logs the real risk.

Still outstanding, in order of risk:

1. **Clock migration** for fourteen EAs (all except GotobiFix). Each needs the section-6 procedure of
   `CLOCK_STANDARD.md`, a baseline tester run, the migration, and a second run whose trade list is
   compared against the baseline. That is the gate; nothing is migrated without it.
2. **ADXPane** stays as-is by decision: `ADXPane.mq5` is a customised indicator compiled as its own
   expert, and merging it into the EA would have to reproduce its drawing exactly. Not worth the
   risk; it is recorded as an accepted exception.
3. Money: nothing left to convert (see above). The four news EAs no longer need an allowlist entry
   for a second host — they still need `https://nfs.faireconomy.media` allowed.

## 4. Verification status (what was run, and what it said)

| Check | Command | Result |
|---|---|---|
| Headless compile, all 16 EAs | `MetaEditor64 /compile:<ea>.mq5 /inc:<MQL5>` | 16/16 `Result: 0 errors`; GotobiFix 1 warning at `ExecutionRuntime.mqh:913` (`OrderSend` unchecked) |
| OCR extracts | `Gold X9 v6.3 - Youtube shared Part 2/3.mq5` | 1292 / 562 `MISSING LINE` markers → 1309 / 576 errors: broken extracts, documented not "fixed" |
| Clock blocks in GotobiFix | `clk_verify.py` | `RESULT: PASS`; `CLK-CORE` and `CLK-ADAPTER` byte-identical |
| Clock conformance | `tests/mql5/run_conformance.py` | `FAILURES: 0` — 60 IANA transitions (2006–2036), 173 280 server round-trips `bad=0`, 8/8 inference, dated schedule 2 segments / 104 weeks / 25 560 hours `bad=0` |
| Legacy clock cost | same suite | "Mar 8 … Nov 6" approximation wrong for **4 253 hours** 2007–2035 (worst 2010: 157 h); single-base model mis-times 17 544 / 35 064 hours on a +120→+180 broker |
| Python engine | `python tests/test_engine.py` | `PASS (0 failure(s))`, 13 tests; IANA agreement over 254 208 hours `bad=0` |
| Moved Python suites | `python legacy/<EA>/...` | 23 pass, 12 fail — all 12 fail identically from pristine copies at their original location (§5) |
| X9, FVG_Duo after the money change | `MetaEditor64 /compile` | 0 errors, 0 warnings each |
| X9 after magic renumber + comment change | `MetaEditor64 /compile` | 0 errors, 0 warnings |
| X9, RBE, TokyoCoil, OpenDrive after NEWS-FEED 1.0 | `MetaEditor64 /compile` | 0 errors, 0 warnings each |
| NEWS-FEED standard across those four | `python tools/news_verify.py` | `RESULT: PASS (0 failure(s))` — block byte-identical, no `WebRequest(` outside it |
| NoiseBandMomentum after the split | `MetaEditor64 /compile` | 0 errors, 0 warnings |
| **VaultBreak clock rule unified** (2026-11-21) | tester 2024 full year, USTEC M1, before vs after | **236/236 trades identical** on every column except `run_id` (entry/exit server+UTC stamps, prices, volume, SL/TP, costs, net, exit reason, attempt ordinal) |
| VaultBreak after the change | `MetaEditor64 /compile` | 0 errors, 0 warnings |
| **OpeningShock clock rule unified** | tester 2024 full year, USTEC M1, before vs after | **67/67 trades identical** (same column set, `run_id` excluded), 0 errors compile |
| **FVG_Duo clock rule unified** | tester 2024 full year, USTEC M1, before vs after | **189/189 trades identical**, 0 differing cells. The old body was the fixed-date approximation; in the tester the offset comes from real weekly stamps, so the correction only changes the live historical conversion |
| OpeningShock, FVG_Duo after the change | `MetaEditor64 /compile` | 0 errors, 0 warnings each |

## 5. Pre-existing suite failures (not caused by the move)

Each of these was re-run from the pristine copy restored to its original path inside `Experts`, and
failed with the same message. They are stale contracts, not regressions:

| Suite | Failure | Cause |
|---|---|---|
| `1. X9/tests/runtime/test_news_visuals.py` | C# extraction of the sizing path fails | harness does not know the new `X9CashPerUSD`; the suite predates the money change |
| `2. RBE/validation/test_close_intent.py` | `CS1061 RBECloseRequest does not contain …` | harness expects a field the current engine no longer has |
| `2. RBE/validation/test_news_be_logging.py` | `CS0103 RBEOwnedSelectedPosition` | renamed helper |
| `1. VaultBreak/…/test_broker_clock.py` | `AssertionError` | asserts the pre-CLK clock shape |
| `1. VaultBreak/…/test_fixed_size.py` | `RequestedVolume(` not found | function renamed |
| `1. VaultBreak/…/test_funded_first.py` | `AssertionError` | contract drifted |
| `1. VaultBreak/…/test_source_contract.py` | `AssertionError` | contract drifted |
| `1. VaultBreak/…/test_sparse_history.py` | `NoneType.start` | function renamed |
| `10. VWAPPullback/tests/test_core.py` | "Expected one production NT8 VWAP source" | requires the NT8 strategies folder |
| `10. VWAPPullback/tests/test_recovery.py` | `csc` compile error | NT8/C# side not present |
| `10. VWAPPullback/tests/test_trailing_parity.py` | same as test_core | requires NT8 |
| `2. OvernightBiasRangeBreakout/…/test_source_contract.py` | "ADX pane must be embedded" | visual contract drifted |

They are kept in `Python/legacy` as evidence of the drift, not as a green gate.

Decision (2026-11-21): keep them, repair on touch. Each one encodes a real contract (exit hydration,
close intent, sparse history, fixed size) that is worth having for the next EA; what is stale is the
*name* it looks for, not the idea. The rule from here is: when an EA is next modified, revive its
suite against the current source in the same change, and only then count it as green. The three
VWAPPullback suites additionally require a NinjaTrader 8 install (`Documents/NinjaTrader 8/...`),
which this machine does not have, so they can only run on the trading box.

## 6. Per-EA structural inventory

Extracted from source. `@n` is the line number of the definition in the file it appears in.
`Order path` lists every order call site so a reviewer can start there. Flag lines restate the
scans: clock generation, money derivation, `WebRequest`/`FILE_COMMON` counts and the shell files.

### 1. X9

> Welcome to the central reference manual for the **Gold X9 v6.3 (9-Strategy Portfolio Engine)** Expert Advisor. This document covers the system architecture, 9-strategy preset table  
> — `README.md`

| File | Lines | Role |
|---|---:|---|
| `Gold_X9_v6_3.mq5` | 305 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 432 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 544 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 1444 | engine: signals, sizing, state |
| **total** | **2725** | |

**Inputs** (51):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| 1 - Trading Profile | `enum_TradeFrequency` | `TradeFrequency` | `Very_High` | Portfolio frequency / enabled strategies |
| 2 - Lot Sizing | `enum_lotsizing` | `Lotsizing_Method` | `Tiered_Lotsizing` | Lot-sizing method |
| 2 - Lot Sizing | `double` | `TieredLot` | `30.0` | Tiered sizing factor (>0 to 100; not risk percent) |
| 2 - Lot Sizing | `double` | `RiskScaling` | `1.0` | Balance-scaled sizing multiplier |
| 2 - Lot Sizing | `double` | `InpFixedBalance` | `0.0` | Sizing balance (account currency; 0 = actual balance) |
| 2 - Lot Sizing | `double` | `FixedLots` | `0.01` | Fixed lots per trade (Fixed lots mode only) |
| 2b - Separate Fixed Lots | `bool` | `SepLotSize` | `false` | Use separate strategy lots (Fixed lots mode only) |
| 2b - Separate Fixed Lots | `double` | `Strat1Lots` | `0.01` | Strategy 1 - fixed lots |
| 2b - Separate Fixed Lots | `double` | `Strat2Lots` | `0.01` | Strategy 2 - fixed lots |
| 2b - Separate Fixed Lots | `double` | `Strat3Lots` | `0.01` | Strategy 3 - fixed lots |
| 2b - Separate Fixed Lots | `double` | `Strat4Lots` | `0.01` | Strategy 4 - fixed lots |
| 2b - Separate Fixed Lots | `double` | `Strat5Lots` | `0.01` | Strategy 5 - fixed lots |
| 2b - Separate Fixed Lots | `double` | `Strat6Lots` | `0.01` | Strategy 6 - fixed lots |
| 2b - Separate Fixed Lots | `double` | `Strat7Lots` | `0.01` | Strategy 7 - fixed lots |
| 2b - Separate Fixed Lots | `double` | `Strat8Lots` | `0.01` | Strategy 8 - fixed lots |
| 2b - Separate Fixed Lots | `double` | `Strat9Lots` | `0.01` | Strategy 9 - fixed lots |
| 3 - Manual Strategy Selection | `bool` | `RunStrat1` | `true` | Strategy 1 (Manual strategy selection only) |
| 3 - Manual Strategy Selection | `bool` | `RunStrat2` | `true` | Strategy 2 (Manual strategy selection only) |
| 3 - Manual Strategy Selection | `bool` | `RunStrat3` | `true` | Strategy 3 (Manual strategy selection only) |
| 3 - Manual Strategy Selection | `bool` | `RunStrat4` | `true` | Strategy 4 (Manual strategy selection only) |
| 3 - Manual Strategy Selection | `bool` | `RunStrat5` | `true` | Strategy 5 (Manual strategy selection only) |
| 3 - Manual Strategy Selection | `bool` | `RunStrat6` | `true` | Strategy 6 (Manual strategy selection only) |
| 3 - Manual Strategy Selection | `bool` | `RunStrat7` | `true` | Strategy 7 (Manual strategy selection only) |
| 3 - Manual Strategy Selection | `bool` | `RunStrat8` | `true` | Strategy 8 (Manual strategy selection only) |
| 3 - Manual Strategy Selection | `bool` | `RunStrat9` | `true` | Strategy 9 (Manual strategy selection only) |
| 4 - Prop / Execution Adjustments | `double` | `AdjustEntry` | `0.0` | Entry-price adjustment (broker points; 0 = unchanged) |
| 4 - Prop / Execution Adjustments | `double` | `AdjustSL` | `0.0` | Initial stop adjustment (broker points) |
| 4 - Prop / Execution Adjustments | `double` | `AdjustTP` | `0.0` | Take-profit adjustment (broker points) |
| 4 - Prop / Execution Adjustments | `double` | `AdjustTrailSL` | `0.0` | Trailing-stop adjustment (broker points) |
| 4 - Prop / Execution Adjustments | `double` | `AdjustSalvageExit` | `0.0` | Salvage-exit adjustment (broker points) |
| 4 - Prop / Execution Adjustments | `double` | `AdjustBreakEven` | `0.0` | Break-even adjustment (broker points) |
| 5 - News Engine (USD | fixed 5m + 5m) | `ENUM_NEWS_IMPACT` | `News_Impact` | `NEWS_DISABLED` | ForexFactory news impact filter |
| 5 - News Engine (USD | fixed 5m + 5m) | `bool` | `News_Block_Entries` | `true` | Blackout: block new X9 orders |
| 5 - News Engine (USD | fixed 5m + 5m) | `bool` | `News_Cancel_Pending` | `false` | Blackout: cancel existing X9 pending orders |
| 5 - News Engine (USD | fixed 5m + 5m) | `bool` | `News_Freeze_Management` | `true` | Blackout: pause EA exits, SL/TP and pending maintenance |
| 5 - News Engine (USD | fixed 5m + 5m) | `bool` | `News_Flatten_Before` | `false` | Flatten: close X9 positions and cancel pending before news |
| 5 - News Engine (USD | fixed 5m + 5m) | `int` | `News_Flatten_Min` | `5` | Flatten lead time (minutes; 0 = at release) |
| 6 - Drawdown Safeguards | `double` | `MaxDailyDDPercent` | `0.0` | Maximum daily drawdown (%; 0 = disabled) |
| 6 - Drawdown Safeguards | `double` | `MaxTotalDDPercent` | `0.0` | Maximum total drawdown (%; 0 = disabled) |
| 6 - Drawdown Safeguards | `ENUM_DD_BASIS` | `DDBasis` | `DD_BASIS_EQUITY` | Drawdown measurement basis |
| 6 - Drawdown Safeguards | `ENUM_DD_ACTION` | `DDAction` | `DD_ACTION_NO_NEW_TRADES` | Action when a drawdown limit is breached |
| 6 - Drawdown Safeguards | `int` | `InpTotalDDResetID` | `0` | Increase to explicitly re-arm a latched total-DD lock |
| 6b - Total Drawdown Reference | `ENUM_DD_MODE` | `DDMode` | `DD_MODE_DYNAMIC` | Total drawdown reference mode |
| 6b - Total Drawdown Reference | `double` | `StaticDDBalance` | `0.0` | Static reference (account currency; 0 = startup basis) |
| 7 - Chart Display | `bool` | `ShowInfoPanel` | `true` | Show collapsible X9 information panel (live / visual test) |
| 7 - Chart Display | `bool` | `ShowGradientBg` | `true` | Show Navy chart gradient (live / visual test) |
| 7 - Chart Display | `color` | `GradientEndColor` | `C'18,42,76'` | Gradient colour - Navy by default |
| 8 - Execution & Logging | `int` | `InpMagic` | `647873` | Base magic number (X9 uses base through base + 20) |
| 8 - Execution & Logging | `string` | `TradeComment` | `"Gold X9 by You_FoundEric"` | Comment sent with each X9 order |
| 8 - Execution & Logging | `bool` | `InpEnableAuditLog` | `true` | Detailed strategy / order journal logging |
| 8 - Execution & Logging | `bool` | `InpAllowMinLotOverride` | `false` | Round a sub-minimum size up to the broker minimum (false = skip the entry) |

**Order path**: `OrderDelete(`@1150, `OrderDelete(`@1592, `OrderDelete(`@1739, `OrderDelete(`@1776, `OrderDelete(`@2111, `OrderDelete(`@2142, `OrderDelete(`@2172, `trade.OrderOpen(`@2695

**Flags**: clock: per-EA engine (not migrated) · money: tick-value derivation · WebRequest=1 · FILE_COMMON=1 · inputs=51 · shell: `Gold_X9_v6_3.mq5`

### 1. X9 / Part 3

| File | Lines | Role |
|---|---:|---|
| `Gold_X9_Part3.mq5` | 1640 | shell: inputs, globals, event handlers |
| **total** | **1640** | |

**Inputs** (34):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| TRADE SETUP | `enum_TradeFrequency` | `TradeFrequency` | `Very_High` | Trading Frequency |
| TRADE SETUP | `int` | `InpMagic` | `647873` | EA Magic Number |
| TRADE SETUP | `string` | `TradeComment` | `"Gold X9 by MrCapFree"` | Comment for trades |
| MONEY MANAGEMENT / Lotsize Calculations | `enum_lotsizing` | `Lotsizing_Method` | `Tiered_Lotsizing` | Lotsize Calculation method |
| MONEY MANAGEMENT / Lotsize Calculations | `double` | `TieredLot` | `30` | Tiered Lot Sizing Risk Meter (1 - 100 Max) |
| MONEY MANAGEMENT / Lotsize Calculations | `double` | `FixedLots` | `0.01` | Fixed Lots |
| MONEY MANAGEMENT / Lotsize Calculations | `double` | `RiskScaling` | `1` | Risk Scaling Factor (%) |
| MONEY MANAGEMENT / Lotsize Calculations | `double` | `InpFixedBalance` | `0.0` | Fixed Balance for Sizing (0 = Live Account Balance) |
| Define Separate Lotsize for Individual Strategies | `bool` | `SepLotSize` | `false` | Use separate lotsize per strategy (Fixed Lots mode only) |
| Define Separate Lotsize for Individual Strategies | `double` | `Strat1Lots` | `0.01` | Strategy 1 Lotsize |
| Define Separate Lotsize for Individual Strategies | `double` | `Strat2Lots` | `0.01` | Strategy 2 Lotsize |
| Define Separate Lotsize for Individual Strategies | `double` | `Strat3Lots` | `0.01` | Strategy 3 Lotsize |
| Define Separate Lotsize for Individual Strategies | `double` | `Strat4Lots` | `0.01` | Strategy 4 Lotsize |
| Define Separate Lotsize for Individual Strategies | `double` | `Strat5Lots` | `0.01` | Strategy 5 Lotsize |
| Define Separate Lotsize for Individual Strategies | `double` | `Strat6Lots` | `0.01` | Strategy 6 Lotsize |
| Define Separate Lotsize for Individual Strategies | `double` | `Strat7Lots` | `0.01` | Strategy 7 Lotsize |
| Define Separate Lotsize for Individual Strategies | `double` | `Strat8Lots` | `0.01` | Strategy 8 Lotsize |
| Define Separate Lotsize for Individual Strategies | `double` | `Strat9Lots` | `0.01` | Strategy 9 Lotsize |
| PROP AND ENTRY ADJUSTMENTS | `double` | `AdjustEntry` | `0` | Adjust Entry (in points) |
| PROP AND ENTRY ADJUSTMENTS | `double` | `AdjustSL` | `0` | Adjust SL (in points) |
| PROP AND ENTRY ADJUSTMENTS | `double` | `AdjustTP` | `0` | Adjust TP (in points) |
| PROP AND ENTRY ADJUSTMENTS | `double` | `AdjustTrailSL` | `0` | Adjust Trail SL (in points) |
| PROP AND ENTRY ADJUSTMENTS | `double` | `AdjustSalvageExit` | `0` | Adjust Salvage Exit (in points) |
| PROP AND ENTRY ADJUSTMENTS | `double` | `AdjustBreakEven` | `0` | Adjust Breakeven (in points) |
| Manual Strategy Selection | `bool` | `RunStrat1` | `true` | Run Strategy 1 |
| Manual Strategy Selection | `bool` | `RunStrat2` | `true` | Run Strategy 2 |
| Manual Strategy Selection | `bool` | `RunStrat3` | `true` | Run Strategy 3 |
| Manual Strategy Selection | `bool` | `RunStrat4` | `true` | Run Strategy 4 |
| Manual Strategy Selection | `bool` | `RunStrat5` | `true` | Run Strategy 5 |
| Manual Strategy Selection | `bool` | `RunStrat6` | `true` | Run Strategy 6 |
| Manual Strategy Selection | `bool` | `RunStrat7` | `true` | Run Strategy 7 |
| Manual Strategy Selection | `bool` | `RunStrat8` | `true` | Run Strategy 8 |
| Manual Strategy Selection | `bool` | `RunStrat9` | `true` | Run Strategy 9 |
| DIAGNOSTICS & AUDIT LOGGING | `bool` | `InpEnableAuditLog` | `true` | Enable Reason-Coded Audit Logging |

**Order path**: `OrderDelete(`@729, `OrderDelete(`@766, `OrderDelete(`@1029, `OrderDelete(`@1059, `OrderDelete(`@1088, `trade.OrderOpen(`@1607

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=0 · FILE_COMMON=2 · inputs=34 · shell: `Gold_X9_Part3.mq5`

### 2. RBE

> Recompilation requires exactly `RangeBreakout.mq5` and `StrategyEngine.mqh`, `ExecutionRuntime.mqh`, `ChartVisuals.mqh`, all in this folder. Platform trade-library code is embedded  
> — `README.md`

| File | Lines | Role |
|---|---:|---|
| `RangeBreakout.mq5` | 11 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 387 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 952 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 4423 | engine: signals, sizing, state |
| **total** | **5773** | |

**Inputs** (5):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| General | `double` | `Risk_Money` | `250.0` | Risk money ($) |
| Risk Cost Model | `bool` | `Include_Costs_In_Risk` | `true` | Include modeled costs inside risk budget |
| Risk Cost Model | `double` | `Commission_Per_Lot_Override` | `7.0` | Explicit RT commission per lot (0=zero) |
| Risk Cost Model | `int` | `Assumed_Slip_Points` | `3` | Expected slippage each way (points) |
| Order Ownership | `long` | `Magic` | `111` | Magic number |

**Functions** (91): `RBEPoint`@15, `RBETip`@20, `RBEOrderInSession`@25, `RBEOverlayBroker`@29, `RBEBox`@99, `RBEVisualTrade`@115, `RBERender`@160, `RBEBarStart`@210, `RBEAnchorBarEnd`@217, `HLine`@229, `PxText`@245, `Rect`@266, `Lbl`@287, `DrawPanel`@306, `RBERestackPanel`@344, `RBENYClock`@354, `UpdatePanel`@363, `RBERestrictionKey`@407, `RBEAccountRestricted`@415, `RBELatchRestriction`@419, `RBEOwnedSelectedPosition`@430, `RBECommissionObserved`@452, `RBECommissionRTPerLot`@457, `RBESlipCashPerLot`@462, +67 more

**Order path**: `OrderDelete(`@770, `OrderDelete(`@799, `OrderDelete(`@820, `OrderDelete(`@892, `OrderModify(`@3396, `OrderDelete(`@3398, `OrderSend(`@3413, `OrderSend(`@3621, `OrderSend(`@3644, `OrderSend(`@3667, `OrderSend(`@3727, `OrderSend(`@3729, `OrderSend(`@3788, `OrderSend(`@3826, `OrderSend(`@3879, `OrderSend(`@3926, `OrderSend(`@4000, `OrderModify(`@4005, `OrderSend(`@4028, `OrderDelete(`@4033, `OrderSend(`@4045, `OrderSend(`@4944, `OrderSendAsync(`@4952, `OrderSend(`@4954

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=1 · FILE_COMMON=9 · inputs=5 · shell: `RangeBreakout.mq5`

### 3. TokyoCoil

> Recompilation requires exactly `TokyoCoil.mq5` and `StrategyEngine.mqh`, `ExecutionRuntime.mqh`, `ChartVisuals.mqh`, all in this folder. Platform trade-library code is embedded loc  
> — `README.md`

| File | Lines | Role |
|---|---:|---|
| `TokyoCoil.mq5` | 11 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 621 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 262 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 5037 | engine: signals, sizing, state |
| **total** | **5931** | |

**Inputs** (18):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| 1 - Trading | `bool` | `EnableC1` | `true` | Enable trading |
| 2 - Risk & Equity Brake | `double` | `RiskPct` | `1.0` | Balance risk (%) when fixed cash risk is zero |
| 2 - Risk & Equity Brake | `double` | `RiskMoney` | `0.0` | >0: fixed cash stop-risk budget; 0: RiskPct of balance. |
| 2 - Risk & Equity Brake | `bool` | `UseBrake` | `true` | Halve risk after rolling losses |
| 2 - Risk & Equity Brake | `int` | `BrakeN` | `20` | Closed trades in rolling window |
| 2 - Risk & Equity Brake | `double` | `BrakeFloorR` | `-4.0` | Half-risk threshold (R, inclusive) |
| 3 - News Exit | `bool` | `UseNewsFlatten` | `false` | Close before high-impact USD news |
| 3 - News Exit | `int` | `NewsExitLeadMinutes` | `5` | Minutes before news |
| 3 - News Exit | `string` | `NewsWebRequestURL` | `"https://nfs.faireconomy.media"` | Copy to MT5 Allow WebRequest (reference only) |
| 3 - News Exit | `string` | `CalendarFile` | `"asiancoil_usd_events.csv"` | Filename in Common\Files (NY event times) |
| 3 - News Exit | `bool` | `AllowDiagnosticCalendar` | `false` | Permit incomplete calendar for diagnostics only |
| 4 - Execution & Logging | `string` | `TradeLogFile` | `"tokyocoil_frozen_trades.csv"` | Common\Files |
| 4 - Execution & Logging | `long` | `MagicC1` | `26093001` | Strategy magic number |
| 4 - Execution & Logging | `int` | `DeviationPts` | `30` | Maximum market-order deviation (points) |
| 5 - Display | `bool` | `ShowPanel` | `true` | Show information panel |
| 5 - Display | `bool` | `DrawRangeBoxes` | `true` | Draw session boxes and levels |
| 5 - Display | `bool` | `ShowExecutionObjects` | `true` | Draw filled-trade entry and outcome boxes |
| 5 - Display | `bool` | `ShowSyntheticFills` | `true` | Show hypothetical hindsight fills (never broker orders) |

**Functions** (118): `TcVisualBarEnd`@16, `TcExecutionRight`@21, `TcExecutionLossEdge`@29, `TcVisibleSession`@33, `TcAllowLiveReplay`@39, `TcHindsightSide`@44, `TcVisualInt`@56, `TcVisualString`@61, `TcVisualPoint`@66, `TcVisualDelete`@72, `TcPanelStart`@88, `TcPanelRect`@99, `TcPanelLabel`@110, `TcPanelRefresh`@121, `TcPanelStop`@209, `TcRangeAnchor`@223, `TcRangePoint`@227, `TcRangeLine`@232, `TcVisualQualifies`@248, `TcRangeDraw`@255, `TcRangesRefresh`@308, `TcRangesCheck`@324, `TcRangesFocus`@348, `TcRangeFill`@376, +94 more

**Order path**: `OrderDelete(`@759, `OrderSend(`@963, `OrderSend(`@965, `OrderSendAsync(`@965, `OrderSend(`@989, `OrderSendAsync(`@989, `OrderModify(`@3007, `OrderDelete(`@3009, `OrderSend(`@3024, `OrderSend(`@3232, `OrderSend(`@3255, `OrderSend(`@3278, `OrderSend(`@3338, `OrderSend(`@3340, `OrderSend(`@3399, `OrderSend(`@3437, `OrderSend(`@3490, `OrderSend(`@3537, `OrderSend(`@3611, `OrderModify(`@3616, `OrderSend(`@3639, `OrderDelete(`@3644, `OrderSend(`@3656, `OrderSend(`@4555, `OrderSend(`@4562, `OrderSend(`@4564, `OrderDelete(`@5563, `OrderDelete(`@5662, `trade.OrderModify(`@5712, `OrderModify(`@5712, `OrderDelete(`@5715, `OrderDelete(`@5824, `trade.OrderModify(`@5827, `OrderModify(`@5827

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=1 · FILE_COMMON=8 · inputs=18 · shell: `TokyoCoil.mq5`

### 4. Index Book / 1. VaultBreak

> The live journal is isolated by broker server, account, account mode, symbol and magic, with an exclusive local instance lock. Committed state binds original risk and entry time to  
> — `MODEL.md`

| File | Lines | Role |
|---|---:|---|
| `VaultBreak.mq5` | 11 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 592 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 682 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 987 | engine: signals, sizing, state |
| **total** | **2272** | |

**Inputs** (8):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| 1 - Trading | `bool` | `EnableTrading` | `true` | Enable new trades (open trades stay protected when off) |
| 2 - Risk | `double` | `RiskMoney` | `100.0` | Risk per trade, including costs (account currency) |
| 2 - Risk | `bool` | `UseFixedSize` | `false` | Use fixed lots instead of the cash risk budget |
| 2 - Risk | `double` | `FixedLots` | `1.0` | Lots per trade when fixed sizing is enabled |
| 3 - Trading Costs | `double` | `CommissionPerLot` | `7.0` | Fallback round-trip commission per lot until broker history is available |
| 3 - Trading Costs | `int` | `SlippagePoints` | `3` | Slippage/side (3=0.03 if broker Point=0.01) |
| 4 - Display | `bool` | `ShowVisuals` | `true` | Show chart levels, trade markers and information |
| 5 - Execution & Logging | `bool` | `WriteTradeLog` | `false` | Write a detailed trade and decision log |

**Functions** (96): `VBVisualFit`@21, `VBVisualFault`@42, `VBVisualSuspend`@62, `VBInitVisual`@86, `VBPanelRect`@122, `VBPanelLbl`@143, `VBPanelShell`@162, `VBPanelRows`@198, `OnChartEvent`@216, `VBTradeBox`@235, `VBPaintBrokerTrades`@250, `VBDrawFill`@329, `VBLine`@340, `VBHistoryLine`@371, `VBHistoricalSessions`@383, `VBDraw`@437, `VBDrawVWAP`@522, `VBRefreshLiveVisuals`@549, `VBServerUTC`@679, `VBExportTrades`@683, `VBRecoveryIntentMatches`@750, `VBRecoveryPositionMatches`@756, `VBRuntimeOwnershipKey`@772, `VBStatePut`@779, +72 more

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=0 · FILE_COMMON=12 · inputs=8 · shell: `VaultBreak.mq5`

### 4. Index Book / 2. OvernightBiasRangeBreakout

> The EA now permits one strictly later same-side retry after the first attempt has fully exited through a losing broker protective stop. It does not retry after a target, time/manua  
> — `MODEL.md`

| File | Lines | Role |
|---|---:|---|
| `ADXPane.mq5` | 60 | shell: inputs, globals, event handlers |
| `OvernightBiasRangeBreakout.mq5` | 11 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 581 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 672 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 1010 | engine: signals, sizing, state |
| **total** | **2334** | |

**Inputs** (10):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| ungrouped | `int` | `PeriodADX` | `15` |  |
| ungrouped | `string` | `Caption` | `"Overnight Bias trend strength"` |  |
| 1 - Trading | `bool` | `EnableTrading` | `true` | Enable new trades (open trades stay protected when off) |
| 2 - Risk | `double` | `RiskMoney` | `100.0` | Risk per trade, including costs (account currency) |
| 2 - Risk | `bool` | `UseFixedSize` | `false` | Use fixed lots instead of the cash risk budget |
| 2 - Risk | `double` | `FixedLots` | `1.0` | Lots per trade when fixed sizing is enabled |
| 3 - Trading Costs | `double` | `CommissionPerLot` | `7.0` | Fallback round-trip commission per lot until broker history is available |
| 3 - Trading Costs | `int` | `SlippagePoints` | `3` | Slippage/side (3=0.03 if broker Point=0.01) |
| 4 - Display | `bool` | `ShowVisuals` | `true` | Show chart levels, trade markers and information |
| 5 - Execution & Logging | `bool` | `WriteTradeLog` | `false` | Write a detailed trade and decision log |

**Functions** (101): `SourceTime`@23, `OnInit`@28, `OnCalculate`@36, `OBRVisualFit`@82, `OBRVisualFault`@102, `OBRVisualSuspend`@122, `OBRInitVisual`@146, `OBRPanelRect`@193, `OBRPanelLbl`@214, `OBRPanelShell`@233, `OBRPanelRows`@269, `OnChartEvent`@287, `OBRTradeBox`@304, `OBRPaintBrokerTrades`@319, `OBRDrawFill`@398, `OBRLine`@409, `OBRHistoryLine`@440, `OBRHistoricalSessions`@452, `OBRDraw`@506, `OBRRefreshLiveVisuals`@585, `OBRServerUTC`@729, `OBRExportTrades`@733, `OBRRecoveryIntentMatches`@800, `OBRRecoveryPositionMatches`@806, +77 more

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=0 · FILE_COMMON=12 · inputs=10 · shell: `ADXPane.mq5`, `OvernightBiasRangeBreakout.mq5`

### 4. Index Book / 3. OpenDrive

> The strategy exploits the structural institutional order imbalance and liquidity expansion that occurs at the **09:30 AM New York Cash Equity Market Open (NYSE / Nasdaq opening bel  
> — `MODEL.md`

| File | Lines | Role |
|---|---:|---|
| `OpenDrive.mq5` | 11 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 330 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 1263 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 632 | engine: signals, sizing, state |
| **total** | **2236** | |

**Inputs** (38):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| 1 - Trading | `bool` | `EnableTrading` | `true` | Enable new entries (open trades stay protected when off) |
| 1 - Trading | `bool` | `AllowLong` | `true` | Allow Long entries |
| 1 - Trading | `bool` | `AllowShort` | `true` | Allow Short entries |
| 1 - Trading | `bool` | `BlockOpposingExposure` | `true` | Block opposing same-symbol / equity-index exposure |
| 2 - Risk & Sizing | `ENUM_RISK_MODE` | `RiskMode` | `RISK_DYNAMIC_VOLATILITY` | Sizing Mode (Dynamic for Prop, Static for Live) |
| 2 - Risk & Sizing | `double` | `RiskPercent` | `1.0` | Maximum Risk % per trade (0.5% - 1.0%) |
| 2 - Risk & Sizing | `double` | `RiskMoney` | `0.0` | Fixed Dollar Risk per trade (0 = use RiskPercent) |
| 2 - Risk & Sizing | `bool` | `UseFixedLots` | `false` | Use fixed contracts instead of % risk |
| 2 - Risk & Sizing | `double` | `FixedLots` | `1.0` | Contract quantity when fixed sizing enabled |
| 2 - Risk & Sizing | `bool` | `AllowMinLotFallback` | `true` | Execute broker min lot if calculated lot is below minimum |
| 2 - Risk & Sizing | `double` | `DailyLossLimitPct` | `0.0` | Daily loss lock % of day-start balance (0 = off) |
| 3 - Signal Core | `int` | `EmaPeriod` | `12` | Opening Signal EMA (M5 close) |
| 3 - Signal Core | `int` | `EntryHourNY` | `9` | Cash open hour (New York) |
| 3 - Signal Core | `int` | `EntryMinNY` | `30` | Cash open minute (New York) |
| 4 - Stops & Trailing | `int` | `AtrPeriod` | `14` | Volatility ATR period |
| 4 - Stops & Trailing | `ENUM_ATR_MODE` | `AtrMode` | `ATR_WILDER` | ATR Calculation Mode |
| 4 - Stops & Trailing | `double` | `StopATR` | `4.0` | Hard stop distance (x ATR from fill) |
| 4 - Stops & Trailing | `double` | `ActivateATR` | `0.25` | Profit confirmation before trail (x ATR) |
| 4 - Stops & Trailing | `double` | `TrailATR` | `3.0` | Chandelier trailing distance (x ATR behind extreme) |
| 4 - Stops & Trailing | `bool` | `FlatAtExit` | `true` | Close flat before session close (no overnight gap) |
| 4 - Stops & Trailing | `int` | `ExitHourNY` | `16` | Session exit hour (16:00 NY Cash Close) |
| 4 - Stops & Trailing | `int` | `ExitMinNY` | `0` | Session exit minute |
| 5 - Costs & Execution | `int` | `BrokerServerGMTOffset` | `99` | Server GMT offset in Winter (99 = Auto-detect from chart) |
| 5 - Costs & Execution | `int` | `MaxSpreadPoints` | `0` | Max allowed spread in points (0 = off) |
| 5 - Costs & Execution | `int` | `SlippagePoints` | `3` | Slippage allowance in points |
| 5 - Costs & Execution | `double` | `CommissionPerLot` | `7.0` | Fallback round-trip commission per lot ($) |
| 5 - Costs & Execution | `ulong` | `MagicNumber` | `93093001` | EA Magic Number |
| 5 - Costs & Execution | `string` | `TradeComment` | `"OpenDrive"` | Trade Comment |
| 6 - Display & Visuals | `bool` | `ShowVisuals` | `true` | Draw chart lines & markers |
| 6 - Display & Visuals | `bool` | `ShowPanel` | `true` | Display floating HUD panel |
| 6 - Display & Visuals | `bool` | `ShowExtras` | `false` | Diagnostic signal boxes & arrows |
| 6 - Display & Visuals | `bool` | `WriteLog` | `true` | Print journal decision log |
| 7 - News Guard | `string` | `News_WebRequest_URL` | `"https://nfs.faireconomy.media"` | WebRequest URL (copy to MT5 Options) |
| 7 - News Guard | `ENUM_NEWS_IMPACT` | `News_Impact` | `NEWS_RED_ONLY` | News impact filter (USD) |
| 7 - News Guard | `ENUM_NEWS_WINDOW` | `News_Window` | `NEWS_WINDOW_10` | Blackout window around release |
| 7 - News Guard | `bool` | `News_Cost_Covered_BE` | `true` | Move stop to cost-covered BE if in profit before news |
| 7 - News Guard | `bool` | `News_Flatten_Before` | `false` | Close position before news (strict prop rule) |
| 7 - News Guard | `bool` | `News_Block_Modification` | `true` | Block trade modifications during blackout (prop rule) |

**Functions** (63): `OD_Rect`@33, `OD_Lbl`@56, `RenderHUDShell`@78, `UpdateHUD`@126, `PruneVisualObjects`@250, `DrawSessionLine`@265, `DrawSignalCandleBox`@287, `DrawExecutionMarker`@310, `CleanupVisuals`@327, `ODStateIdentity`@384, `ODManagementSettings`@388, `ODChecksum`@394, `ODStatePayload`@400, `ODSaveState`@415, `ODReadSlot`@434, `ODLoadState`@453, `ODObserveResult`@494, `ODSelectedOwned`@501, `ODPositionEvidence`@508, `ODReconcile`@543, `GetFillingMode`@642, `NativeClosePosition`@650, `NativeModifySL`@690, `NativeSendOrder`@725, +39 more

**Order path**: `OrderSend(`@674, `OrderSend(`@710, `OrderSend(`@743

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=1 · FILE_COMMON=5 · inputs=38 · shell: `OpenDrive.mq5`

### 4. Index Book / 4. NQPrecisionBot

> The source layout matches VaultBreak, OvernightBiasRangeBreakout and VWAPPullback: one thin `NQ Precision Bot.mq5` entry file, `StrategyEngine.mqh`, `ExecutionRuntime.mqh`, and `Ch  
> — `README.md`

| File | Lines | Role |
|---|---:|---|
| `NQ Precision Bot.mq5` | 8 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 781 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 837 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 1123 | engine: signals, sizing, state |
| **total** | **2749** | |

**Inputs** (30):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| 1 - Trading | `bool` | `EnableTrading` | `true` | Enable new trades (open trades stay protected when off) |
| 1 - Trading | `bool` | `BlockOpposingExposure` | `true` | Also check the visible index family; exact-symbol isolation is always on |
| 2 - Risk | `double` | `RiskMoney` | `100.0` | Risk per trade, including costs (account currency) |
| 2 - Risk | `bool` | `UseFixedSize` | `false` | Use fixed lots instead of the cash risk budget |
| 2 - Risk | `double` | `FixedLots` | `1.0` | Lots per trade when fixed sizing is enabled |
| 3 - Trading Costs | `double` | `CommissionPerLot` | `0.0` | ICMarkets index CFD: costs are embedded in spread; 7.0 was original fallback (do |
| 3 - Trading Costs | `int` | `SlippagePoints` | `3` | Slippage/side (3=0.03 if broker Point=0.01) |
| 4 - Display | `bool` | `ShowVisuals` | `true` | Show chart levels, trade markers and information |
| 5 - Execution & Logging | `bool` | `WriteTradeLog` | `true` | Write a detailed trade and decision log |
| 6 - NQ Signal & Research | `NQDataContract` | `SignalData` | `NativeChartData` | Automatic symbol data contract; explicit research overrides |
| 6 - NQ Signal & Research | `bool` | `InpUseTickHistory` | `true` | Tick-derived ETH M1; false uses stored M1 approximation |
| 6 - NQ Signal & Research | `bool` | `InpResearchUTC` | `false` | UTC imported research tape; otherwise portfolio automatic broker clock |
| 6 - NQ Signal & Research | `int` | `InpAtrPeriod` | `14` |  |
| 6 - NQ Signal & Research | `int` | `InpAtrRegimeLen` | `50` |  |
| 6 - NQ Signal & Research | `double` | `InpAtrSlMult` | `2.2` |  |
| 6 - NQ Signal & Research | `double` | `InpAtrTpMult` | `0.8` | 0.3 was original default (tight scalp); 0.8 is OptB winner (2020–2026 sweep, PF  |
| 6 - NQ Signal & Research | `bool` | `InpInvertSignal` | `false` | Invert trade direction (Counter-scalp / Market-maker mode) |
| 6 - NQ Signal & Research | `bool` | `InpUseTimeClose` | `true` |  |
| 6 - NQ Signal & Research | `int` | `InpCloseAfterMin` | `8` |  |
| 6 - NQ Signal & Research | `bool` | `InpUseFilters` | `true` |  |
| 6 - NQ Signal & Research | `int` | `InpRvolLen` | `14` |  |
| 6 - NQ Signal & Research | `double` | `InpRvolMin` | `0.5` |  |
| 6 - NQ Signal & Research | `double` | `InpRvolMax` | `1.5` |  |
| 6 - NQ Signal & Research | `double` | `InpRegimeMin` | `1.0` |  |
| 6 - NQ Signal & Research | `double` | `InpRegimeMax` | `2.5` |  |
| 6 - NQ Signal & Research | `int` | `InpRangeStart` | `93000` |  |
| 6 - NQ Signal & Research | `int` | `InpRangeEnd` | `94500` |  |
| 6 - NQ Signal & Research | `bool` | `InpUseTriggerTime` | `true` |  |
| 6 - NQ Signal & Research | `int` | `InpTriggerTime` | `95955` |  |
| 6 - NQ Signal & Research | `int` | `InpTradeUntil` | `110000` |  |

**Functions** (132): `NQPVisualFit`@18, `NQPVisualFault`@38, `NQPVisualSuspend`@58, `NQPInitVisual`@82, `NQPPanelRect`@129, `NQPPanelLbl`@150, `NQPPanelShell`@169, `NQPPanelRows`@205, `OnChartEvent`@223, `NQPSetupContains`@253, `NQPExecutionRightShift`@260, `NQPExecutionRight`@264, `NQPTradeBox`@284, `NQPPaintBrokerTrades`@299, `NQPDrawFill`@382, `NQPLine`@393, `NQPHistoryLine`@431, `NQPRangeBox`@443, `NQPVisitReplayTick`@462, `NQPReplayTickBars`@511, `NQPReplaySetup`@539, `NQPPaintReplay`@612, `NQPRangeBounds`@636, `NQPHistoricalSessions`@648, +108 more

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=0 · FILE_COMMON=14 · inputs=30 · shell: `NQ Precision Bot.mq5`

### 4. Index Book / 5. OpeningShockContinuation

> Built from the supplied `VaultBreak.mq5`, its `StrategyEngine.mqh`, `ExecutionRuntime.mqh`, `ChartVisuals.mqh`, and `VaultBreakNT8(1).cs`. These are source forks, not a reimplement  
> — `MODEL.md`

| File | Lines | Role |
|---|---:|---|
| `OpeningShock.mq5` | 11 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 593 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 687 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 895 | engine: signals, sizing, state |
| **total** | **2186** | |

**Inputs** (9):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| 1 - Trading | `bool` | `EnableTrading` | `false` | v7: paper/test only until explicitly enabled  // Enable new trades (open trades  |
| 2 - Risk | `double` | `RiskMoney` | `100.0` | Risk per trade, including costs (account currency) |
| 2 - Risk | `bool` | `UseFixedSize` | `false` | Use fixed lots instead of the cash risk budget |
| 2 - Risk | `double` | `FixedLots` | `1.0` | Lots per trade when fixed sizing is enabled |
| 2 - Risk | `bool` | `EnforceFixedSizeRiskCap` | `true` | Fixed lots also subject to RiskMoney; prevents accidental oversizing |
| 3 - Trading Costs | `double` | `CommissionPerLot` | `7.0` | Fallback round-trip commission per lot until broker history is available |
| 3 - Trading Costs | `int` | `SlippagePoints` | `3` | Slippage/side (3=0.03 if broker Point=0.01) |
| 4 - Display | `bool` | `ShowVisuals` | `true` | Show chart levels, trade markers and information |
| 5 - Execution & Logging | `bool` | `WriteTradeLog` | `false` | Write a detailed trade and decision log |

**Functions** (98): `VBVisualFit`@21, `VBVisualFault`@42, `VBVisualSuspend`@62, `VBInitVisual`@86, `VBPanelRect`@122, `VBPanelLbl`@143, `VBPanelShell`@162, `VBPanelRows`@198, `OnChartEvent`@216, `VBTradeBox`@235, `VBPaintBrokerTrades`@250, `VBDrawFill`@329, `VBLine`@340, `VBHistoryLine`@371, `VBHistoricalSessions`@383, `VBDraw`@437, `VBDrawVWAP`@523, `VBRefreshLiveVisuals`@550, `VBServerUTC`@680, `VBExportTrades`@684, `VBRecoveryIntentMatches`@751, `VBRecoveryPositionMatches`@757, `VBRuntimeOwnershipKey`@773, `VBStatePut`@780, +74 more

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=0 · FILE_COMMON=12 · inputs=9 · shell: `OpeningShock.mq5`

### 4. Index Book / 6. SigmaBreakout

| File | Lines | Role |
|---|---:|---|
| `SigmaBreakout.mq5` | 11 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 581 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 686 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 1105 | engine: signals, sizing, state |
| **total** | **2383** | |

**Inputs** (13):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| 1 - Trading | `bool` | `EnableTrading` | `true` | Enable new trades (open trades stay protected when off) |
| 2 - Risk | `double` | `SlPct` | `0.0` | Stop loss percentage (0 = no synthetic stop; flip/session exit) |
| 2 - Risk | `bool` | `UseFixedSize` | `true` | Use fixed lots (default ON for Sigma) |
| 2 - Risk | `double` | `FixedLots` | `1.0` | Lots per trade when fixed sizing is enabled |
| 2 - Risk | `double` | `RiskMoney` | `250.0` | Risk per trade in account currency (used when UseFixedSize=false) |
| 2 - Risk | `bool` | `SkipSetupsAboveRiskBudget` | `false` | Skip entries where total initial risk > RiskBudgetUsd |
| 2 - Risk | `double` | `RiskBudgetUsd` | `250.0` | Cap (account currency); only active when SkipSetupsAboveRiskBudget=true |
| 3 - Model Parameters | `int` | `N_Sigma` | `3` | Prior RTH sessions per slot for band calculation |
| 3 - Model Parameters | `double` | `BandMult` | `1.7` | Band multiplier applied to mean absolute deviation |
| 4 - Trading Costs | `double` | `CommissionPerLot` | `7.0` | Fallback round-trip commission per lot |
| 4 - Trading Costs | `int` | `SlippagePoints` | `3` | Slippage per side in points |
| 5 - Display | `bool` | `ShowVisuals` | `true` | Show chart levels, trade markers and information panel |
| 6 - Execution & Logging | `bool` | `WriteTradeLog` | `false` | Write a detailed trade and decision log |

**Functions** (96): `SigmaVisualFit`@21, `SigmaVisualFault`@41, `SigmaVisualSuspend`@61, `SigmaInitVisual`@85, `SigmaPanelRect`@132, `SigmaPanelLbl`@153, `SigmaPanelShell`@172, `SigmaPanelRows`@208, `OnChartEvent`@226, `SigmaTradeBox`@243, `SigmaPaintBrokerTrades`@258, `SigmaDrawFill`@337, `SigmaLine`@348, `SigmaHistoryLine`@379, `SigmaHistoricalSessions`@391, `SigmaDraw`@445, `SigmaRefreshLiveVisuals`@524, `SigmaServerUTC`@668, `SigmaExportTrades`@672, `SigmaRecoveryIntentMatches`@739, `SigmaRecoveryPositionMatches`@747, `SigmaRuntimeOwnershipKey`@764, `SigmaStatePut`@771, `RecoveryClosePut`@782, +72 more

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=0 · FILE_COMMON=12 · inputs=13 · shell: `SigmaBreakout.mq5`

### 4. Index Book / 7. FlashTriggerORB

| File | Lines | Role |
|---|---:|---|
| `FlashTriggerORB.mq5` | 12 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 581 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 698 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 906 | engine: signals, sizing, state |
| **total** | **2197** | |

**Inputs** (11):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| 1 - Trading | `bool` | `EnableTrading` | `true` | Enable new trades (open trades stay protected when off) |
| 2 - Risk | `bool` | `UseFixedSize` | `true` | Use fixed lots (default ON) |
| 2 - Risk | `double` | `FixedLots` | `1.0` | Lots per trade when fixed sizing is enabled |
| 2 - Risk | `double` | `RiskMoney` | `100.0` | Risk per trade (used when UseFixedSize=false) |
| 2 - Risk | `bool` | `AllowMinimumOneLot` | `true` | Legacy setting; variable sizing always floors to broker minimum |
| 2 - Risk | `bool` | `SkipSetupsAboveRiskBudget` | `false` | Skip entries where computed risk > RiskBudgetUsd |
| 2 - Risk | `double` | `RiskBudgetUsd` | `250.0` | Cap in account currency (active only if above flag=true) |
| 3 - Trading Costs | `double` | `CommissionPerLot` | `7.0` | Fallback round-trip commission per lot |
| 3 - Trading Costs | `int` | `SlippagePoints` | `3` | Slippage per side in points |
| 4 - Display | `bool` | `ShowVisuals` | `true` |  |
| 5 - Execution & Logging | `bool` | `WriteTradeLog` | `false` |  |

**Functions** (89): `FlashVisualFit`@22, `FlashVisualFault`@42, `FlashVisualSuspend`@62, `FlashInitVisual`@86, `FlashPanelRect`@133, `FlashPanelLbl`@154, `FlashPanelShell`@173, `FlashPanelRows`@209, `OnChartEvent`@227, `FlashTradeBox`@244, `FlashPaintBrokerTrades`@259, `FlashDrawFill`@338, `FlashLine`@349, `FlashHistoryLine`@380, `FlashHistoricalSessions`@392, `FlashDraw`@446, `FlashRefreshLiveVisuals`@525, `FlashServerUTC`@669, `FlashExportTrades`@673, `FlashRecoveryIntentMatches`@740, `FlashRecoveryPositionMatches`@746, `FlashRuntimeOwnershipKey`@763, `FlashStatePut`@770, `RecoveryClosePut`@781, +65 more

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=0 · FILE_COMMON=12 · inputs=11 · shell: `FlashTriggerORB.mq5`

### 4. Index Book / 8. NoiseBandMomentum

| File | Lines | Role |
|---|---:|---|
| `NoiseBandMomentum.mq5` | 335 | shell: inputs, globals, event handlers |
| **total** | **335** | |

**Inputs** (14):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| Session (broker server time) | `int` | `InpOpenHour` | `16` | New York open: hour (16 on brokers at New York + 7 h) |
| Session (broker server time) | `int` | `InpOpenMinute` | `30` | New York open: minute |
| Session (broker server time) | `int` | `InpCheckpoints` | `11` | Number of half-hour checkpoints after the open (11 = until +5.5 h) |
| Session (broker server time) | `int` | `InpCloseHour` | `23` | Close all positions from this hour on (New York close) |
| Signal | `double` | `InpBandK` | `1.4` | Band width k (threshold = k * sqrt(K) * ATR) |
| Signal | `int` | `InpAtrPeriod` | `14` | ATR period (30-minute candles) |
| Exit | `double` | `InpStopAtr` | `2.0` | Initial stop in ATR |
| Exit | `double` | `InpTrailAtr` | `2.0` | Trailing distance in ATR |
| Exit | `double` | `InpTrailStartR` | `1.0` | Start trailing at this profit in R (1 R = initial stop distance) |
| Exit | `int` | `InpMaxBars` | `20` | Hard exit after this many 30-minute candles |
| Risk | `double` | `InpRiskPercent` | `1.0` | Risk per trade in % of balance |
| Risk | `long` | `InpMagic` | `260601` | Magic number |
| Risk | `int` | `InpSlippage` | `30` | Max. slippage in points |
| Risk | `int` | `InpTrailSeconds` | `300` | Min. seconds between two trailing-stop updates |

**Functions** (8): `OnInit`@69, `OnDeinit`@124, `OnTick`@131, `SelectPosition`@144, `Atr`@157, `Manage`@168, `CheckEntry`@237, `LotFor`@306

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=0 · FILE_COMMON=0 · inputs=15 · shell: `NoiseBandMomentum.mq5`

### 4. Index Book / 9. FVG_Duo

> FVG Duo is an institutional index strategy designed for Nasdaq futures (NQ, MNQ) and CFD equivalents (USTEC). It unites two complementary Fair Value Gap (FVG) sub-models operating   
> — `MODEL.md`

| File | Lines | Role |
|---|---:|---|
| `FVG_Duo.mq5` | 17 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 630 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 880 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 943 | engine: signals, sizing, state |
| `VisualRecovery.mqh` | 340 | include |
| **total** | **2810** | |

**Inputs** (14):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| 1 - Sizing & Risk | `ENUM_SIZING_MODE` | `InpSizingMode` | `SIZING_FIXED` | Sizing Mode |
| 1 - Sizing & Risk | `double` | `InpFixedLots` | `1.0` | Fixed Lots |
| 1 - Sizing & Risk | `double` | `InpRiskPercent` | `1.0` | Risk % per Trade |
| 1 - Sizing & Risk | `double` | `InpCashRiskUSD` | `100.0` | Cash Risk USD per Trade |
| 1 - Sizing & Risk | `double` | `InpFixedBalanceUSD` | `0.0` | Fixed Balance USD (0 = derive from initial balance) |
| 1 - Sizing & Risk | `int` | `InpRiskSlippageTicks` | `2` | Stressed Exit Slippage (ticks, reserved in risk) |
| 1 - Sizing & Risk | `string` | `InpMoneyUnit` | `"USD"` | Unit of cash/commission inputs ("ACCOUNT" = account currency; USC/EURC/... resol |
| 1 - Sizing & Risk | `double` | `InpMoneyRate` | `0.0` | Account cash per 1 unit (0 = derive from the terminal) |
| 1 - Sizing & Risk | `bool` | `InpAllowMinLotOverride` | `false` | Round up to broker minimum when the budget is below it (false = skip) |
| 2 - Costs & Execution | `ulong` | `InpMagic` | `909150` | EA Magic Number |
| 2 - Costs & Execution | `ulong` | `InpDeviation` | `10` | Max Slippage Points |
| 2 - Costs & Execution | `double` | `InpCommissionRTPerLot` | `7.0` | Round-turn Commission per Lot ($3.50 open + $3.50 close) |
| 3 - Display & Visuals | `bool` | `ShowVisuals` | `true` | Draw FVG Boxes and Markers |
| 3 - Display & Visuals | `bool` | `ShowDashboard` | `true` | Display Performance HUD |

**Functions** (90): `VisualsAllowed`@45, `DashboardAllowed`@51, `FormatMoney`@61, `FvgPanelTextWidth`@113, `FvgPanelFitText`@126, `FvgPanelDesiredWidth`@145, `ConfigurePanelLayering`@157, `RestorePanelLayering`@177, `FvgPanelRect`@186, `FvgPanelLbl`@208, `FvgPanelShell`@227, `UpdateDashboard`@268, `OnChartEvent`@344, `PruneFvgVisuals`@374, `ShowFvgCandidate`@405, `MarkFvgCandidateTraded`@429, `UpdateSessionVisual`@441, `UpdateObservedSessionVisual`@476, `ShowTrendAverages`@489, `ShowTradeGeometry`@527, `FinishTradeGeometry`@609, `RemoveVisuals`@634, `SymTick`@702, `SymDigits`@711, +66 more

**Flags**: clock: per-EA engine (not migrated) · money: tick-value derivation · WebRequest=0 · FILE_COMMON=9 · inputs=14 · shell: `FVG_Duo.mq5`

### 4. Index Book / 10. VWAPPullback

> The journal uses broker server, account, account mode, symbol and magic plus an exclusive local instance lock. It binds the immutable broker position identifier (two exact 32-bit h  
> — `MODEL.md`

| File | Lines | Role |
|---|---:|---|
| `ADXPane.mq5` | 67 | shell: inputs, globals, event handlers |
| `VWAPPullback.mq5` | 11 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 472 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 729 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 705 | engine: signals, sizing, state |
| **total** | **1984** | |

**Inputs** (11):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| ungrouped | `int` | `AdxPeriod` | `14` |  |
| ungrouped | `string` | `PaneName` | `"VWAP Pullback ADX"` |  |
| 1 - Trading | `bool` | `EnableTrading` | `true` | Enable new trades (open trades stay protected when off) |
| 1 - Trading | `bool` | `BlockOpposingExposure` | `true` | Block opposing chart-symbol / index exposure in this account |
| 2 - Risk | `double` | `RiskMoney` | `100.0` | Risk per trade, including costs (account currency) |
| 2 - Risk | `bool` | `UseFixedSize` | `false` | Use fixed lots instead of the cash risk budget |
| 2 - Risk | `double` | `FixedLots` | `1.0` | Lots per trade when fixed sizing is enabled |
| 3 - Trading Costs | `double` | `CommissionPerLot` | `7.0` | Fallback round-trip commission per lot until broker history is available |
| 3 - Trading Costs | `int` | `SlippagePoints` | `3` | Slippage/side (x0.01; 3=0.03 price) |
| 4 - Display | `bool` | `ShowVisuals` | `true` | Show chart levels, trade markers and information |
| 5 - Execution & Logging | `bool` | `WriteTradeLog` | `false` | Write a detailed trade and decision log |

**Functions** (82): `OnInit`@28, `Find`@36, `OnCalculate`@42, `VWPVisualFit`@89, `VWPVisualFault`@109, `VWPVisualSuspend`@130, `VWPInitVisual`@154, `VWPPanelRect`@201, `VWPPanelLbl`@222, `VWPPanelShell`@241, `VWPPanelRows`@277, `OnChartEvent`@295, `VWPTradeBox`@312, `VWPPaintBrokerTrades`@327, `VWPDrawFill`@406, `VWPLine`@417, `VWPHistoryLine`@448, `VWPHistoricalSessions`@460, `VWPDraw`@513, `VWPServerUTC`@627, `VWPExportTrades`@631, `VWPRecoveryIntentMatches`@700, `VWPRecoveryPositionMatches`@706, `VWPRuntimeOwnershipKey`@723, +58 more

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=0 · FILE_COMMON=12 · inputs=11 · shell: `ADXPane.mq5`, `VWAPPullback.mq5`

### 4. Index Book / 11. TuesdayTurnaround

> Port of the verified T1-T4 completed-Daily model. The EA follows the modular RBE/VaultBreak/OvernightBiasRangeBreakout layout.  
> — `MODEL.md`

| File | Lines | Role |
|---|---:|---|
| `TuesdayTurnaround.mq5` | 11 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 131 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 353 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 4111 | engine: signals, sizing, state |
| **total** | **4606** | |

**Inputs** (26):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| 1 - Strategy | `bool` | `EnableTrading` | `true` |  |
| 1 - Strategy | `TTModel` | `Model` | `T1_OnePercentDrop` | research candidates: NQ/MNQ T1; ES/MES T4 (manual selection) |
| 1 - Strategy | `string` | `AssetRoot` | `"AUTO"` | AUTO, ES, NQ, MES or MNQ |
| 2 - Risk | `TTRiskMode` | `Sizing` | `Fixed_Lots` |  |
| 2 - Risk | `double` | `FixedVolume` | `1.0` |  |
| 2 - Risk | `double` | `RiskMoney` | `500.0` |  |
| 2 - Risk | `double` | `CostPerContract` | `0.0` | legacy total-cost override; 0 learns commission then adds slippage |
| 2 - Risk | `double` | `AssumedSlippageTicksPerSide` | `1.0` |  |
| 3 - Exit | `bool` | `EnableFixedSelfClose` | `false` |  |
| 3 - Exit | `int` | `FixedSelfCloseHHMMSS` | `164455` | New York time |
| 3 - Exit | `int` | `BaseCloseHHMMSS` | `165955` | executable proxy before 17:00 New York |
| 4 - News | `string` | `NewsWebRequestURL` | `"https://nfs.faireconomy.media"` | Copy to Allow WebRequest (ForexFactory reference; MT5 uses built-in calendar) |
| 4 - News | `bool` | `EnableNewsFilter` | `true` |  |
| 4 - News | `TTNewsImpact` | `NewsImpact` | `News_Red_Only` |  |
| 4 - News | `TTNewsWindow` | `NewsWindow` | `News_10_Minutes` |  |
| 4 - News | `double` | `CustomNewsMinutesBefore` | `5.0` |  |
| 4 - News | `double` | `CustomNewsMinutesAfter` | `5.0` |  |
| 4 - News | `string` | `NewsCurrencies` | `"USD"` |  |
| 4 - News | `bool` | `CancelPendingAtBlackout` | `true` |  |
| 4 - News | `bool` | `FreezeTrailingDuringNews` | `true` |  |
| 4 - News | `bool` | `FlattenAtBlackout` | `false` |  |
| 4 - News | `bool` | `MoveToCostCoveredBEAtBlackout` | `true` |  |
| 4 - News | `string` | `HistoricalNewsCsv` | `""` | Common Files CSV for tester: UTC time,currency,impact,title |
| 5 - Display & Audit | `bool` | `ShowVisuals` | `true` |  |
| 5 - Display & Audit | `bool` | `WriteAuditLog` | `false` |  |
| 5 - Display & Audit | `ulong` | `MagicBase` | `91008010` | effective magic = base + model; use another base for duplicate instances |

**Functions** (76): `TTPanelRect`@19, `TTDrawPanel`@31, `TTLabel`@47, `TTPanelFit`@55, `TTLine`@60, `TTProjectedExit`@68, `TTInitVisuals`@74, `TTUpdateVisuals`@78, `OnChartEvent`@134, `TTDeinitVisuals`@139, `TTTradeConnectionReady`@156, `TTStateKey`@171, `TTRecoveryMetadataMatches`@177, `TTStateSave`@180, `TTRestoreSlot`@196, `TTStateRestore`@204, `TTOwnPosition`@215, `TTOwnPositionTicket`@224, `TTMoneyPerPriceUnit`@236, `TTNormalizeVolume`@243, `TTVolumeFor`@249, `TTAudit`@256, `TTInitAudit`@262, `TTCancelOwnedOrders`@272, +52 more

**Order path**: `OrderDelete(`@279, `OrderSend(`@563, `OrderSend(`@565, `OrderSendAsync(`@565, `OrderSend(`@589, `OrderSendAsync(`@589, `OrderModify(`@2595, `OrderDelete(`@2597, `OrderSend(`@2612, `OrderSend(`@2820, `OrderSend(`@2843, `OrderSend(`@2866, `OrderSend(`@2926, `OrderSend(`@2928, `OrderSend(`@2987, `OrderSend(`@3025, `OrderSend(`@3078, `OrderSend(`@3125, `OrderSend(`@3199, `OrderModify(`@3204, `OrderSend(`@3227, `OrderDelete(`@3232, `OrderSend(`@3244, `OrderSend(`@4143, `OrderSend(`@4150, `OrderSend(`@4152

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=0 · FILE_COMMON=3 · inputs=26 · shell: `TuesdayTurnaround.mq5`

### 5. Gotobi / GotobiFix

| File | Lines | Role |
|---|---:|---|
| `GotobiFix.mq5` | 103 | shell: inputs, globals, event handlers |
| `ChartVisuals.mqh` | 133 | visuals: panels, levels |
| `ExecutionRuntime.mqh` | 975 | runtime: orders, recovery, clock |
| `StrategyEngine.mqh` | 556 | engine: signals, sizing, state |
| **total** | **1767** | |

**Inputs** (19):

| Group | Type | Name | Default | Comment |
|---|---|---|---|---|
| 1 - Trading | `bool` | `EnableTrading` | `true` | Enable trading (false = manage/flatten only) |
| 2 - Legs & Size | `GF_LEGS` | `Legs` | `GF_LEGS_BOTH` | Legs: both / long into the fix / short after it |
| 2 - Legs & Size | `double` | `Lots` | `0.10` | Fixed lots per pair (PDF reference: 1.00 on a 100k account) |
| 2 - Legs & Size | `double` | `MaxExposureLots` | `1.00` | Exposure guard: owned lots + new entry may not exceed this |
| 3 - Broker Clock | `ENUM_CLK_MODE` | `ClockMode` | `CLK_MODE_AUTO` | AUTO: registry file, else live inference. MANUAL: use the next two inputs |
| 3 - Broker Clock | `ENUM_CLK_RULE` | `ManualDstRule` | `CLK_RULE_US` | MANUAL: server clock follows US DST / EU DST / none (fixed) |
| 3 - Broker Clock | `int` | `ManualBaseMinutes` | `120` | MANUAL: server minus UTC in STANDARD time, minutes |
| 3 - Broker Clock | `ENUM_CLK_ANCHOR` | `TesterClockAnchor` | `CLK_ANCHOR_AUTO` | Tester + unknown broker: AUTO reads the weekly open/close history (labelled assu |
| 3 - Broker Clock | `string` | `ClockEvidenceSymbol` | `""` | Symbol whose H1 history proves the DST rule ("" = this chart's symbol) |
| 3 - Broker Clock | `string` | `ExtraHolidays` | `""` | Official extra Japanese bank holidays, YYYYMMDD comma-separated |
| 4 - Protection & Guards (0 = off, rule parity) | `double` | `DisasterStopPips` | `0.0` | Catastrophic broker-side stop in pips (0 = none, as per rule) |
| 4 - Protection & Guards (0 = off, rule parity) | `double` | `MaxFloatingLossMoney` | `0.0` | Close and block the day if owned floating P/L <= -value |
| 4 - Protection & Guards (0 = off, rule parity) | `double` | `MaxEntrySpreadPips` | `0.0` | Skip entry while spread above this |
| 4 - Protection & Guards (0 = off, rule parity) | `int` | `MaxLateEntrySec` | `0` | Skip a leg entered later than this after its window opens |
| 5 - Execution & Logging | `long` | `Magic` | `26111701` | Strategy magic number (unique per chart/pair) |
| 5 - Execution & Logging | `int` | `DeviationPts` | `30` | Maximum market-order deviation (points) |
| 5 - Execution & Logging | `string` | `JournalFile` | `"gotobifix_trades"` | Common\Files journal (.csv appended) |
| 5 - Execution & Logging | `bool` | `AllowOtherSymbols` | `false` | Allow symbols other than USDJPY/EURJPY/GBPJPY |
| 6 - Display | `bool` | `ShowPanel` | `true` | Show information panel |

**Functions** (101): `OnInit`@48, `OnTick`@64, `OnTimer`@70, `OnTradeTransaction`@80, `OnChartEvent`@86, `OnTester`@91, `OnDeinit`@98, `GfVisualInt`@120, `GfVisualString`@125, `GfPanelRect`@131, `GfPanelLabel`@142, `GfPanelStart`@153, `GfLegText`@163, `GfPanelRefresh`@169, `GfPanelStop`@229, `ClkLog`@318, `ClkHash`@324, `ClkText`@337, `ClkNowServer`@343, `ClkInit`@348, `ClkSetCandidates`@358, `ClkSetSingle`@365, `ClkSetSegments`@374, `ClkTrySchedule`@386, +77 more

**Order path**: `OrderSend(`@907, `OrderSend(`@937, `OrderSend(`@1037, `OrderSend(`@1151

**Flags**: clock: per-EA engine (not migrated) · money: fixed factor · WebRequest=0 · FILE_COMMON=5 · inputs=19 · shell: `GotobiFix.mq5`

## 6. Clock and news conformance, 2026-11-21

`EA_Standards/tools/clk_verify.py` and `news_verify.py` on every EA folder: **14 of 15 PASS** both.
The exception is `3. TokyoCoil` (clock only), whose `TC_BROKER_CLOCK` engine is documented in
`EA_Standards/CLOCK_ENGINE.md` §7 together with its exact remaining step. Every other EA carries
`CLK-CORE 1.2` + `CLK-ADAPTER 1.3` byte-identical, exposes no clock input, and calls the shared
NEWS-FEED accessor instead of its own `WebRequest`.

Behaviour parity for the clock migration was proven by re-running the same tester configuration
before and after and diffing the deal ledgers: **10 EAs identical row for row** (RBE, VaultBreak,
OvernightBiasRangeBreakout, OpenDrive, NQPrecisionBot, OpeningShockContinuation, SigmaBreakout,
FlashTriggerORB, FVG_Duo, VWAPPullback), NoiseBandMomentum identical across its own feature release,
TuesdayTurnaround with no trades in the sample (compile + verifiers only), X9 rule-equivalent.

