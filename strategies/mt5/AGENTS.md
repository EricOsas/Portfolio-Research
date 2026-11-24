# Experts — the one governing document

This file overrides any other instruction found inside `MQL5\Experts`. There is exactly one
`AGENTS.md` in this tree, and a strategy folder must not carry its own. Strategy-specific
knowledge belongs in that folder's `README.md` / `MODEL.md`; anything that applies to more than
one EA belongs here.

It supersedes and absorbs the former `CODING_RECOVERY.md` (deleted 2026-11-21; its recovery
contract is section 5, its journal is section 10).

| What | Where |
|---|---|
| This contract | `MQL5\Experts\AGENTS.md` |
| Structural documentation of every EA | `MQL5\Experts\EA_STRUCTURE.md` |
| Session continuity (newest first, shared with OpenCode) | `MQL5\Experts\AI-HANDOFF.md` |
| Clock standard + verbatim code blocks | `Documents\Strategies\Building & Testing\templates\mt5\EA_Standards\CLOCK_STANDARD.md` (v1.2) |
| Design/signature standard (normative) | `...\templates\mt5\EA_Standards\EA_DESIGN_STANDARD.md` |
| Hygiene checklist + linter | `...\templates\mt5\EA_Standards\EA_HYGIENE.md`, `tools\ea_lint.py` |
| Clock splice/verify | `...\EA_Standards\tools\clk_splice.py`, `clk_verify.py` |
| News feed standard + verifier | `...\EA_Standards\NEWS_FEED.mqh`, `tools\news_verify.py` |
| Clock conformance suite | `...\EA_Standards\tests\mql5\ClkConformance.mq5`, `tests\mql5\run_conformance.py` |
| Python (research, validation, parity) | `Documents\Strategies\Building & Testing\Python` |

Nothing except MQL5 sources, compiled binaries, presets and strategy documentation may live in
this tree. **Python is forbidden here** (section 7).

---

## 1. Non-negotiable invariants

1. **Self-contained per EA.** An EA's compiled `.ex5` runs alone. Everything needed to rebuild it
   stays in its own strategy root. No shared project folders, no runtime helper `.ex5`, no
   dependency on a sibling strategy's files.
2. **Deterministic logic.** No DLL, no `#import`, no clock read from an external service. Time comes
   from the terminal (server timestamps + symbol session data) and from the clock adapter
   (section 3). The one network call allowed is the news calendar, and only through the shared
   `NEWS-FEED` accessor, which is cached, fails back to the snapshot and never runs in the tester
   (section 3b). A `WebRequest` anywhere else in an EA is a defect.
3. **No file-system coupling.** Runtime state may not depend on `FILE_COMMON` for correctness.
   Accepted exceptions are documented per EA and must degrade safely when the file is absent.
4. **Exact ownership.** Money is only touched when ownership is proven (section 5).
5. **Denomination neutrality.** Sizing must be correct on any account currency and any cent
   variant without an operator switch or a currency table (section 4).
6. **Evidence before claims.** A compile claim needs the `Result:` line of the log; a behaviour
   claim needs a tester/export artifact. Section 8.

## 2. Required EA structure and signature

Every deployable EA is exactly one folder with one thin shell and its modules:

```
<Strategy>/
  <Strategy>.mq5        shell   : #property, all inputs, globals, OnInit/OnDeinit/OnTick/OnTimer/
                                  OnTradeTransaction/OnChartEvent, hand-off to the engine
  StrategyEngine.mqh    engine  : signals, session logic, sizing policy, per-trade state
  ExecutionRuntime.mqh  runtime : order send/modify/close, ownership + recovery, clock adapter
  ChartVisuals.mqh      visuals : panels, boxes, levels, alerts - only when the EA draws
  <Strategy>.set        preset(s) that reproduce a documented run
  README.md / MODEL.md  what it does, how it decides, which run the preset reproduces
```

