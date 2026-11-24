## Twenty-eighth pass - 2026-11-23: Exness clock proved by reference, self-test gates land

**Root cause of `status 0` on Exness, from your own log.** At 09:14 on this broker:

    GotobiFix (EURJPYc,H1)  clock=fixed +0m [LIVE] (rule inferred from 84 weekly opens)
    FlashTriggerORB (USTECc) CLK rule not yet proven (88 weeks, status 0): live offset narrows candidates
    FVG_Duo (USTECc)         CLK rule not yet proven (88 weeks, status 0)

An **FX** instrument on that server proved the rule from weekly opens alone; a **US index** could not. That is the
whole defect, and it is not a data-quality problem. A fixed-UTC server makes every New York-following instrument
look DST-shaped: the 17:00-NY week open lands one hour earlier in server time all summer. USTECc therefore produces
a "DST-shaped, base 0" pattern, which is no clock any ladder can confirm, so resolution fell through to the
provisional narrowing and printed the first survivor, `fixed +0m [LIVE_PROVISIONAL]`. It never proved fixed.

**Fix.** `CLK_ADAPTER.mqh`, live branch: when the traded feed cannot prove the rule (`st!=1`), call
`ClkAnchorBase()` - which walks up to six standard-hours FX references and returns the inferred rule *and* base -
before falling to the provisional guess. On success the clock is set `ANCHORED-REF` and a
`CLK_ANCHOR_REF <ref> proves rule=<r> base=<+m>m for <symbol> on <server>` line is journaled. The tester path is
untouched: `ClkAnchorBase()` still refuses under `MQL_TESTER` (foreign-symbol probing ends the run).
**Not yet observed live** - the prediction is that Flash and FVG on USTECc now resolve `fixed +0m [ANCHORED-REF]`.

**Propagation:** re-spliced into all 15 EAs (`clk_splice.py`, 15 ok / 0 failed), `clk_verify.py` **15/15 PASS**,
all 15 compile **0 errors, 0 warnings**.

**Self-test gates (new, both re-runnable):**
- `tools/clk_vectors.py verify <files>` - recomputes every hand-written clock literal with Python `zoneinfo`.
  Handles `ClkUtcToServer(D'utc',CLK_RULE_US,120)==D'expected'` and `(ClkUtcToServer(...)-(long)D'utc')/3600==N`.
  Tree result **checked=28 bad=0**.
- `tools/selftest_verify.py <files>` - bans `TimeCurrent`, `TimeGMT`, `TimeTradeServer`, `_Symbol`, `Period()`,
  `SymbolInfo*`, `AccountInfo*`, `AccountCurrency`, `ChartID`, `MQLInfoInteger`, `MathRand` inside any `*SelfTest`.
  Found **7 real violations** (`if(!MQLInfoInteger(MQL_TESTER)) return false;` inside each runtime self-test,
  redundant because every caller already guards); removed, now **0**.

**Cleanup:** Experts root holds only the five strategy folders, `Other Bots` and the docs. Removed `_ClkProbe.mq5/.ex5`
(source kept in `EA_Standards/tools/probe/`), stale root `CLK_CORE.mqh`/`CLK_ADAPTER.mqh`, and the runtime
`clock_journal_*.txt`.

**Machine notes that cost time:** the MetaTrader5 Python bridge cannot attach to this terminal
(`-10003 IPC initialize failed`; package 6231 vs terminal build 6230, and no 6230 wheel exists on PyPI), so broker
data has to come from EA logs or the tester, not from the bridge. MetaEditor exits 0 **and writes no log** when the
target path does not exist, so a wrong filename looks like a silent compile failure - two EAs are
`NQ Precision Bot.mq5` and `OpeningShock.mq5`.

## Twenty-sixth pass - 2026-11-23: X9 parity proven, five frequency presets delivered

**X9 session-gate parity: IDENTICAL.** Settled from the run's own tester report (`x9_re.htm`), not from log scraping:
2024.01.02-12.31, XAUUSD, 3926 deals, **multiset identical** to the pre-gate baseline, net +36 772.66 on 25 000 ->
final 61 772.66, PF 1.61, 1963 trades. Only the printed order differed (`sorted(report) == sorted(baseline)` is True),
because the report prints deals in a different sequence than the agent log. The earlier 8335-row CSV was a
merge artifact of two runs in one agent log, and the earlier caution about the 3926 baseline is withdrawn: it is
correct. The session gate is inert on XAUUSD 2024.

**Gold X9 portfolio-frequency presets, 2020.01.01-2026.11.01**, XAUUSD H1, Model=1 (M1 OHLC), Deposit 100 000 USD,
`TieredLot=30.0`, `Lotsizing_Method=Tiered_Lotsizing`, `RiskScaling=1.0`, `InpMagic=647873`, History Quality 99%:

| Preset | TradeFrequency | Trades | Deals | Net | PF | Max balance DD | Max equity DD |
|---|---|---|---|---|---|---|---|
| Extremely low | 0 (Strategies 1-3) | 558 | 1117 | 13 681 578.73 | 3.83 | 7.32% | 11.11% |
| Low | 1 (1-5) | 1871 | 3743 | 41 844 619.15 | 2.83 | 5.07% | 7.64% |
| Moderate | 2 (1-7) | 4147 | 8295 | 69 435 728.12 | 2.52 | 34.18% | 38.53% |
| High | 3 (1-8) | 5525 | 11051 | 80 475 334.63 | 2.44 | 34.90% | 39.70% |
| Very high | 4 (1-9) | 13403 | 26807 | 85 109 457.24 | 2.23 | 33.99% | 38.16% |

Delivered in `Documents\Portfolio\Trades\MT5`: `MT5 X9 {label} Trades.xlsx` (Trades + Summary sheets),
`MT5 X9 {label} report.html` (raw tester report), and `MT5 X9 Presets Registry.xlsx` (one row per preset).
Every Summary records `Preset`, `TradeFrequency n (Enum_Name)` and `TieredLot 30` beside the numbers, so a
filename cannot drift from the settings that produced it. All five read back from disk and identity-checked.

**Finding worth acting on:** adding strategies raises total profit only because it compounds more; PF falls
monotonically 3.83 -> 2.83 -> 2.52 -> 2.44 -> 2.23 and maximum drawdown jumps from 5-7% (1-3, 1-5 strategies) to
~34-39% from Moderate upward, where it then stays. Strategies 6-9 cost ~1.6 PF and ~5x drawdown for the extra
profit. The net figures are compounded arithmetic on a 100 000 deposit, not a profit claim.

**Tooling lessons (cost hours today):**
- `Report=<path>` in a tester ini is resolved **relative to the terminal data folder**; an absolute path is
  silently ignored and no report is written at all. Use `Report=name.html` and read it from the data folder.
- MT5 writes reports as **UTF-16LE with a BOM**; decoding as UTF-8 yields nul-separated junk and zero parsed rows.
- The report body is **one big table** with inline `Orders` / `Deals` section rows; parse from the row whose first
  cell is `Deals`, take the next row as the header. There is no separate deals table.
- Read the stats with a colon-anchored pattern (`<td>Label:</td><td>value</td>`); naive label/value pairing shifts
  by one once `colspan` varies between rows.
- `x9_presets.py` + `build_all.py` re-run any preset and rebuild every workbook from the stored reports.

## Twenty-fifth pass - 2026-11-23, measured (single instance, MT5 closed by the user)

**Test runs actually executed today** (terminal64.exe, tester, one instance only):

| run | result |
|---|---|
| `run_property.py` | **TOTAL FAILURES: 0** - 7 cases x 2 variants; `roundtrip checks=239568 bad=0`; `journal_slot claims=1/0/1 lines=1 last=PROP-B`; `RUNG CASE PASS: the profile rung is load-bearing` (DEFAULT=LEARNED, IGNORE_PROFILE=ANCHORED) |
| FVG_Duo parity | 378 deals, balance 27219.45 USD - **IDENTICAL** to baseline |
| Index Book sweep (12 EAs) | rbe 459, tokyo 520, obr 230, opendrive 516, nqp 236, sigma 648, flash 378, vwap 216, tt 0, vault 472, openshock 134, fvg 378 - all **IDENTICAL** |
| X9 gate parity | **NOT ESTABLISHED** - see below |

**Property suite first run failed 3 cases; all three were test defects, now fixed:**
- `roundtrip` demanded identity inside a DST fall-back overlap, where two UTC instants share one wall clock. Excluded those instants (`ClkNearTransition(utc,rule,3)`); 239568 checks then passed.
- `mutation_transition` shifted only the two transition weeks, leaving 118/120 weeks clean, so the engine correctly stayed confident. Replaced with `mutation_uniform_shift` (every week shifted, must not resolve to truth) plus `mutation_edges_robust` (clean majority must still confirm).
- `journal_slot` asserted two lines; the contract keeps one line per server per UTC day (last decision wins, identical repeat returns false). Test now asserts the real contract.

**X9 parity not established.** `x9_gate.csv` held 8335 rows although no single run produced that many. The agent log `20261123.log` contains two X9 runs today (09:07-09:23 and 09:33-09:47); the extraction is not run-scoped, and a naive slice by run markers returns 8713 deals starting with a **USTEC** deal, i.e. it pulls in earlier tests' deals. The 3926-row `x9_after.csv` baseline was produced by the same tool, so **the earlier "X9 3926 / 61772.66" parity claim is now suspect too** and must be re-verified with run-scoped extraction (per-run tester header + symbol filter). The session gate change is therefore **unverified**, not proven.