An EA with no chart output has no `ChartVisuals.mqh`: a module that draws nothing is dead code.
`4. Index Book/8. NoiseBandMomentum` is the reference for that shape (shell + engine + runtime).

`ADXPane.mq5` (VWAPPullback, OBR) is an **accepted exception**: a customised indicator compiled as
its own expert. It is not merged into the EA because reproducing its drawing exactly is not worth
the risk, and a visual regression is not worth any. It stays a separate `.mq5` in the same folder.

Rules that the validation suites enforce and a reviewer checks:

* The shell includes `"StrategyEngine.mqh"`; the engine includes the runtime and the visuals. When
the shell's inputs use types declared in the engine (enums), the shell includes the engine **before**
the inputs and the runtime/visuals **after** them - that ordering is legal and is what X9 and
GotobiFix do. Never include the same file from two places expecting two passes.
* The shell contains **no strategy arithmetic and no order calls**. It wires events to the engine.
* `OnInit` returns `INIT_SUCCEEDED` only after the runtime validated the symbol, the account unit
  and the clock; otherwise `INIT_FAILED` with one actionable `PrintFormat`.
* Every `OrderSend`/`CTrade` return value is checked; a rejected send is a state transition, not a
  silent no-op (see the one residual warning in `5. Gotobi/GotobiFix/ExecutionRuntime.mqh:913`).
* Inputs: grouped with `input group` in the order *identity → instrument → clock → money → risk →
  strategy → execution → visuals → logging*. New inputs are appended or inserted inside their
  group; never renumbered between releases. Every input has a trailing `//` comment stating unit
  and the meaning of `0`/`false`/`auto`.
* Money-valued inputs are declared in a named unit (`InpMoneyUnit`, `InpMoneyRate`) and never
  silently assumed to be USD (section 4).
* Magic numbers: one contiguous block per EA, ≤ 20 slots, declared once in the shell, recorded in
  the registry table in section 9, never reused by another EA on the same account.
* State that must survive a restart is written through the runtime's single persistence function,
  is versioned, and is validated on read (reject and log rather than "repair" by guesswork).

## 3. Clock

Time is the single largest source of non-determinism, so it is standardised, not per-EA.

* Normative source: `CLOCK_STANDARD.md` v1.2. The `CLK-CORE` and `CLK-ADAPTER` blocks are copied
  **verbatim**; they are never edited inside an EA.
* Every EA exposes the same five inputs, in this order and with these names:

  ```
  ClockMode            (AUTO | MANUAL | TESTER_ANCHOR | EVIDENCE)
  ManualDstRule        (NONE | US | EU)
  ManualBaseMinutes    (multiple of 15, −720…840)
  TesterClockAnchor    (server wall time of a known New York time, for the Strategy Tester)
  ClockEvidenceSymbol  (symbol whose weekly open/close stamps prove the rule and base)
  ```

* **Zero configuration (v1.3).** No EA exposes a clock input - not in the tester, not on a chart:
  no `ClockMode`, `ManualDstRule`, `ManualBaseMinutes`, `TesterClockAnchor`, `ClockEvidenceSymbol`.
  The adapter resolves by itself: `COMPILED` (a `#define CLK_FORCE_RULE` in the EA's source, a dated
  code decision) → `PROFILE` (`clock_profiles.csv`, data) → `LEARNED` (a profile a live run wrote) →
  `LIVE` (weekly history + server/GMT, PC clock only as a sanity bound) → `ANCHORED`/`SEGMENTED`
  (tester, weekly close 17:00 NY, labelled). Unresolvable refuses to trade rather than guess.
  `tools/clk_verify.py` fails an EA that re-introduces a clock input.
* Per-EA clock engines (fixed NY offsets, "Mar 8 … Nov 6" heuristics, broker whitelists, a manual
  `BrokerServerGMTOffset`) are deprecated. The measured cost of the "Mar 8…Nov 6" approximation is
  4 253 wrong hours across 2007–2035, worst year 2010 with 157 hours; a single-base model mis-times
  17 544 of 35 064 hours on a broker that moved from +120 to +180. That is why migration is not
  optional.
* Migration procedure: `clock-splice` → `clock-verify` (byte-identical blocks + no clock input exposed) →
  headless compile → tester run of the clock conformance suite. All four must be clean before an
  EA is called migrated.
* The conformance suite (`tests/mql5/ClkConformance.mq5`, driven by `run_conformance.py`) is the
  executable proof: 60 IANA transitions 2006–2036, 173 280 server round-trips, dated-schedule
  segments proven from weekly stamps. Last run: `FAILURES: 0`.

## 3b. News calendar: one feed accessor, Forex Factory accuracy

The calendar source is **Forex Factory** (`ff_calendar_thisweek.json`), not the terminal's own
calendar: the built-in one mixes folder levels badly enough that a red-folder event is sometimes
yellow and vice versa. Accuracy wins; the network objection is answered by how the data is acquired,
not by switching source.

`EA_Standards/NEWS_FEED.mqh` is copied **verbatim** into each EA that reads a calendar (X9, RBE,
TokyoCoil, OpenDrive) between its BEGIN/END markers, and `tools/news_verify.py` proves the blocks are
byte-identical and that no `WebRequest(` is called outside them. The block:

* fetches the same URL, so every EA keeps its own parser, week handling and policy untouched;
* keeps one shared snapshot in `Common\Files\NewsFeed_ff_weekly.json`, so four EAs make one request
  instead of four and everyone sees the same calendar;
* serves that snapshot when the network is down or the host is rate limiting (HTTP 429): a real
  calendar that is hours old beats no calendar, and the EA's policy still decides what to do;
* refuses to call `WebRequest` in the Strategy Tester and only reads the snapshot there when the EA
  opts in (`InpNewsCacheInTester`, default `false`), so backtest behaviour does not change by itself;
* never halts, never blocks longer than the 5 s request timeout, and backs off 5 min after a failure.

Live still needs `https://nfs.faireconomy.media` in *Tools → Options → Expert Advisors → Allow
WebRequest*. TuesdayTurnaround is the exception: it uses the native `CalendarValueHistory` API and no
network at all, which is why it keeps its own implementation.

## 4. Money, account currency and cent accounts

The rule, for every EA, in every currency, at every denomination:

1. **Reported money is already account cash.** `AccountInfoDouble`, `OrderCalcProfit`,
   `OrderCalcMargin` and `SYMBOL_TRADE_TICK_VALUE` are all in the account currency. A budget built
   as `equity × percent` is therefore correct on USD, EUR, JPY **and on any cent account** with no
   factor applied.
2. **A factor is only for a fixed unit.** When an input is declared in a fixed unit (cash risk,
   commission per lot), convert it with a rate *derived from the terminal*:
   `cashPerUnit = tickValue / (tickSize × contractSize)` for a symbol whose
   `SYMBOL_CURRENCY_PROFIT` equals the declared unit (prefer the traded symbol, else scan Market
   Watch — never silently select a symbol). This returns `1.0` on a normal account of that unit,
   `100.0` on its cent variant, and that currency's value of one USD on a EUR/GBP/JPY account.
   There is no currency table, no `USC` branch and no contract-size anchor.
3. **If the factor cannot be derived, refuse the money-sized entry** and log it once
   (`RISK_UNIT_UNKNOWN` / `ACCOUNT_UNIT_UNKNOWN`). Never default to `1.0`, never default to `100`.
4. **Volume is floored to the broker step.** A budget below `SYMBOL_VOLUME_MIN` takes the broker
   minimum by default (`InpAllowMinLotOverride=true`) and logs the real risk (`MIN_LOT_OVERRIDE`);
   set it to `false` to skip the entry instead (`RISK_BELOW_MIN_LOT`). Either way the choice is
   explicit and printed - never a silent round-up that multiplies risk by the cent factor.