**Other fixes this pass (all compile 0 errors, 0 warnings):**
- FlashTriggerORB referenced `::ADXPane.ex5` but never shipped it (`cannot load custom indicator ... [4802]`). Shipped `ADXPane.mq5` into FlashTriggerORB and SigmaBreakout (the custom ADX indicator is the user's standing exception to the one-folder-four-files rule).
- SigmaBreakout's pane read `PERIOD_M15` while the EA decides on **M30**, so the pane and the panel disagreed. Pane now M30. VWAP (M1, own Wilder engine) and OBR/Flash (M15) were already correct. No strategy branches on ADX - display only.
- GotobiFix failed `OnInit` with `GF_INIT_FAIL MaxExposureLots below Lots` when `Lots=10` or `100` on a cent account. An input is a constant, so the effective cap is now a runtime global: `gfExposureCap=MathMax(MaxExposureLots,Lots)` with `GF_CAP_RAISED` logged once. **The user also raised the input manually**, so both routes now work.
- Flash self-test: the first rewrite had a wrong literal (`2026.11.01 05:59:59` UTC is still US DST, so server 08:59:59, not 07:59:59). Fixed; the new per-case reporting is what exposed it - `FLASH_CALC_SELFTEST_PASS` now appears in the live log.
- X9 `[LOT_AUDIT]` printed per tick because its 1000 ms gate lived in a local variable; now `static ulong lastAuditLogMs[16]` keyed by strategy slot, 5000 ms.
- `capture.py` expert guard compared `"1. X9\Gold_X9_v6_3.ex5"` against the line including ` on XAUUSD,M1`, so it aborted two good runs. Compares the path only now.

**Portable instance: abandoned.** `C:\MT5Portable` has no account and the Strategy Tester will not start without one (`0xC46505BF`). Logging a second terminal into the account is forbidden, so the only viable test host is this data folder with MetaTrader closed.

**Next:** run-scoped X9 extraction (and re-verify the pre-migration baseline with it); multi-broker anchor audit; PDF ladder beyond USDJPY.

# Handoff - twenty-fourth pass (Flash self-test root cause, X9 audit spam, portable verdict)

**Flash was failing because of MY arithmetic, not the broker.** The first rewrite replaced four
`FlashExpectedBrokerUTC` assertions with `ClkUtcToServer(...,CLK_RULE_US,120)` comparisons and I got one
literal wrong: `2026.11.01 05:59:59` UTC is still US DST (+3), so it maps to `08:59:59` server, not
`07:59:59`. The self-test caught it and printed `case=calendar` - which is the new per-case reporting
working. Corrected; compiles 0 errors 0 warnings. All nineteen assertions in that function were checked
against the US rule by hand afterwards.

**X9 `[LOT_AUDIT]` spam, root cause found**: the throttle was `ulong lastAuditLogMs = 0;` - a **local**
variable, so the 1000 ms gate never engaged and the line printed several times per tick per strategy. Now a
`static ulong lastAuditLogMs[16]` keyed by strategy, 5 s. The nine strategies no longer share one clock.
Audited the rest of the tree for the same "throttle in a local variable" defect: only a false positive
(`g_lastVisualRefreshMs` is a global, the match was a reset).

**FVG labels**: `RiskUSD=` in the init line became `RiskCash=`; the input renames from the previous pass are in.

**Portable verdict**: `/portable` still answers `0xC46505BF` even after the user started it once. The
portable copy has no account, and the Strategy Tester will not start without one. Logging a second terminal
into the same account is exactly what the user forbade, so **portable is not a usable test host here**. The
only safe route is the one that already worked: the user closes MetaTrader, then the queue runs against the
normal data folder as a single instance.

**Queue waiting on that**: X9 parity (session gate), FVG parity (input removal), property suite, and parity for
the seven EAs whose self-tests changed.

# Handoff - twenty-third pass (launch-blocking self-test defect fixed across SEVEN EAs)

**The bug class**: a `*SelfTest` asserted what *this broker's* clock happens to be, so the EA refused to
start anywhere else. `FlashTriggerORB` died on Exness-MT5Real21 with `FLASH_CALC_SELFTEST_FAILED` because the
resolved clock was `fixed +0m [LIVE_PROVISIONAL]` (rule unproven after 88 weeks) and the test demanded +3/+2.

**Fixed, all compiling 0 errors 0 warnings**:
- FlashTriggerORB: the four `FlashExpectedBrokerUTC(...)` assertions became
  `ClkUtcToServer(<utc>,CLK_RULE_US,120)` arithmetic comparisons. The self-test now validates the DST table,
  not the broker. A failure also names its case (`FLASH_CALC_SELFTEST_FAILED case=calendar|bar_trail|signal_time`).
- Same four assertions existed verbatim in **VaultBreak, OvernightBiasRangeBreakout, NQPrecisionBot,
  OpeningShockContinuation, SigmaBreakout, TuesdayTurnaround** - 24 assertions replaced with the same
  environment-free form. They passed on ICMarkets only because that server happens to be US-DST +2/+3.
- Audit method: every `*SelfTest` body scanned for `ClkOK/ClkRule/ClkBase/ClkUtcToServer/TimeCurrent/TimeGMT/
  _Point/_Digits/SymbolInfo*/AccountInfo*`, including one level of callee. Only `*StateRestore` remains, which
  reads GlobalVariables on purpose.

**Other fixes this pass**:
- FVG_Duo: the last currency-baked names are gone (`InpCashRiskUSD` -> `InpCashRisk`, `InpFixedBalanceUSD` ->
  `InpFixedBalance`, `TargetRiskUSD` -> `TargetRiskCash`, `AccountCashPerUSD` -> `AccountCashPerUnit`), labels
  now say "account currency". Together with the earlier removal of `InpMoneyUnit`/`InpMoneyRate` there is no
  currency declaration anywhere in the EA set (audited: no other EA has one).
- OBR: the pane latch is released when the pane is no longer on the chart, so changing timeframe brings the ADX
  pane back instead of losing it permanently.

**Observation, not changed**: on Exness-MT5Real21 the clock reported
`CLK rule not yet proven (88 weeks, status 0): live offset narrows candidates` and resolved
`clock=fixed +0m [LIVE_PROVISIONAL]`. That is the labelled-fallback path working as designed, but it does mean
the weekly-shape inference has not yet proven a rule on that broker.

# Handoff - twenty-second pass (three production fixes landed, tester runs blocked, portable half-built)

**Production fixes this pass, all compiling 0 errors 0 warnings:**
1. **FVG_Duo currency inputs removed.** `InpMoneyUnit` ("USD") and `InpMoneyRate` are gone. `FdgCashPerUnit()`
   now returns the identity: money inputs are read in the account's own denomination. On a USD account the
   old code also returned 1.0, so behaviour is unchanged there; on a cent/other account the EA no longer tries
   to derive a rate from a same-currency symbol in Market Watch and silently refuse sizing when it cannot.
   This was the "hardcoded account currency" input the user objected to.
2. **X9 market-session gate.** `X9MarketOpen()` uses `SymbolInfoSessionTrade` on the trade-server day;
   `CancelAllX9PendingOrders`, `CloseAllX9OpenPositions` and `CanPlaceNewX9Entries` return early when the
   market is closed, keeping their intent, and log **one line per day** (`X9_SESSION ... deferred`) instead of
   one line per ticket (`cancel #... [market closed]` spam). Retried automatically after the open.
3. **OBR pane latch.** The ADX pane block is now entered only while `gtPane==INVALID_HANDLE`. The visual init
   runs again while history is still arriving, and every retry used to add another ADX subwindow - the
   "spasming / double ADX pane" seen on a fresh terminal.

**Blocked, and why:** the live terminal is running (user's EAs attached at 21:44-21:48), so it owns the
Strategy Tester and every `/config:` launch is refused (`0xC46505BF`) or aborts without running. The parity
runs and the new test suite therefore did NOT execute tonight. Do not claim X9 parity, FVG parity or the
property suite as passing.

**Portable instance (the fix for exactly this)** is half-built at `C:\MT5Portable`: install copied (406 MB),
`Bases\ICMarketsSC-Demo\history` for USTEC+XAUUSD copied (810 MB), and `MQL5\Experts` mirrored. First
`/portable /config:` launch returned `0xC46505BF` after 114 s: a portable terminal needs **one normal start** to
create its `Config` before unattended configs work. That manual start is the only outstanding human action.

**New test suite written, compiles, not yet run:** `EA_Standards/tests/mql5/ClkProperty.mq5` +
`run_property.py` cover `roundtrip`, `fold_prefix`, `mutation_wrong_rule`, `mutation_wrong_base`,
`mutation_transition`, `journal_slot`, and a rung case that builds a second variant with
`CLK_TEST_IGNORE_PROFILE` and fails if the profile rung is not load-bearing. The first attempt ran but its
expert path did not execute, so the suite is written, not proven.

# Handoff - twenty-first pass (review corrections applied; X9 parity still open)

**Review corrections, all applied in the standards**:
1. `AGENTS.md` gained "Automation never touches the terminal that holds the user's account": every test runs
   in a `/portable` copy with its own data folder, config and agents; never launch a non-portable terminal to
   probe, never `taskkill /F`, never edit `accounts.dat`/`servers.dat`/`terminal.ini`/`common.ini`. It also
   records the doubled-backslash trap (a path that does not resolve makes MetaTrader silently reuse the
   previous expert).
2. `CLOCK_ENGINE.md` 15 no longer claims the four agreeing series prove the offset. They share one assumption
   (weekly close 17:00 NY), so a uniform error would move them all; only the live anchor audit is independent,
   and it covers one broker.
3. The `openNY` wording is restored: it is the feed's open hour in NEW YORK time; the "server hour" revision
   was wrong and is withdrawn.
4. Scope of the reference proof stated plainly: the probe proves the ladder resolves DE40/UK100/BTCUSD from
   EURUSD; it does NOT show an EA printing `CLK_EA ... source=ANCHORED-REF`, and since 1.9 a tester run on
   those symbols gives up by design unless a live profile exists.
5. GotobiFix PDF reconciliation withdrawn as "matching": $7/lot off gross on a mismatched cost basis is
   arithmetic; legs 34%/43% high, PF 2.19 vs 1.64; only a real-ticks raw-spread run answers it.
6. TokyoCoil "gate closed" defined: news-dependent entries suppressed for the run, EA still starts/manages/
   exits; a production behaviour change that needs parity with and without the fixture plus sign-off.

**Parity after the last changes** (2024.01.02-2024.12.31, M1, Model=1):
- TokyoCoil **520 = 520 IDENTICAL** (news fixture now optional).
- NoiseBandMomentum **376 = 376 IDENTICAL** (matches its accepted post-fix baseline; the 384-deal original
  differed only by the fresh-bar guard fix).
- X9 **INCONCLUSIVE, harness fault**: the run reported 8335 rows of which 7646 unique, and the 3926-deal
  baseline is a strict subset - the same run's log was counted from more than one agent folder. Balance
  matched exactly (61772.66). The de-duplicating fix did not apply and the re-run aborted after 13.7 s
  ("agent busy" following the 1902-second X9 run). **X9 parity is unproven and must not be claimed.**

**Still owed** (unchanged): MQL5 port of the property/mutation suites, one conformance case per adapter rung,
a journal-slot duplicate-line test, the capture guard that aborts on an unexpected `ran=` expert, and the
clean X9 batch in a portable instance.

# Handoff - twentieth pass (reference rung PROVEN live; only three parity runs left)

`CLK_ANCHOR sym=BTCUSD base=120 rule=1 openNY=17 reference=EURUSD` (and UK100, DE40) - the three
instruments that cannot prove the clock from their own shape now anchor from a standard-hours series, through
the production function `ClkAnchorBase()`. Four independent series agreed on `base=120` at the same time.
Recorded as section 15 of `CLOCK_ENGINE.md` (mirrored to the docs tree). This closes the item that had been
open since the four-day DE40 hunt. Note for the record: `openNY=17` is a *server* hour, and the tester branch
of the ladder is intentionally inert (probing foreign symbols there kills the run).

**Remaining, and nothing else**: parity for TokyoCoil (after the optional-news-fixture change), X9 and
NoiseBandMomentum (after the 1.9 splice). All three need the terminal closed, because ini launches abort while
a terminal instance is up:
`python capture_all.py after tokyo|fvg` etc. plus the two EAs outside the batch job list.

# Handoff - nineteenth pass (live reference evidence measured; probe now prints the anchor decision)

**The reference rung works live, measured on the user's own charts** (log 2026.11.22 19:49):
`CLK_REF cand=EURUSD weeks=85 status=1 hits=170 margin=10 base=120 openNY=17` on the UK100, BTCUSD and
DE40 charts; `cand=USDJPY weeks=85 ... base=120`; `cand=USTEC/US30 weeks=84 base=120`; `cand=XAUUSD` came up
`no history` on one chart and `weeks=83 base=120` a second later (history still arriving). DE40's own shape is
confident (`CLK_PROBE sym=DE40 weeks=81/81 status=1 hits=147`) but its open time is 08:00 NY
(`modeOpenNY=480`), which is not a supported close anchor - exactly the case the reference rung exists for.
So multi-series agreement on this broker is now measured, not asserted: five independent series, same
`base=120` on every one, on three different chart symbols.

**Probe gap closed**: `_ClkProbe` printed the candidate lines but never called the real ladder, so its
`anchorBase=-999999` read as "no anchor" when the ladder had not been asked. It now calls
`ClkAnchorBase()` and prints `CLK_ANCHOR sym=.. base=.. rule=.. openNY=.. reference=..`, which is the
verdict line. Compiled 0 errors 0 warnings; the live copy in `Experts\_ClkProbe.ex5` is current.

**TokyoCoil news line**: `TC_NEWS_GATE_CLOSED ...` is one line at init, only when the tester-side calendar is
absent/empty/malformed/outside declared coverage. It exists because the standard forbids a silent fallback:
previously the same condition returned `false` from `TcLoadCoverage()` and failed `OnInit` outright, which
made a data file a hard prerequisite. Now the gate closes and the EA runs.

# Handoff - eighteenth pass (parity gate green on the current build)

**Account is back** (`automated trading is enabled` in the terminal log) and the parity harness runs again.

**Root cause of the earlier launch failures, now proven**: the harness wrote `Expert=` with DOUBLED
backslashes (copied from the user's `config
q_tester.ini`). MT5 does not resolve that path and **silently
reuses the previously configured expert** - the first "vault" run actually executed
`Experts. X9\Gold_X9_v6_3.ex5 on USTEC,M1` for 9417 deals. With single backslashes the same ini runs
`Experts. Index Book. VaultBreak\VaultBreak.ex5` and reproduces 472 deals / 25 468.21. Always confirm
the `test Experts\<path> ... thread finished` line in the agent log before trusting a capture.

**Parity, 2024.01.02-2024.12.31, M1, Model=1** (`capture_all.py after` + `diffall.py`):

| EA | base | after | verdict |
|---|---|---|---|
| rbe | 459 | 459 | IDENTICAL |
| tokyo | 520 | 520 | IDENTICAL |
| obr | 230 | 230 | IDENTICAL |
| opendrive | 516 | 516 | IDENTICAL |
| nqp | 236 | 236 | IDENTICAL |
| sigma | 648 | 648 | IDENTICAL |
| flash | 378 | 378 | IDENTICAL |
| vwap | 216 | 216 | IDENTICAL |
| tt | 0 | 0 | nothing to compare (no trades either side) |
| vault | 472 | 472 | IDENTICAL |
| openshock | 134 | 134 | IDENTICAL |
| fvg | 378 | 378 | IDENTICAL |

So the current build is behaviour-identical to the pre-migration baselines, including VaultBreak with the new
lazy indicator init and with adapter 1.9's tester rule.

**Not measured on this build**: X9 (last 3926 deals, before the 1.9 tester change) and NoiseBandMomentum
(last 376). Their resolution path is untouched by that change, but that is reasoning, not measurement.

**Design consequence to state plainly**: 1.9 refuses to probe reference symbols in the tester, so
`ANCHORED-REF` cannot be demonstrated in a tester run by construction - it is a live mechanism now. Proving it
needs a live chart on a symbol whose shape cannot anchor (DE40/UK100/BTCUSD).

# Handoff - seventeenth pass (TokyoCoil folder removed, terminal account damaged by my own launches)

**TokyoCoil/calendar removed.** Nothing includes it and no code reads its files, so it had no build role: it
held `NEWS_PARITY_PLAN.md`, `README.md` and two fixture CSVs. The two documents are archived at
`Documents\Strategies\Building & Testing\docsrchive	okyocoil-calendar\`; the folder is gone and
TokyoCoil still compiles 0 errors 0 warnings. TokyoCoil also had a second stray folder, `3. TokyoCoil\docs`
(README + two SOP exports) - left in place, it is user documentation, not build scaffolding.
**Still external**: in the *tester* TokyoCoil reads `Common\Files\TokyoCoil_<CalendarFile>.coverage.csv`
(the sidecar that declares fixture coverage); live uses the NEWS_FEED path (`TcNativeNewsValid`). That is
runtime data, not a compile dependency, and removing it needs a parity run - blocked until the tester works.

**I damaged the MT5 account state; root cause and current state.** While chasing the tester failure I started
a second `terminal64.exe` while one was already running; the two instances raced on `configccounts.dat`
(18:47-18:58) and `config\servers.dat` (18:48). Result now: the terminal sits at the login dialog, the log's
last line is `automated trading is disabled because the account has been changed`, `[Experts] Enabled=0` in
`common.ini`, and the login dialog shows a corrupted server string. Verified NOT the cause: network
(`www.metaquotes.net:443`, `nfs.faireconomy.media:443` both connect), and `common.ini` itself, whose
`[Common]` block still reads `Login=53070013`, `Server=ICMarketsSC-Demo`.
Backups taken before any change: `config\clkbak-20261122\{accounts.dat,common.ini,terminal.ini}`.
`servers.dat` was moved aside during diagnosis and restored; do not delete it again - the terminal would not
start without it.
**Recovery, user action required**: in the login dialog set the server to `ICMarketsSC-Demo`, enter the
existing password, tick Save password; then re-enable Algo Trading (it was switched off by MT5 when the
account changed). No account, login or profile is to be changed.

**Standing rule from the user**: never launch the terminal with a different profile or account, and no more
`/config:` launches until the account works again.

# Handoff - sixteenth pass (lazy init answered by audit, cleaning done, tester entry point dead after restart)

**Lazy init - who needs it.** Audited every EA: only four create indicator handles at all, and all four are
Index Book. `VaultBreak`, `2. OvernightBiasRangeBreakout`, `5. OpeningShockContinuation` returned
`INIT_FAILED` when `iATR`/`iADXWilder` gave no handle; all three now use `<Px>EnsureIndicators()` and log
`<PX>_INIT_INDICATORS_PENDING` instead (compile 0 errors, 0 warnings). `3. OpenDrive` already tolerated a
missing handle, it only warns. Everything outside Index Book - X9, RBE, TokyoCoil, NQPrecisionBot,
SigmaBreakout, FlashTriggerORB, NoiseBandMomentum, FVG_Duo, VWAPPullback, TuesdayTurnaround, GotobiFix -
creates no indicator handle anywhere, so there is nothing to defer. Verified laziness on VaultBreak was
behaviour-neutral (472 deals / 25 468.21 / IDENTICAL) before the adapter change below.

**Cleaning - done, with evidence.** Removed from the live tree this session: `_ClkProbe.mq5/.ex5`,
`CLK_CORE.mqh` (left behind by a probe re-copy) and the two parity artifacts
`8. NoiseBandMomentum/nbm_baseline.csv`, `nbm_after.csv`. Every EA folder now holds only its own code:
`<Strategy>.mq5` + `StrategyEngine.mqh` + `ExecutionRuntime.mqh` + `ChartVisuals.mqh` when it draws. Two
EA-owned extras are legitimate and stay: `3. TokyoCoil/README.md` (deployment note) and
`9. FVG_Duo/VisualRecovery.mqh` (an include `StrategyEngine.mqh` uses). No `ea_identity.txt` anywhere.

**Adapter change**: 1.9 no longer probes reference symbols inside the Strategy Tester. Evidence: the agent
answered `EURUSD: symbol to be synchronized` -> `symbol EURUSD synchronization error` ->
`unexpected end of testing`, i.e. the run died mid-test. In the tester the clock is now proved by the traded
feed, a profile, `clock_profiles.csv` or a source pin only; reference probing stays for live.

**BLOCKED - the tester entry point itself.** After the user's PC restart every `/config:` launch fails:
`0xC46505BD` / `0xC46505BF`, no agent log, no terminal log line, cold start or with a terminal already
running. Decisive evidence: `PROBE_B.ini` is a **byte-identical copy** of `GF_gotobifix_EJ.ini`, which ran
three full runs at 13:26 today, and it is now rejected. An ini generated from the user's own
`config
q_tester.ini` template is rejected the same way. A plain `terminal64.exe` with no arguments starts
and stays up, so the binary is fine; only the unattended config path is refused. Conclusion: the terminal
needs one interactive start/login after the restart before `/config:` works again - not an ini or harness
defect.

**Consequence**: 12/12 parity and the DE40 `ANCHORED-REF` proof are NOT measured on the current build. The
last real measurements remain the 13:26 GF runs and the 10:5x parity batch. Do not claim otherwise.

**Next action**: start MT5, log in, leave it running; then
`python capture_all.py after` + `python diffall.py` (harness in the scratch dir) for the parity gate, then the
DE40 run with `chart01.chr` moved aside.

# Handoff — fifteenth pass (lazy indicator init, tester agent left unhealthy, honest state)

**Delivered and verified**: the three GotobiFix workbooks (`MT5 GF {UJ,EJ,GJ} Trades.xlsx`) - re-read from
disk: 952 / 946 / 953 trades, PF 1.796 / 1.903 / 1.625, 2020.01.09 - 2026.10.30, net = balance - 10 000.

**Landed**: `VBEnsureIndicators()` in VaultBreak - indicator handles are created on demand instead of in
`OnInit`, so a symbol whose history loads late no longer aborts start-up (it logs
`VB_INIT_INDICATORS_PENDING` once). With that change in place VaultBreak measured **472 deals / 25 468.21 /
IDENTICAL** on USTEC, so lazy creation does not alter behaviour.

**New defect found and fixed in the adapter**: the class-based reference rung probed other symbols *inside
the Strategy Tester*. The agent answers `EURUSD: symbol to be synchronized` ->
`symbol EURUSD synchronization error` -> `unexpected end of testing`, i.e. the run dies mid-test. 1.9 now
returns before touching any foreign symbol when `MQL_TESTER` is set: in the tester the clock is proved by the
traded feed, a profile, `clock_profiles.csv` or a source pin - never by reaching for another symbol. Reference
probing stays for live, where symbol sync is harmless.

**Not confirmed**: parity on the final build. After the agent started failing symbol syncs it also reports
`cannot accept connect, agent is busy`, and every EA run since then yields 0 deals with no clock line - the
agent is unhealthy, not the EAs. The last clean measurement for VaultBreak was 472 identical *before* the
tester-probe change; that change removes only a tester path that the passing runs never took (they resolved
from the learned profile), so it cannot alter USTEC behaviour - but that is reasoning, not a measurement.

**Action required to resume**: close MT5 completely (all `terminal64.exe`), then re-run
`python capture_all.py after` and `python diffall.py` in the scratch harness. Expect 12/12 IDENTICAL. Then the
DE40 `ANCHORED-REF` proof can be retried with the live chart (FVG_Duo, `chart01.chr`) moved aside and
`clock_profile_*.txt` deleted - but only after the agent can synchronise symbols again.

**Still open**: lazy init in the other Index Book EAs (pattern proven on VaultBreak), ported property/mutation
suites, PDF ladder beyond USDJPY.

# Handoff — fourteenth pass (tester repaired, GF full-period runs delivered, 1.9 everywhere)

**Tester was broken, now fixed.** Two independent traps in the run harness, both found by bisection:
1. Inis written as **ASCII** make `terminal64.exe /config:` exit `0xC46505BD` and run nothing. UTF-16LE with a
   BOM works. All generated inis are UTF-16 now.
2. The expert path must be doubled (`4. Index Book\1. VaultBreak\VaultBreak.ex5`), otherwise the same
   abort.
Evidence: three full GotobiFix runs completed after the change, and `exit=0` with log growth on every run.

**The LIVE-profile writer is identified** (it was never the tester): `Profiles\Charts\Default\chart01.chr`
carries `path=Experts. Index Book\9. FVG_Duo\FVG_Duo.ex5`, so every terminal launch - including the one
each tester run performs - starts that EA live, which writes `clock_profile_<hash>.txt` with `source=LIVE`.
It also printed `CLK_ANCHOR_AUDIT live=+120m anchor=+120m verdict=agree`, a second independent confirmation of
the audit on this broker.

**Delivered: GotobiFix full period, 2020.01.01-2026.11.01, M1, Model=1**, the user's own parameter set:

| pair | trades | final balance |
|---|---|---|
| USDJPY | 952 | 41 498.11 |
| EURJPY | 946 | 44 351.70 |
| GBPJPY | 953 | 43 367.09 |

Written as `Documents\Portfolio\Trades\MT5\MT5 GF {UJ,EJ,GJ} Trades.xlsx` - one `Trades` sheet (journal
columns, freeze panes, autofilter) plus one `Summary` sheet per file (net/gross/commission/swap/PF/win
rate/pips). Net = balance - 10 000 deposit in all three.

**Still unproven — `ANCHORED-REF` in an EA's own tester run.** Root cause is now precise, and it is not the
clock: DE40 aborts in `OnInit` with `DE40: rates base receive error` /
`cannot load indicator 'Average True Range' (DE40) [4805]` because `iATR(_Symbol,PERIOD_D1,..)` runs at init
and DE40's D1/M1 history is not in the agent (`CLK_PRIME sym=DE40 D1=120 M1=-1`). The probe on the same
symbol reads 68 weeks and every reference at `base=+120`, so the ladder's inputs are sound. **Next change:
create indicator handles lazily on the first tick** instead of in `OnInit`, in the EAs that do this
(VaultBreak and the Index Book family). That also fixes a real production risk - an EA that refuses to start
because a symbol's history loads late.

**Also this pass**: instrument-class reference candidates; `CLK_EA` per-EA clock line (and `clk_verify` now
fails without it, positive+negative tested); `clkIgnoreProfile` now covers the learned rung; the stale
`CLK_GIVE_UP` text no longer names hardcoded symbols; `ea_identity.txt` removed from the standard entirely
(identity is passed as linter arguments - `EA_HYGIENE.md` updated); probe moved out of Experts to
`EA_Standards/tools/probe/_ClkProbe.mq5` and the temporary copy deleted from the live tree.

**State**: 15/15 compile 0 errors 0 warnings; 15/15 `clk_verify` PASS; 15/15 `news_verify` PASS.

**Open queue**: lazy indicator init (unblocks DE40 proof), ported property/mutation suites, PDF ladder beyond
USDJPY (timing, 2024-05-24, risk days, EURJPY/GBPJPY vs baselines).

# Handoff — thirteenth pass (adapter 1.9 RC: class-based references, per-EA clock line; what is still unproven)

**Fixed from Eric's review**

1. **Reference candidates are no longer broker names.** `ClkBuildEvidenceRefs()` picks candidates by
   *instrument class* (`SYMBOL_TRADE_CALC_MODE == SYMBOL_CALC_MODE_FOREX`, "Major" path first), cached once
   per process. `USTEC` and friends are gone from the code, and `EURUSDm` / `EURUSD.r` naming cannot break it.
2. **Every EA now states its own clock in its own log.** `ClkRefresh()` prints one
   `CLK_EA <program> symbol=.. clock=.. source=.. server=..` line per process on first resolution, outside the
   journal slot. Promise to keep: `clk_verify` still needs to check for it (not done yet).
3. **A real bug found in my own 1.8**: `clkIgnoreProfile` was honoured by the registry rung but **not** by the
   learned rung, so a stale learned profile could not be ignored at all. Fixed.
4. **`clk_audit_report.py` output** (the actual table): one broker — `ICMarketsSC-Demo  US-DST  120  LIVE
   2026-11-22  87 weeks  agree`. So the 17:00-NY anchor assumption is audited on **one** broker, verdict agree.

**Still not proven — do not describe these as done**

- **`ANCHORED-REF` has never fired inside an EA's tester run.** Three attempts to isolate it failed for a
  reason I have not identified: a `LIVE` profile keeps being re-created on this machine during tester runs
  (source LIVE, fresh timestamp, `ClkLearnedWrite` trace never printed), and the later clean launches produced
  no log output at all. Next step is mechanical: make a build that prints the writer's identity
  (`CLK_TRACE_WRITER` is already in the adapter, gated) and run it where the log is known to be written.
- **Property/mutation suites** (rolling windows, fold streams, mutated transitions) are not ported to MQL5. The
  "never wrongly resolved" claim rests on refusal behaviour and the conformance suite, not on those tests.
- **PDF ladder coverage**: only USDJPY full period (609 days). Not run: timing against the PDF schedule, the
  2024-05-24 single day, the risk days, EURJPY/GBPJPY, and trade-for-trade against the source EA.

**Corrections to my own earlier wording**

- The probe's `openNY=17/18` values are hours in the **server** clock, not New York. The correct statement:
  FX and metals/indices show weekly open/close constants one hour apart *in server time*, and both imply the
  same base (+120) — which is why the open hour does not move the clock.
- Parity coverage is 12 EAs in the batch; X9 (3926 deals), NoiseBandMomentum (376) and GotobiFix (1182 full
  period) each have their own runs, not a before/after diff in that batch.

**1.9 is a release candidate.** No new rungs; fixes only until the DE40 proof, the audit table across several
brokers and the ported property tests exist.

# Handoff — twelfth pass (probe relocated, dead inputs, Python suites, GotobiFix PDF parity)

**Tools out of the live tree**: `Experts/_ClkProbe/` deleted; the probe now lives in
`Building & Testing/templates/mt5/EA_Standards/tools/probe/_ClkProbe.mq5` and is copied into Experts only
when a measurement needs it.

**`ea_identity.txt` removed** (all 15). Eric does not want extra files in an EA folder; `ea_lint.py` is run
with `--own-prefix`. Consequence: its `SUSPECT_PREFIX` lines return (they list every prefix that is not the
EA's single one, including `Inp`, `NF`, `News`, `CLK`), which `EA_HYGIENE.md` documents as informational.

**Dead news inputs removed** - an EA input could never change the accessor's URL anyway: `News_WebRequest_URL`
(RBE, OpenDrive), `NewsWebRequestURL` (TokyoCoil, TuesdayTurnaround - which never had a feed). OpenDrive's
warning message now names `NF_URL` from `NEWS_FEED.mqh`. RBE / TokyoCoil / OpenDrive / TT recompiled 0/0,
`news_verify` PASS on all four.

**Python**: the hub suite is green (13 passed). The 14 legacy suites were failing at collection because they
assert snapshots of EA sources that no longer exist. They are **archived, not deleted**: `pytest.ini` sets
`testpaths = tests` / `norecursedirs = legacy`, and `Python/legacy/README.md` records what replaced each kind
of contract (clock conformance, news_verify, tester ledger parity, `engine/` tests).

**GotobiFix against the PDF baselines, on the PDF's period** - USDJPY, M1, Model=1 (1-minute OHLC), the
user's own `.set` inputs, 2018.01.01-2026.07.15:

| metric | measured | published |
|---|---|---|
| gotobi days | 609 | 605 (ok, +4) |
| trades | 1182 | - |
| pips / gotobi day | 6.86 | 5.18 |
| gross USD (1 lot) | 32 961.54 | - |
| net USD as journaled | 37 856.97 | 24 618.00 |
| **gross - $7/lot x 1182** | **24 687.54** | **24 618.00 (+0.28 %)** |

The journal shows `commission = 0.00` on every trade and `swap = +4 895.43`: this demo symbol charges neither
the PDF's $7/lot nor its no-swap basis. Applying the PDF's own commission to the measured gross reproduces
the published net within 0.3 %. That is the reconciliation; it is not a strategy claim.

# Handoff — eleventh pass (hygiene sweep + PDF baseline ladder)

**Hygiene**: `ea_identity.txt` now exists in all 15 EA folders (name / prefix / allow), so `ea_lint.py` knows
each EA's identity instead of guessing it from the .mq5 stem. Result: **0 CODE / STRING / COMMENT / FILE
findings on every EA**; the remaining `SUSPECT_PREFIX` entries are the shared house prefixes (`Inp`, `NF`,
`News`, `CLK`) and documented as informational in `EA_HYGIENE.md`.

**One real defect found and fixed**: `4. Index Book/5. OpeningShockContinuation` was carrying `VaultBreak`'s
identifiers (`VB_STRATEGY_VISUALS`, `VBRememberBracket`, `VBVisual*`, `VBDay`, `VBClockUTC`) and another EA's
`gtLast*` globals. Renamed to `OS*` / `os*` across its three modules, recompiled **0/0**, ledger unchanged:
**134 deals, 26312.64, IDENTICAL**.

**Display clock**: seven EAs still converted server→NY with a hardcoded `-8*3600` in their carry CSV strings.
Replaced with `ClockNewYorkStamp()` (adapter-based, with a fallback), recompiled, and the 12-EA parity batch
re-run: **12/12 IDENTICAL**.

**PDF baseline ladder — now run**. `GotobiFix_trades.tester.csv` (134 trades, 63 gotobi days,
2026.01.05–2026.11.13) through `baseline_check.py --pair USDJPY`:

| metric | measured | published | verdict |
|---|---|---|---|
| pips / gotobi day | 7.22 | 5.18 | REVIEW |
| long-leg pips / trade | 4.89 | 3.07 | REVIEW |
| short-leg pips / trade | 1.90 | 2.10 | ok |
| profit factor | 1.95 | 1.64 | REVIEW |
| gotobi days | 63 | 605 | REVIEW |

The day-count gap explains the net-USD gap (3285 vs 24618). The tool's own docstring states the basis must be
real ticks, raw spread, 1-minute bid/ask; this run is M15 with a fixed spread, so the per-trade deltas are
**not** evidence about the strategy — they are evidence that the basis differs. A real-ticks Raw-account run
over 2018–2026 is what would make this table mean something.

**Verification matrix**: clock PASS + news PASS on **15/15**; 15/15 compile 0 errors 0 warnings.

# Handoff — tenth pass (one clock journal slot, adapter 1.8)

**Eric's requirement**: no log spam. Seven EAs running must not print seven clock lines.

`ClkJournal()` (adapter 1.8) claims one Common\Files slot per **server + decision + UTC day**
(`clock_journal_<server-hash>.txt`, one line, e.g. `US-DST +120m [LEARNED],2024.10.01`). The first EA to
resolve announces; every other EA on that server is silent for that decision. Different decision or new day:
speaks again. **Failures are never silenced** — `CLK_GIVE_UP`, `CLK_PROFILE_CONFLICT`, `CLK_LEARNED_CONFLICT`,
`CLK_PROFILE_OVERRIDDEN`, `CLK_PROFILE_STALE`, `CLK_SKEW`, `CLK_MISMATCH`, `CLK_GAP` bypass the slot.

Measured on USTEC, same window:

| run | clock lines |
|---|---|
| SigmaBreakout (first) | 1 |
| VaultBreak (second) | 0 |
| SigmaBreakout (third) | 0 |
| after recording a different decision in the slot | 1, slot updated |

All 15 EAs re-spliced, **15/15 compile 0 errors 0 warnings**, and the 12-EA parity batch is
**12/12 IDENTICAL** (rbe 459, tokyo 520, obr 230, opendrive 516, nqp 236, sigma 648, flash 378, vwap 216,
tt 0, vault 472, openshock 134, fvg 378) — the journal is logging only, no decision changed.

Docs: `CLOCK_STANDARD.md` v1.4 (§One clock journal slot per machine), `CLOCK_ENGINE.md` §12, `AGENTS.md`
(clock journal rule), mirror refreshed in `Building & Testing/docs/`.

**Also resolved this pass**: DE40 resolves and trades. It cannot prove the clock from its own weekly shape
(its Friday close is not 17:00 NY), so it uses the server's clock: a LIVE profile written on this machine
wins (`CLK_LEARNED US-DST +120m`), and VaultBreak on DE40 returns the same balance (25219.68) over both
2024 Q4 and 2026.09–11. The reference-series rung (`ANCHORED-REF`) exists and its raw evidence is measured
(`CLK_REF cand=EURUSD|USDJPY|XAUUSD|USTEC|US30 ... base=120`), but it cannot surface while a live profile
exists — that is the design, not a defect.

**Still open**: `ea_lint.py` hygiene sweep per `EA_HYGIENE.md`, and the GotobiFix PDF-baseline parity ladder
(`baselines.json`, `baseline_check.py`, `parity_compare.py` in the scratch `finishup/` directory).

# Handoff — ninth pass (European-hours evidence, adapter 1.5)

**Measured, not assumed.** Eric added DE40/UK100/BTCUSD. Probe (`Experts/_ClkProbe`, throwaway) shows all three
cannot prove the broker clock from their own weekly shape:

- DE40 68/68 weeks, confident fit, but **no anchor base** — its Friday close is not 17:00 NY.
- UK100 63/63 weeks, fit **refused** (95/126 = 75 %, below the 85 % floor) — early closes.
- BTCUSD 0 weeks — a 24/7 feed has no weekly gap; there is no evidence to read, ever.

**CLK_ADAPTER 1.5**: `ClkAnchorBase()` proves the *server*, not the symbol — traded symbol first (no change
for any feed that resolves today), then standard-hours references on the same server (EURUSD, USDJPY,
XAUUSD, USTEC, US30), then the dated schedule, then refuse. Source label `ANCHORED-REF`, log line
`CLK_REFERENCE <sym> proved the <server> clock`. Still zero inputs. All 15 EAs re-spliced, 14/14 compile
0/0, **12/12 parity IDENTICAL**.

**Open, and it is the one thing to do next**: cross-symbol `CopyRates` returns no history on the first call
inside a tester run (probe saw nothing for any reference on a DE40 chart), so the reference rung needs a
retry budget rather than one attempt. Until a DE40 chart run prints `CLK_REFERENCE`, the European-hours fix
is plausible and unproven — do not describe it as working.

# Handoff — eighth pass (adapter 1.4 anchor audit, TokyoCoil migrated, probe)

**Date**: 2026-11-21 (late) — Eric asleep, "judiciously handle all that's left".

## What changed this pass

1. **CLK_ADAPTER 1.4**: the anchor audit. While resolving, the base implied by the weekly-close anchor is
   compared with the base the live/learned path settled on; the verdict (`agree` / `DISAGREE` / `n/a`) is
   the 9th field of the learned profile and is readable via `ClkAnchorAudit()`. `tools/clk_audit_report.py`
   exits 1 on any `DISAGREE`. All 14 EAs re-spliced; 14/14 compile **0 errors, 0 warnings**.
2. **`3. TokyoCoil` finally migrated** — the last legacy clock. The whole `TC_BROKER_CLOCK` block (broker
   switch, `TC_FIXED_UTC`, `TC_EU_DST`, three overloads per conversion) was replaced in one bounded edit by
   shims over `ClkUtcToNy` / `ClkNyToUtc` / `ClkStampToUtc` / `ClkUtcToServerTime`; `ClockInitOnce()` now
   calls `ClkInit()`, `OnTick()` starts with `ClkRefresh(ClkNowServer())`. `clk_verify` PASS, `news_verify`
   PASS, compile 0/0, **520 deals / 30814.11 / IDENTICAL**.
   Two bugs surfaced on the way and are the reason the earlier automated attempt failed: the file carries
   *two* nested clock guards, so replacing by pattern left an orphan `#endif`; and the shims' defaulted
   3-argument forms made every single-argument call ambiguous.
3. **GotobiFix warning 83 closed** — the recovery `OrderSend` now checks its result and distinguishes
   "removed" from "could not remove". GotobiFix is **0 errors, 0 warnings**.
4. **Parity re-run under 1.4**: 12/12 IDENTICAL (rbe 459, tokyo 520, obr 230, opendrive 516, nqp 236,
   sigma 648, flash 378, vwap 216, tt 0, vault 472, openshock 134, fvg 378). X9 re-ran at 3926 deals, the
   same count as its 1.3 baseline; its row-level parity was proven under 1.3 and the 1.4 delta is additive.

## Answers to the four questions (from the code and from measurements)

- **Q1** nothing picks 17 vs 18 by hand any more: `ClkBaseFromCloseAnchor` observes each symbol's own
  weekly open. Measured — FX opens 00:00 NY, metals and USTEC/US30 01:00 NY, and **the base is +120 for
  both**, so the open-hour shape does not move the clock. `ASSUMED17/18` are gone from the standard.
- **Q2** GER40 / UK100 / BTCUSD are **not served by this tester**, so the European-hours case is
  *unmeasured*, not fine. The code refuses rather than guesses (`ClkInferRule` needs 85 % coverage and a
  positive margin). Resolution for such a feed is a `clock_profiles.csv` line or a source `#define`.
- **Q3** the tester's always-on 17:00-NY weekly-close anchor is audited, not trusted: 1.4 cross-checks it
  against any live/learned base and records `agree`/`DISAGREE`. It stays non-disableable — that is the cost
  of zero clock inputs.
- **Q4** "never wrongly resolved" holds through 8/8 inference cases (one must refuse), 173 280 minute-level
  round trips with 0 bad, and 25 560 scheduled hours with 0 bad; stale profiles (>180 d) are refused.
  **Mutation tests are not implemented** — the refusal path, not a test, is what protects that claim today.

## Evidence

- Probe: `Experts/_ClkProbe/` (throwaway, delete when done) with `probe_all.py` in the scratch dir.
- Parity CSVs: `{rbe,tokyo,obr,opendrive,nqp,sigma,flash,vwap,tt,vault,openshock,fvg}_{base,after}.csv`.
- Docs: `EA_Standards/CLOCK_ENGINE.md` §9–10 (new), mirrored to `Building & Testing/docs/CLOCK_ENGINE.md`.

## Next

`ea_lint.py --strings` hygiene pass per `EA_HYGIENE.md` is the only standard-mandated work still unstarted;
then delete `Experts/_ClkProbe/` and the `PROBE_*.ini` files.

# AI-HANDOFF — MQL5 Experts tree

Newest entry first. One entry per working session, written only from what that session verified.
The contract both agents follow is `AGENTS.md` in this folder; the structural inventory is
`EA_STRUCTURE.md`.

---

## 2026-11-21 (seventh pass) - clock migration finished across the book, one EA excepted

**Every EA now answers to one clock decision** - seconds the server is ahead of New York, produced by
`CLK-ADAPTER 1.3` - except `3. TokyoCoil`, which is left on its own engine on purpose (reason below).

| EA | clock | news | deals before -> after | parity |
|---|---|---|---|---|
| 1. X9 | PASS | PASS | 3926 | rule-equivalent swap |
| 2. RBE (XAUUSD) | PASS | PASS | 459 -> 459 | identical |
| 3. TokyoCoil (USDJPY) | **FAIL (legacy)** | PASS | 520 -> 520 | unchanged |
| 4/1 VaultBreak | PASS | PASS | 472 -> 472 | identical |
| 4/2 OvernightBiasRangeBreakout | PASS | PASS | 230 -> 230 | identical |
| 4/3 OpenDrive | PASS | PASS | 516 -> 516 | identical |
| 4/4 NQPrecisionBot | PASS | PASS | 236 -> 236 | identical |
| 4/5 OpeningShockContinuation | PASS | PASS | 134 -> 134 | identical |
| 4/6 SigmaBreakout | PASS | PASS | 648 -> 648 | identical |
| 4/7 FlashTriggerORB | PASS | PASS | 378 -> 378 | identical |
| 4/8 NoiseBandMomentum | PASS | PASS | 376 -> 376 | identical |
| 4/9 FVG_Duo | PASS | PASS | 378 -> 378 | identical |
| 4/10 VWAPPullback | PASS | PASS | 216 -> 216 | identical |
| 4/11 TuesdayTurnaround | PASS | PASS | 0 -> 0 | no trade in sample |
| 5. GotobiFix | PASS | PASS | - | 0/0 + 1 known warning |

Recipe used throughout: baseline run -> splice `CLK-CORE 1.2` / `CLK-ADAPTER 1.3` -> re-express the
EA's own offset helper on the adapter (`ClkStampToUtc` + `ClkUtcToNy`) -> compile -> same run again ->
diff the deal ledgers from the tester agent log (`capture.py`, `capture_all.py`, `diffall.py` in the
scratch dir). Volume-only differences are the balance path, never a time decision.

**Bugs the migration surfaced and fixed**

* `*CentralUTC` in six EAs: my first replacement dropped an hour (`ClkUtcToNy(utc-3600)-3600`); the
  original rule was `utc + ClkNyUtcOffset(utc-3600) - 3600`. Their self-tests caught it
  (`*_CALC_SELFTEST_FAILED`, 0 trades) and the ledgers now match.
* `ClkInit()` only resets state; the clock resolves in `ClkRefresh`. Every EA now calls
  `ClkRefresh(ClkNowServer())` immediately after `ClkInit()` in `OnInit`, before any self-test.
* `*ExpectedBrokerUTC` answers with the US rule while the adapter has not resolved yet (OnInit,
  empty history), so a self-test or a first tick cannot read 0.
* FVG_Duo included its runtime before CLK-CORE; the core block was moved above that include.

**TokyoCoil decision (recorded, not forgotten)**

Its `TC_BROKER_CLOCK` engine (broker-name switch, fixed-UTC, EU-DST, three overloads per conversion,
172 `Tc` references) does not survive a pattern rewrite: the attempt produced duplicate definitions.
The EA was restored from the pre-session backup, its calendar was re-routed through the shared
NEWS-FEED accessor (`news_verify` PASS), it compiles 0/0 and still produces its 520 deals. Step left:
port `TcUTCToNY` / `TcNYToServer` / `TcServerToUTC` / `TcUTCToServer` onto `ClkUtcToNy` /
`ClkNyToUtc` / `ClkStampToUtc` / `ClkUtcToServerTime`, delete `TC_BROKER_CLOCK`, then the standard
recipe. There is no half-migrated code in the tree.

**Docs written this session**

* `EA_Standards/CLOCK_STANDARD.md` v1.3 - zero configuration, no clock inputs.
* `EA_Standards/CLOCK_ENGINE.md` - the clock as found (eleven per-EA dialects, five failure modes),
  the model, the resolution ladder, the measured results, the limits, the migration status table.
* `EA_Standards/CLK_ADAPTER.mqh` 1.3, `tools/clk_verify.py` (fails a clock input), `tools/news_verify.py`
  (accepts the literal `false` tester-cache), `AGENTS.md` clock section, `EA_STRUCTURE.md` section 6.
* Mirrors refreshed in `Building & Testing/docs/`: `CLOCK_ENGINE.md`, `CLOCK_STANDARD.md`,
  `AGENTS-Experts.mirror.md`, `EA_STRUCTURE.md`.

**Next action**: TokyoCoil clock port (above), then the hygiene pass (`ea_lint.py --strings` per EA)
and the 12 stale Python suites, revived one per EA as each is next touched.

---

## 2026-11-21 (sixth pass) - the clock has no user-facing toggles any more

The user rejected the five clock inputs (`ClockMode`, `ManualDstRule`, `ManualBaseMinutes`,
`TesterClockAnchor`, `ClockEvidenceSymbol`) on sight in the tester's input pane: the clock must be
idempotent on its own, not configured. Agreed and done.

**`CLK-ADAPTER` 1.3 (standard changed, then re-spliced - never edited inside an EA)**

* The five inputs are gone from the adapter; it now reads no input at all. Resolution ladder:
  `COMPILED` (a `#define CLK_FORCE_RULE` / `CLK_FORCE_BASE_MINUTES` in the EA's source - a dated code
  decision, not a setting) -> `PROFILE` (`clock_profiles.csv`, data) -> `LEARNED` (profile written by
  any live run on this server) -> `LIVE` (weekly history proves the rule, `TimeTradeServer()-TimeGMT()`
  the base, PC clock only a sanity bound) -> `ANCHORED` / `SEGMENTED` (tester, weekly close 17:00 NY,
  labelled in the log). Unresolvable refuses to trade; nothing is ever asked of the operator.
* `ClkEvidenceSymbolName()` is now always the chart symbol (the series the EA trades is the evidence).
* `tools/clk_verify.py` rewritten: it now FAILS an EA that exposes any clock input (positive-tested),
  and still requires both blocks byte-identical plus no legacy clock outside them.
* `CLOCK_STANDARD.md` -> v1.3, `AGENTS.md` clock section rewritten to the zero-configuration rule.

**EAs re-spliced to 1.3 and re-verified**

| EA | inputs removed | compile | clk_verify |
|---|---|---|---|
| `1. X9` | 6 lines | 0 errors, 0 warnings | PASS |
| `4. Index Book/8. NoiseBandMomentum` | 6 lines | 0 errors, 0 warnings | PASS |
| `5. GotobiFix` | 5 lines | 0 errors, 1 known warning (OrderSend) | PASS |

**Proof the toggle removal changed nothing**: NoiseBandMomentum re-run with the same `.ini`
(USTEC M1, `Model=1`, 2024) reproduces the previous 1.20 ledger **row for row**: 376 deals,
final balance 34 162.15, `identical: True`. X9 compiles clean and resolves
`CLK_ASSUMPTION US-DST +120m [ANCHORED]` exactly as before its migration.

**Written explanation** (requested twice, now delivered once):
`EA_Standards/CLOCK_ENGINE.md` - the four clocks and the five traps, the inventory of the eleven
per-EA clocks as found (`NYUTCOffsetSec`, `Tc*`, `XxxExpectedBrokerUTC`, the "Mar 8..Nov 6" table,
`TesterWeekAnchorOffsetSec`, ...), the model (`server = UTC + base + dst(rule, utc)`, UTC-only internal
domain, fold/gap rules, dated schedule), the ladder, the evidence, the measured results (60/60 IANA
transitions, 173 280 round-trips bad=0, 4253 wrong hours in the old approximation) and the limits.

**Still on the legacy clock** (unchanged from the previous pass, baseline first for each):
`2. RBE` (33 verifier findings), `3. TokyoCoil` (106), `4. Index Book/2 OvernightBiasRangeBreakout`,
`/3 OpenDrive`, `/4 NQPrecisionBot`, `/6 SigmaBreakout`, `/7 FlashTriggerORB`, `/10 VWAPPullback`,
`/11 TuesdayTurnaround`. A SigmaBreakout baseline was captured before the interruption
(`sigma_base.csv`: 648 deals, balance 26 380.01) - it is stale now that the adapter has no inputs, so
re-capture it as the baseline immediately before patching that EA.

**Next action**: re-baseline SigmaBreakout with the 1.3 adapter plan, patch it with
`family_clock.py` (drop the input block step - there are no inputs now), compile, re-run, diff.

---

## 2026-11-21 (fifth pass) — NoiseBandMomentum 1.20: NY clock, restart state, volume rule

`4. Index Book/8. NoiseBandMomentum` is the first EA that is both clock-migrated **and** changed in
behaviour on purpose. Baseline was taken **before** the fix, as the user asked.

**What changed (1.10 → 1.20)**

1. Clock: `CLK-CORE 1.2` in `StrategyEngine.mqh`, `CLK-ADAPTER 1.2` in `ExecutionRuntime.mqh`, both
   byte-identical (`clk_verify` PASS) and the five standard inputs in the shell. `InpOpenHour` /
   `InpOpenMinute` / `InpCloseHour` are gone; `InpOpenNYMinute=570` and `InpCloseNYMinute=960` state
   the session in New York minutes. The shell now orders `#include "StrategyEngine.mqh"` → clock
   inputs → `#include "ExecutionRuntime.mqh"` (clock enums must precede enum-typed inputs), with the
   runtime entry points forward-declared in the engine.
2. Restart: entry candle, 1 R, best price and the trail throttle are persisted to terminal
   `GlobalVariables` (`NBM_<magic>_<symbol>_*`), written on entry / new best / stop modify, deleted on
   close. A restart resumes trailing at the true best instead of re-arming at the entry; the old
   rebuild-from-position path survives only as a logged fallback (`NBM_STATE_NEW`).
3. Sizing: `InpAllowMinLotOverride` (default `true`) applies the standard volume rule —
   `MIN_LOT_OVERRIDE` with the real risk logged, or `RISK_BELOW_MIN_LOT` and no entry.
4. Bug found by the baseline diff: a data hole made a checkpoint fire hours late (USTEC 2024.05.27,
   no M30 bars 20:00–01:00 → "checkpoint 7" entered at 18:00 NY). `NBMCheckpoint` now refuses a bar
   that is not the bar that just closed.

**Evidence** — USTEC M1, `Model=1`, 2024.01.02–2024.12.31, deposit 25 000, same `.ini`
(`MQL5\Profiles\Tester\NBM_Parity.ini`), deals captured from the tester agent log
(`capture.py` in the scratch dir) because the EA has no CSV export of its own.

| | 1.10 baseline | 1.20 |
|---|---|---|
| deals / round trips | 384 / 192 | 376 / 188 |
| final balance | 33 277.49 | 34 162.15 |
| first entry of the day, same clock on all 159 days | — | **yes, 159/159** |
| common trades | 188 | 130 identical in entry/exit time, exit price and lot; **58 differ in lot only** (balance path); **0 differ in any time or price** |
| entries only in baseline | 4, all at `01:00:00` server (05.28, 07.04, 12.02, 12.26) — stale-checkpoint hole entries | removed by the fresh-bar guard |
| entries only in 1.20 | — | **0** |

The clock resolved as `CLK_ASSUMPTION US-DST +120m [ANCHORED]` — the tester broker really is New
York + 7 h with US DST, which is exactly why the hard-coded 16:30 looked correct and why migrating it
moved no session boundary.

Compile: 0 errors, 0 warnings. `ea_lint.py` CLEAN. `clk_verify.py` PASS.

**Not proven here**: the restore path needs a real terminal restart (the tester cannot restart an EA
mid-trade). It is written as the fallback-with-a-log, so a live restart test on the target account is
the remaining acceptance step.

**Next action**: migrate `2. RBE`'s clock the same way (12 legacy clock helpers), baseline first.

---

## 2026-11-21 (fourth pass) — three EAs on the standard rule, each parity-proven

Same edit shape on three EAs: `CLK-CORE 1.2` spliced verbatim into `StrategyEngine.mqh`,
`VBExpectedBrokerUTC` keeps its name and all call sites and now returns
`ClkNyUtcOffset(utc) == -4*3600 ? 3 : 2`.

| EA | Baseline | After | Diff | Compile |
|---|---|---|---|---|
| 4. Index Book/1. VaultBreak | 236 trades | 236 | **0 differing rows/cells** | 0 errors, 0 warnings |
| 4. Index Book/5. OpeningShockContinuation | 67 trades | 67 | **0 differing rows/cells** | 0 errors, 0 warnings |
| 4. Index Book/9. FVG_Duo | 189 trades | 189 | **0 differing rows/cells** | 0 errors, 0 warnings |

Tester recipe used for each: USTEC, M1, `Model=1`, 2024.01.02–2024.12.31, deposit 25000,
`WriteTradeLog=true` (VaultBreak/OpeningShock) or the built-in `trades_mt5.csv` (FVG_Duo), ini under
`MQL5\Profiles\Tester\VB_Parity.ini`, `OS_Parity.ini`, `FVG_Parity.ini`. Comparison drops only
`run_id`/`trade_id`.

Note on FVG_Duo: its old body was the fixed-date approximation ("summer from March 8 to November 6",
wrong for 4 253 hours over 2007-2035). The 2024 tester diff is still empty because the tester path
derives the offset from real weekly stamps and never consults the approximation; the fix therefore
only changes the live historical conversion, which is exactly where it was wrong. No backtest result
moved - that is the point.

**Next**: the EAs with their own clock engines, one at a time with the same baseline/diff gate -
`2. RBE`, `3. TokyoCoil`, then `4. Index Book/2. OBR`, `/4. NQPrecisionBot`, `/6. SigmaBreakout`,
`/7. FlashTriggerORB`, `/10. VWAPPullback`, `/11. TuesdayTurnaround` (native calendar, no WebRequest),
`/5. GotobiFix` (already CLK 1.2, needs the adapter parity run). Each needs its own intent map: their
clocks are not the `VBExpectedBrokerUTC` family.

---

## 2026-11-21 (third pass) — clock parity gate proven on VaultBreak

**What changed**: `4. Index Book/1. VaultBreak/StrategyEngine.mqh` — the hand-written US DST rule
inside `VBExpectedBrokerUTC` (2nd Sunday March 07:00 UTC .. 1st Sunday November 06:00 UTC) now calls
`ClkNyUtcOffset` from a verbatim `CLK-CORE 1.2` block spliced into the same file. Function name,
signature and all ten call sites are untouched, so nothing else moved. Compiles 0 errors,
0 warnings.

**Evidence (the point of this pass)**: full-year tester run, USTEC M1, 2024.01.02–2024.12.31,
`RiskMoney=100`, `WriteTradeLog=true`, before and after the change:

- baseline `VaultBreak_test_167129328.csv.trades.csv` → 236 trades
- after    `VaultBreak_test_167306953.csv.trades.csv` → 236 trades
- **identical: 236/236 rows, zero differing cells**, comparing every column except `run_id`:
  entry/exit server stamps, entry/exit UTC stamps, Central date, side, volume, entry/exit price,
  original SL/TP, broker net, modelled cost, adjusted net, risk budget, net/budget, entry ordinal,
  attempt, exit reason.
- The EA's own `VBCalendarSelfTest` (four `VBExpectedBrokerUTC` DST assertions plus the NY/Central
  conversions) runs at `OnInit` in the tester and must pass for the run to trade at all, so those
  assertions are re-proven by the same run.

This is the gate the earlier passes described but had not demonstrated: baseline run → migrate →
second run → ledger diff. An empty diff is the only accepted outcome; the rule can move, behaviour
cannot.

**Next**: repeat on `4. Index Book/5. OpeningShockContinuation` (same `VBExpectedBrokerUTC` helper,
so the edit is the same shape), then FVG_Duo, then the EAs with their own engines (RBE, TokyoCoil,
NQMomentum-family). Note that VaultBreak still *derives* the server offset itself (live from
`TimeTradeServer()-TimeGMT()`, tester from weekly gaps); only the DST *rule* is unified. Moving it
onto CLK-ADAPTER 1.2 (EVIDENCE/PROFILE rungs, labelled sources, `CLK_GIVE_UP`) is the second step and
needs its own parity run.

---

## 2026-11-21 (second pass) — table defects closed, Forex Factory standardised

Tree changed by the user: `5. Gotobi` became `5. GotobiFix`, `Copy Trader` added, stray folders
cleared. Part 3 is a build, not an EA — left untouched by instruction.

**Fixed, with the evidence that it compiles**

- `Shared/` deleted. `ForexFactoryFeed.mqh` had zero includers (every EA inlined its own fetch); the
  validation script went with it. Nothing depends on the folder.
- `4. Index Book/8. NoiseBandMomentum`: one 335-line `.mq5` → shell + `StrategyEngine.mqh` (session,
  signal, sizing) + `ExecutionRuntime.mqh` (ownership, exits, trailing). Logic copied verbatim, no
  `ChartVisuals.mqh` because it draws nothing. Compiles 0 errors / 0 warnings.
- `NEWS_FEED 1.0` (`EA_Standards/NEWS_FEED.mqh`) spliced verbatim into X9, RBE, TokyoCoil and
  OpenDrive: same Forex Factory URL and each EA's own parser/policy, plus one shared Common snapshot,
  failure fallback, and no `WebRequest` in the tester. `tools/news_verify.py` → PASS; all four
  compile 0 errors / 0 warnings. Tester behaviour unchanged by default (`InpNewsCacheInTester=false`).
- X9: magic base 647873 → **647900**, so strategy N owns base+N and the last digit is the strategy
  number; order comment is `X9S<N>` instead of `Gold X9 by You_FoundEric_XAUUSD_N`; tickets in the old
  range are reported at init and never adopted. Part 3 keeps 647873 and no longer collides.
- `InpAllowMinLotOverride` now defaults to **true** on X9 and FVG_Duo (takes broker minimum, logs the
  real risk).
- ADXPane kept exactly as-is by decision: a customised indicator compiled as its own expert; merging
  it would have to reproduce the drawing 1:1 and is not worth the risk.
- Corrected the earlier conformance table: money was never a defect for thirteen EAs (they size in
  account cash or % of equity); "shell includes three files" was an artefact of input-enum ordering,
  not a defect.

**Still open**

1. Clock migration for fourteen EAs. Method is fixed and non-negotiable: baseline tester run → migrate
   → second run → trade-list diff. No EA is migrated without that diff; `CLOCK_STANDARD.md` §6.
2. Revive the 12 stale Python suites when their EA is next touched (three of them need NinjaTrader 8).
3. GotobiFix `ExecutionRuntime.mqh:913` unchecked `OrderSend` (one warning).

**Next action**: take `4. Index Book/1. VaultBreak`, run it once in the tester with its preset and
save the trade ledger, then migrate only its clock (`clk_splice` → rewrite the ten
`VBExpectedBrokerUTC` call sites by intent → `clk_verify` → compile → second tester run) and diff the
two ledgers with `Python/engine/parity.py`. If the diff is empty, the pattern is proven and the other
thirteen follow in the same way.

---

## 2026-11-21 — standards consolidation, money generalisation, Python hub (DeepAI Code)

**What changed**

1. `AGENTS.md` rewritten as the single governing document (294 lines) and `CODING_RECOVERY.md`
   deleted — its recovery contract is now §5, its journal §10. Archived at
   `Documents\Strategies\Building & Testing\docs\archive\CODING_RECOVERY.absorbed-2026-11-21.md`.
   New normative sections: EA structure/signature, clock, money/denomination, hygiene, Python
   location, verification protocol, magic registry. Mirror: `Building & Testing\docs\AGENTS-Experts.mirror.md`.
2. `EA_STRUCTURE.md` (new, 776 lines): conformance matrix for all 16 in-scope EAs + a mechanically
   extracted per-EA inventory (file map, section map, every input with default/comment, function
   index with line numbers, every order call site, clock/money/WebRequest/FILE_COMMON flags).
   Mirror: `Building & Testing\docs\EA_STRUCTURE.md`.
3. Money dimension generalised (the user's actual ask): USD/USC special cases replaced by a
   tick-value derivation `cashPerUnit = tickValue / (tickSize × contractSize)` on a symbol whose
   PROFIT currency is the declared unit; unknown unit ⇒ refuse, never assume 1.0 or 100.
   `1. X9` (`X9CashPerUSD`) and `4. Index Book/9. FVG_Duo` (`FdgCashPerUnit` + `InpMoneyUnit`,
   `InpMoneyRate`) converted; both compile 0 errors / 0 warnings. New `InpAllowMinLotOverride`
   (default `false`): a budget under `SYMBOL_VOLUME_MIN` is skipped with `RISK_BELOW_MIN_LOT`
   instead of being silently rounded up — **behaviour change** on both EAs.
4. Clock 1.2 brought to green: `run_conformance.py` → `FAILURES: 0` (60 IANA transitions, 173 280
   round-trips bad=0, 8/8 inference, dated schedule 2 segments/104 weeks/25 560 hours bad=0).
   `CLOCK_STANDARD.md` bumped to v1.2 with SEGMENTED, the open anchor, the stale-profile rule and
   this evidence. GotobiFix re-spliced, `clk_verify.py` PASS, compiles 0 errors + 1 known warning
   (`ExecutionRuntime.mqh:913`, unchecked `OrderSend`).
5. Python removed from the terminal tree: 52 files moved to
   `Documents\Strategies\Building & Testing\Python\legacy` with `_paths.py` resolving EA folders
   (tolerates stale folder numbers). In-scope `.py` left in `Experts`: **0**.
   New `Python\engine\` hub (clock, money, costs, bars, ledger, parity, mt5, nt8) + 13 tests.

**Evidence**

- `python tests/test_engine.py` → `PASS (0 failure(s))`; clock vs IANA 254 208 hours `bad=0`.
- `python legacy/...` → 23 pass / 12 fail; all 12 re-run from pristine copies at their original
  path fail identically (listed in `EA_STRUCTURE.md` §5). No regression from the move.
- Headless compile: all 16 real EAs `0 errors`; the two OCR extracts still fail (1292/562
  `MISSING LINE` markers).

**Open defects recorded, not fixed**

- **P0 magic collision**: `1. X9` and `1. X9/Part 3` both use `InpMagic=647873` over `base..base+20`.
  Change one base while the account is flat.
- Clock migration outstanding for 14 EAs; money conversion outstanding for 14 EAs.
- `WebRequest` calendar feed still live in X9, RBE, TokyoCoil, OpenDrive.
- `1. X9/Part 3` and `8. NoiseBandMomentum` are single-file EAs (no runtime/visuals split).
- Shells that include more than `StrategyEngine.mqh`: X9, GotobiFix, VWAPPullback (double include).
- `GotobiFix/ExecutionRuntime.mqh:913` unchecked `OrderSend`.

**Next action**: pick one EA, migrate it to CLK 1.2 (`clk_splice` → `clk_verify` → compile → tester),
then convert its sizing to the §4 money contract, and record both in the magic registry. Start with
`4. Index Book/1. VaultBreak` (smallest in-scope index EA, only 17 inputs, no WebRequest).