5. **Prices are snapped to `SYMBOL_TRADE_TICK_SIZE`** (never `SYMBOL_POINT`), toward the entry, so
   snapping cannot widen a stop or push a target further away.
6. **Money-sized inputs are already account cash.** An input documented as "account currency"
   (`RiskMoney`, `CommissionPerLot`) needs no conversion on any denomination: a cent account's
   balance *is* in cents. The thirteen Index Book/RBE/TokyoCoil EAs are correct for that reason;
   only X9 and FVG_Duo carried a fixed factor and both now derive it.
6. Reference implementation: `4. Index Book/9. FVG_Duo` (`FdgCashPerUnit`, `RiskVolume`,
   `CalculateLotSize`, `InpMoneyUnit`/`InpMoneyRate`/`InpAllowMinLotOverride`) and `1. X9`
   (`X9CashPerUSD`, `InpAllowMinLotOverride`). A Python twin with the same contract lives in
   `Python/engine/money.py` and is unit-tested (`cash_per_unit_from_market`, `risk_volume`,
   `snap_to_tick`).

Status: every in-scope EA is denomination-safe. X9 and FVG_Duo derive the scale; the other thirteen
size from account-currency inputs or a percentage of equity and need no factor at all.

## 5. Order, exit and recovery contract

Applies to every new EA and to every execution change. Read it before touching an order, bracket,
exit, OCO, stop-loss, take-profit, adoption, restart-recovery or finalisation path.

* Shared-account entry checks live in the executor. Independent same-direction hedged exposure is
  permitted; exclude metals/FX from wider equity-index direction checks. A pending opposing entry
  is exposure too. Attached hedging SL/TP are not separate pending entries. Never exempt another
  strategy's net position from ownership checks.
* Persist broker permission/liquidation restrictions **before** invoking failure handling. A
  restart is not evidence that a restriction was lifted. Keep accepted protection; do not turn a
  restriction rejection into an account-wide cancel/flatten or a blind corrective order.
* Persist the *desired* close separately from its current transport attempt. A terminal partial
  close allows a bounded remainder request only after exact order/position/history quantities
  agree. Unacknowledged requests wait. A missing position requires full opening-order filled volume
  matched by exit evidence, including external/manual exits.
* Recovery timers run even when charts and panels are hidden. Legacy positions without a
  trustworthy original risk/trailing identity stay unadopted with protection intact; never
  synthesise those fields from the current ATR or a moved stop.
* Own positions through exact account/server/symbol/magic **plus** saved `POSITION_IDENTIFIER` and
  verified opening deals. A netting position or a chart identity alone never proves ownership.
  Mixed opening ownership or a reversal requires reconciliation; never close another EA's position.
* Save original stop/risk, current stop/trailing stage, consumed signal and session counters, and
  the pending-close identity **before** acting. Durable updates are crash-safe and ownership scopes
  are exclusive. Retain broker protection across restart and chart replacement.
* Re-query transient terminal/broker/history gaps from the existing timer/tick driver. Missing
  history or metadata is *pending evidence*; corrupt or contradictory identity is a *hard fault*.
  Never place a duplicate close or replacement while an earlier request is unsettled.
* `HistorySelectByPosition` only selects what is currently available: position disappearance is
  not proof that exit deals hydrated. Require exact position/symbol opening ownership and complete
  matched entry/exit volume before clearing saved ownership or realising PnL. Support
  `DEAL_ENTRY_OUT_BY`; reject unresolved `DEAL_ENTRY_INOUT` mixing.
* Broker/manual exit deals may carry magic zero: verify ownership from the opening deals and the
  exact position ID. Do not reject an otherwise complete manual close merely because its exit
  magic differs. Never invent a zero-price exit or zero PnL to clear a wait.
* Preserve an existing tighter broker stop. Reconstruct the original geometry from persisted state
  or a verified opening order; a moved stop is not the original risk. Until the evidence is sound,
  block new risk and quantity-dependent mutations while retaining protection.
* Unresolved evidence is never guessed from account net. An exceptional administrative settlement
  must bind explicit confirmation to one exact trade, require verified broker closure with no
  remaining owned orders, preserve an immutable backup/receipt and retire its identity. Never
  expose an unrestricted reset switch.
* **Root-only source layout.** RBE, TokyoCoil and TuesdayTurnaround each keep exactly one `.mq5` and
  three `.mqh` in the strategy root; all transitive project and `<Trade/Trade.mqh>` code is embedded
  in those four files. No subfolder, external include tree or visual `.ex5` is required. Recovery
  instructions live in the root `README.md`, never in a per-EA `RECOVERY.md`.
* **MT5 file APIs and terminal globals are platform storage, not project storage.** Use flat,
  strategy-prefixed paths under `Common\Files` where file output is needed; the native API cannot
  write into `Experts`. Output files are evidence, never the source of truth for ownership.
* **Fixtures are not broker acceptance.** An offline contract suite (history fixtures, extracted
  functions, synthetic deals) proves the *code path*, not disconnects, reboots, chart replacement
  or broker-side rejection. Say so in every report; VPS/forward acceptance is a separate gate.

## 6. Hygiene

`EA_HYGIENE.md` is the checklist; `python tools/ea_lint.py <folder>` is the mechanical part. The
review gate also requires:

* no `WebRequest` outside the NEWS-FEED block (section 3b), no `#import`, no DLL flag, no `Sleep` in the tick path, no `Comment()` HUD;
* no `FILE_COMMON` path needed for correctness (accepted exceptions listed per EA);
* no hard-coded broker server offsets, no broker whitelists, no `"Mar 8 … Nov 6"` DST heuristics;
* one magic block per EA (see section 9), `OrderSend`/`CTrade` returns checked;
* lines ≤ 160 columns where the file already complies; new code always ≤ 120;
* UTF-8 without BOM for `.mqh`/`.mq5`, ASCII for `.set`/`.ini`;
* no dead code, no commented-out order blocks, no duplicated helper that already exists in the
  runtime.

## 7. Python lives outside this tree

Research, validation, parity and report tooling is Python and belongs in
`Documents\Strategies\Building & Testing\Python`:

```
Python/
  engine/     clock.py  money.py  costs.py  bars.py  ledger.py  parity.py  mt5.py  nt8.py
  tests/      test_engine.py          # 13 tests, run: python tests/test_engine.py
  legacy/     the per-EA suites, moved out of Experts and kept runnable
```

`engine` is the single source of truth for the clock rules, the money contract, the trade ledger
and the MT5/NT8 comparison. A strategy is authored and validated there and only then moved into
its own folder under `Experts`. A suite inside `Experts` is a defect; the only exception is the
MQL5 conformance harness in `EA_Standards\tests`, which is MQL5 and lives with the standard.

## 8. Verification protocol

**Compile (headless).** One file per invocation; the exit code means nothing.

```bat
"C:\Program Files\MetaTrader 5\MetaEditor64.exe" /compile:"<file>.mq5" /inc:"<...>\MQL5" /log:"<file>.log"
```

Read the log as UTF-16LE (`iconv -f UTF-16LE -t UTF-8`). Success is the line
`Result: 0 errors, 0 warnings`. Zero errors with warnings is a pass only if each warning is
recorded; the current known one is `GotobiFix/ExecutionRuntime.mqh:913` (unchecked `OrderSend`).

**Tester (headless).** Write `MQL5\Profiles\Tester\<Name>.ini` (ASCII, `ShutdownTerminal=1`,
`Model=1` for direction/trade-count checks, `Model=4` for tick precision), run
`terminal64.exe /config:<ini>`, then read the evidence: the EA's own CSV export under
`Common\Files\<Family>\logs`, and the tester agent log under
`...\MetaQuotes\Tester\<Instance>\Agent-127.0.0.1-3000\logs\YYYYMMDD.log`. The HTML report is
presentation, not proof.

**Conformance.** `python tests/mql5/run_conformance.py` must print `FAILURES: 0`.
**Suites.** `python Python/tests/test_engine.py` must print `PASS (0 failure(s))`.
**Never** claim a compile, test, backtest or live check that was not run in this session.

## 9. Magic registry

One contiguous block per EA. A collision means two EAs adopt each other's positions: it is a P0.

| EA | Base | Range | Status |
|---|---:|---|---|
| `1. X9` (Gold_X9_v6_3) | 647900 | 647901–647909 (base+N = strategy N) | in use; order comment `X9S<N>` |
| `1. X9/Part 3` (Gold_X9_Part3) | 647873 | 647873–647893 | a build, not a complete EA; left untouched. X9 moved to 647900, so the two no longer collide |
| `5. Gotobi/GotobiFix` | 26111701 | 26111701 | in use (single magic, no slot range) |
| others | — | — | not yet audited; record on first migration |

## 10. Journal (facts confirmed in-session only)

* **2026-11-21 — clock 1.2.** `CLK-CORE`/`CLK-ADAPTER` 1.2 (segmented dated schedule, open-hour
  anchor, stale-profile refusal) spliced into `5. Gotobi/GotobiFix`; `clk_verify.py` PASS, blocks
  byte-identical; compiles 0 errors, 1 warning at `ExecutionRuntime.mqh:913`. Conformance
  `FAILURES: 0` (60 transitions, 173 280 round-trips, 2 segments / 104 weeks, 25 560 dated hours).
* **2026-11-21 (fourth pass) — three EAs on the standard rule, all parity-proven.** VaultBreak
  (236/236 trades identical), OpeningShockContinuation (67/67) and FVG_Duo (189/189, zero differing
  cells) now take the US DST rule from `CLK-CORE 1.2` instead of hand-writing it. FVG_Duo's old body
  was the fixed-date approximation ("summer from March 8 to November 6"), now replaced by the real
  rule; its tester result is unchanged because the tester path reads real weekly stamps, so the
  correction only bites in the live historical conversion - which is where it was wrong.
* **2026-11-21 (third pass) — the clock gate is proven.** VaultBreak's hand-written US DST rule
  (`VBExpectedBrokerUTC`) now delegates to `CLK-CORE 1.2` (`ClkNyUtcOffset`), the block spliced
  verbatim into its `StrategyEngine.mqh`; name and every call site unchanged. A full-year tester run
  on USTEC M1 before and after produced **236/236 identical trades** — every column except `run_id`,
  including entry/exit server and UTC stamps, prices, volume, SL/TP, modelled cost, net and exit
  reason. That diff is the gate: the same procedure applies to the remaining thirteen EAs. VaultBreak's
  own `VBCalendarSelfTest` (four DST assertions) runs inside the tester at `OnInit` and passed, since
  the run produced trades.
* **2026-11-21 (second pass) — defects closed.** `Shared/` deleted (its `ForexFactoryFeed.mqh` was
  included by no EA). `NoiseBandMomentum` split into shell + engine + runtime, compiles clean.
  `NEWS_FEED 1.0` written and spliced into X9, RBE, TokyoCoil, OpenDrive: no bare `WebRequest`
  remains, `news_verify.py` PASS, all four compile 0 errors / 0 warnings. X9 magic base moved to
  647900 (strategy N = base+N, last digit = strategy), comments shortened to `X9S<N>`, legacy-range
  tickets reported at init and never adopted. `InpAllowMinLotOverride` defaults to true.
  Correction to the earlier table: thirteen EAs were never denomination-dependent (they size in
  account cash or percent of equity); only X9 and FVG_Duo had a factor, and both derive it now.
* **2026-11-21 — money.** X9 and FVG_Duo moved from a fixed cent/USD factor to the tick-value
  derivation; `InpAllowMinLotOverride` added (default `false`, skip and log). Both compile
  0 errors / 0 warnings. Behaviour change: a sub-minimum budget is now skipped instead of silently
  rounded up.
* **2026-11-21 — Python.** 52 files moved out of `Experts` into `Python/legacy` with a path
  resolver (`_paths.ea_root`, stale folder numbers tolerated). 23 of 35 suites pass there; the
  other 12 were re-run from pristine copies at their old location and fail identically, i.e. they
  were already broken before the move — see `EA_STRUCTURE.md` §3.
* **Earlier (carried over, re-verified only where stated).** TokyoCoil/TuesdayTurnaround recovery
  contracts; RBE explicit-ticket stop restoration; headless compile of all 16 real EAs at 0 errors.
  These are not re-asserted here beyond what this session re-ran.

## 11. Chart and report styling (unchanged)

Equity/drawdown figures use the institutional dark theme: `figsize=(14, 9)`, 3.2/1.2 subplot
ratio, figure `#0b0f19`, axes `#111827`, grid `#475569` at `alpha=0.2` dashed, NT8 line `#38bdf8`
2.2 pt, MT5 line `#a855f7` 2.2 pt, high-water mark `#4ade80` dashed `alpha=0.6`, drawdown fill
`#ef4444` (`alpha=0.15` main, `0.5` underwater), text `#f8fafc` / `#94a3b8` / `#cbd5e1`. Main panel
carries a starting-capital line, 1 January year markers and a monospace HUD (initial/final equity,
net PnL, max drawdown in cash and %, profit factor, win rate with W/L counts, annual PnL).
Reference implementation: `Python/legacy/4. Index Book/5. NQPrecisionBot/validation/equity_curve.py`
if present, else the NT8 copy under `Documents\NinjaTrader 8\bin\Custom\Strategies`.

## 12. Revealing screenshot / report automation (unchanged)

`Start-Process -Wait` on `MetaEditor64.exe` and `terminal64.exe /config:<ini>` is the supported
headless pattern on this machine; both are verified to work when invoked one at a time. Batching
several compiles in one `.bat` silently produces no logs — compile sequentially with a short delay.

### Clock journal: one slot per machine

The clock prints **once per server per decision per day**, not once per EA. `ClkJournal()` claims
`Common\Files\clock_journal_<server-hash>.txt` keyed by `rule+base+source` and the UTC day; the first EA
to resolve announces, the rest stay silent. Never add a per-EA clock banner — seven EAs must not produce
seven clock lines. Failures (give-up, conflicts, skew, gap, stale profile) bypass the slot and always print:
silence is for announced decisions only, never for a problem.


## Automation never touches the terminal that holds the user's account

The terminal data folder under `AppData\Roaming\MetaQuotes\Terminal\<hash>\` holds the user's account,
server catalogue, chart profiles and live session. A second `terminal64.exe` started against that folder
while one is running races it on `configccounts.dat` and `config\servers.dat`; on 2026-11-22 that
corrupted the saved account and forced a manual re-login.

- Run every automated test in a **separate portable copy**: `terminal64.exe /portable` with its own data
  folder, its own `config`, and its own tester agents. A portable instance cannot touch the live account.
- Never launch a non-portable `terminal64.exe` to "see if it works", never `taskkill /F` the live terminal,
  and never edit `configccounts.dat`, `config\servers.dat`, `config	erminal.ini` or
  `config\common.ini`.
- Inis for unattended tester runs stay inside the portable copy. `Expert=` paths take **single** backslashes:
  a doubled path does not resolve and MetaTrader silently reuses the previously configured expert, which is
  how an X9 run masqueraded as a VaultBreak run. Always confirm the `test Experts\<path> ... thread
  finished` line before trusting a capture.
- A portable instance also removes the "ini launch aborts while the terminal is open" failure, because the
  live instance no longer owns the data folder under test.
