# AI handoff — Portfolio-Research

Newest entry first. Only what was verified in this session is recorded here.

## 2026-11-23 (latest) — Gold X9 ingested as a five-preset family

**Delivered.** Five X9 exports (2020.01.01-2026.11.01, XAUUSD M1 OHLC, USD 100k deposit) plus a
preset registry: Extremely low (freq 0, strategies 1-3, 558 trades / 1,117 deals), Low (1, 1-5,
1,871 / 3,743), Moderate (2, 1-7, 4,147 / 8,295), High (3, 1-8, 5,525 / 11,051), Very high (4, 1-9,
13,403 / 26,807). Exports copied to `Trades/MT5 Trades/`; the registry workbook sits in
`Trades/MT5 Presets/` so the preflight does not flag it. The legacy single `MT5 X9 Trades.xlsx`
(left the repo; it was the Very-high run) is still in `Documents/Portfolio/Trades/MT5`.

**Registry.** "Gold X9" replaced by five entries; MT5 is now 19 exports and all 19 parse.

**Mutual exclusion.** `strategy_family()` in `build_equity_reports.py` (selection screen) and
`build_live_and_prop_reports.py` (book enumeration) drops any book with two X9 presets.
`GOLD_X9` in `analyze_the5ers_sizing.py` is the single place naming the standard preset.

**Preset fact.** One EA at five `TradeFrequency` settings: R/day rises 0.31 -> 1.34 from Extremely
low to Very high while the worst validation day falls from -9.6R to -30.1R (High). Measured 1R at
0.01 lot: Extremely low $10.15, Low $9.90, Moderate $11.65, High $11.02, Very high $13.09.

**Standard preset = `Low`**, chosen by measurement: The5ers phase book 89.6% reach / 5.9% breach /
80.9% payout, Moneta phase book 99.7% both phases / 0.0% breach / 98.8% payout. High was rejected
despite the best R/day (33% Moneta evaluation breach).

**Rebuilt with Low.** The5ers: phase 4-sleeve USD 50 target = **USD 46.83** (gold 0.01, GotobiFix
0.12/0.12, Open Drive 0.32), funded no-gold USD 100 = **USD 97.68**; 89.6% reach, 5.9% breach,
80.9% payout, 90.4% conditional, 0.5% funded breach, 174 median days, USD 183 expected. Moneta
$10k: phase X9(Low)+OBR USD 50 = **USD 44.26** (gold 0.02 = USD 19.80, OBR 0.40), funded no-gold
USD 100 = **USD 97.68**; 99.7% both phases, 0.0% breach, 98.8% payout, 99.1% conditional, 0.4%
funded breach, 116 median days, USD 249 expected.

**Set files.** Gold X9 now writes `TradeFrequency` (0-4), `Lotsizing_Method=0`, `FixedLots`,
`SepLotSize=false`; filenames carry the preset (`01. Gold X9 Low.set`). Repo copy and
`Documents/Portfolio/Set-Files` both regenerated.

**EA sources re-synced.** `ExecutionRuntime.mqh` updated for VaultBreak, OvernightBias,
NQPrecision, OpeningShock, Sigma and FlashTriggerORB after the user's latest edits.

**Verified.** CI run `45189645268` on `e3ed2fc` green, bot commit `b1d6bad`. Checked the published
`book_rankings.csv`: 808 The5ers rows, **zero** books holding two X9 presets.

**Follow-up fixed and verified.** The training-score ranking shortlisted `Very high` (338 of 808
rows) because it scores raw return, not breach risk. `run_platform` now screens **only the standard
preset** for MT5 prop candidates, so ranking and execution cannot disagree; the other four presets
stay in the per-sleeve and normalized-live reports. CI run `45367919124` (commit `fe08768`, bot
`985a783`) was green in 21m40s: both `book_rankings.csv` are 1,940 rows and name only
`Gold X9 (Low)` (470 each, no book holds two presets), and the generated Moneta README says $10,000.

**Plan-switch fix.** The hand-written The5ers figures were not reproducible from the generated
reports, and the "real switch" the report describes was never simulated on one path set.
`analyze_the5ers_sizing.py` now draws a single joint matrix, sizes the 4-sleeve phase book to USD 50
and the no-gold funded book to USD 100, and writes `plan_switch.csv` plus a report section:
**89.6%** reach, **5.9%** evaluation breach, **80.9%** first payout, **90.4%** conditional,
**0.5%** funded breach, **174** days, **$183** expected. `reports/strategy_suitability.md`,
`Prop-Firms/methodology.md` and `analysis/README.md` quote those numbers.

## 2026-11-23 — Moneta $10k 2-Step added; plug-and-play EA set files built

**Ask.** Include the Moneta account the user is about to buy (**USD 10,000**, corrected from
$25k mid-task), and create a folder under `Documents/Portfolio` with pre-configured EA set
files per firm per stage.

**Moneta rules recorded** (support clarification 2026-11-21; the firm says website/dashboard/
FAQ/Terms are authoritative): Phase 1 +5% (USD 500), Phase 2 +10% (USD 1,000), 4% daily loss
(USD 400) and 8% static max loss (USD 800) — 5%/10% with the wider option — three profitable
days of at least 0.5% (USD 50) per phase and per payout cycle, **no consistency rule**, 88%
split, 14-calendar-day payout cycle, own EAs allowed, incidental opposing positions from
independent EAs on one account allowed, cross-account hedging prohibited, news restricted 5
minutes either side of high-impact releases **in evaluation too**, IP/VPS switching not
blanket-approved.

**Engine.** `simulate_moneta()` in `build_live_and_prop_reports.py` (2 phases + funded,
`MONETA_SIZE = 10000`, `MONETA_RISKS = [12.5, 25, 50, 75, 100]`, base `$50`,
`funded_paths`/`funded_risk` switch the book at funding). Moneta Monte Carlo rows, a recovery
block (8% floor = USD 800, 4% daily = USD 400), `account_rules.json`, generated README and the
Prop-Firms index link are wired in. Two bugs found and fixed: Phase 1 passing jumped straight
to the funded state, and `reached_funded` read the Phase-1 marker.

**Sizing (`analysis/analyze_moneta_sizing.py`, new CI step).** Whole-lot sizing plus an
end-to-end plan with the funded switch → `Prop-Firms/Moneta-2Step-10K/reports/`
`stage_sizing.{md,csv}`, `plan_switch.csv`, `ea_allocation.json`.

Verified locally on the $10k account: phase book **Gold X9 + Overnight Bias ORB** at a USD 50
target = **USD 37.41** (0.37%; gold 0.01 lot = USD 12.96, OBR 0.40 lot = USD 24.46); funded
book **Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB** at USD 100 =
**USD 97.68** (0.98%), no gold. Plan: **97.4%** reach funding, **2.5%** evaluation breach,
**97.3%** first payout (**99.8%** conditional, **0.7%** funded breach), median **88** trading
days, expected first payout **USD 250**. Phase 2 is the binding constraint (10% target against
an 8% static budget, Phase 1 profit reset away).

**Set files (`analysis/build_set_files.py`, new CI step).** Writes `Set-Files/<firm>/<stage>/`
with one MT5 `.set` per sleeve, a per-stage `manifest.csv` (EA, symbol, lots, USD risk, magic)
and per-firm READMEs, plus a Tradeify NT8 settings README. Whole-lot sizing with explicit magic
numbers (The5ers base 760000, Moneta 770000). Generated locally into
`C:/Users/Administrator/Documents/Portfolio/Set-Files` and committed under `Set-Files/`.
Input names read from the terminal-tree sources, including `Lotsizing_Method=0`
(`Manual_Lotsize`) for Gold X9 and `InpSizingMode=0` for FVG Duo.

**Moneta presets:** Phase 1 `770101` Gold X9 0.01 / `770102` Overnight Bias 0.40; Phase 2 the
same sizes with `770201/770202`; Funded `770301-04` Flash 0.38, GotobiFix EURJPY 0.24, Tokyo
Coil 0.14, Overnight Bias 0.40.

**Docs.** `Prop-Firms/methodology.md`, `reports/strategy_suitability.md`, `analysis/README.md`,
root `README.md`, CI workflow (`analyze_moneta_sizing.py`, `build_set_files.py Set-Files`).

**Status — verified in this session.** CI run `45168585423` on commit `0f3e07f` completed green;
the bot commit is `20d2edd`. The generated Moneta README and `stage_sizing.md` in the repo match
the local run (phase book USD 37.41, funded book USD 97.68, 97.3% first payout, 0.7% funded
breach). The live copy at `C:/Users/Administrator/Documents/Portfolio/Set-Files` was regenerated
after the last code change and matches `Set-Files/` in the repo. Two further fixes landed after
the first commit: stage folders are wiped before writing (the $25k-to-$10k resize had left stale
GotobiFix files beside the new phase book), and the `.set` header now prints the 0.01-lot 1R
rather than the per-1.0-lot unit.

**Next action.** Nothing blocking on Moneta or the set files. The only open item is the user's
Gold X9 preset exports (`Phase 1/2/3` variants by `TradeFrequency`/`TieredLot`/`RiskScaling`),
still not delivered into `Trades/MT5 Trades/`; when they land, register the preset family with
mutual exclusion and rebuild the Moneta and The5ers phase books against the chosen preset.

## 2026-11-23 — NT8 contract sizing for Tradeify

**Why.** The The5ers sizing fix has an NT8 counterpart: a "0.5% per sleeve" rule is meaningless on a micro contract that already risks USD 127-182.

**New artifact.** `analysis/analyze_tradeify_sizing.py` (also a CI step) enumerates 1-10 micros per sleeve for the challenge book, funded book and lower-risk pair, enforces the four-mini cap, and writes `Prop-Firms/Tradeify-50K-Growth-Futures/reports/stage_sizing.{md,csv}`.

**Verified numbers (5,000 paths, validation bootstrap)**
- 1R per micro: FVG Duo 168.44, Sigma ORB 182.13, Overnight Bias 139.12, Gold ORB (RBE) 134.03, Opening-Shock 129.52, Flash ORB 127.04, NQ Precision 75.36, VWAP 67.60, Vault 98.90.
- Four-sleeve challenge book at 1 micro/sleeve: USD 511.97 per trade (1.02% of 50k), 3.91R to the 2,000 trail; pass 67.4%, payout 45.6%, funded breach 40.0%.
- Funded book at 1 micro/sleeve: USD 475.65, 4.20R; payout 57.4%, funded breach 34.5%.
- Lower-risk pair (Flash + Overnight) at 1 micro/sleeve: USD 237.63, 8.42R, zero clip-binding days; pass 86.4%, payout 64.1%, funded breach 19.0%. This is the only allocation the model evaluates exactly.
- 2 micros/sleeve doubles risk to ~2% and ~2R to the trail; the simulator's USD 1,250 daily clip then binds on 3-21% of days and hides losses, so rows above one micro are scale illustrations, not odds. Flagged in the report and docs rather than silently published.

**Settings recorded (NinjaScript sources in `Documents/NinjaTrader 8/bin/Custom/Strategies/`)**: `FixedContracts=1` on MNQ/MGC per sleeve for both stages; keep `UseFixedContracts=true` on Flash/FVG/OpenDrive so `RiskPercent` cannot scale the book. Only the book changes at funding (FVG Duo out, Opening-Shock in). The 4-mini cap is not binding; the USD 2,000 trail is.

**Docs:** `reports/strategy_suitability.md` (new minimum-contract subsection with the allocation table), `Prop-Firms/methodology.md` (contract-floor section), generated Tradeify README now links the report and explains the micro constraint.

**CI verified (run 45134849886, commit b1930a0).** Success in ~20 min; the bot commit `24b9747` regenerated the Tradeify README with working `stage_sizing.md`/`stage_sizing.csv` links and re-ran both sizing steps. Committed table matches the local run: challenge book 1 micro/sleeve $512, 3.9R, 67.4% pass, 45.6% payout, 40.0% funded breach; Flash+Overnight pair $238, 8.4R, 86.4% pass, 64.1% payout, 19.0% funded breach, 0.0% clip-binding days.

**Next action:** none. Both sizing reports regenerate on the next `analysis/` or `Trades/` change.

## 2026-11-22 (latest) — minimum-lot sizing: the published The5ers odds were optimistic

**What triggered it.** The published The5ers ladder sizes the book in continuous dollars (USD 25 total = USD 6.25/sleeve). On XAUUSD the broker minimum is 0.01 lot, whose mean losing trade in the Gold X9 export is USD 20.02, so the equal split is not placeable. Every continuous-dollar number for The5ers is therefore an idealisation, and the funded-breach figures (0.14% / 0.05%) are not reachable with these EAs.

**New artifact.** `analysis/analyze_the5ers_sizing.py` (wired into CI). It models `risk_i = max(pct x balance, 0.01-lot 1R_i)` per sleeve, the real mid-account switch from the evaluation book to the funded book, and writes `Prop-Firms/The5ers-20K-Bootcamp/reports/stage_sizing.{md,csv}`.

**Verified numbers (5,000 paths, validation block bootstrap)**
- 0.01-lot 1R: Gold X9 USD 20.02; GotobiFix EURJPY 1.05; GotobiFix USDJPY 1.14; Open Drive 0.04; Flash ORB 0.73; Tokyo Coil 0.13; Overnight Bias 0.08.
- Physical minimum, no scaling (A): stage risk 0.44% / 0.22% / 0.15% of $5k / $10k / $15k, funded 0.11%; reach funded 63.4%, evaluation breach 36.6%, first payout 60.8%, funded breach 44.6% (because the funded book still held Gold X9).
- 0.125%/sleeve scaling both stages (C): 65.2% reach funded, 57.7% funded breach. 0.25%/sleeve (D): 57.3% / 88.3%. 0.5%/sleeve (E): 44.5% / 96.3%. So scaling with the balance is worse, not better.
- Minimum-lot evaluation + funded book without Gold X9 at 0.125%/sleeve (F): 65.0% reach funded, 35.0% evaluation breach, 64.9% first payout, **1.0% funded breach**, 99.8% conditional payout. At 0.25%/sleeve (G): 26.1% funded breach.
- 1%/sleeve is impossible: 4% of the step per trade against a 5% static limit is a 1.25R buffer.

**EA settings verified in the terminal tree** (`.../MQL5/Experts/`): Gold X9 uses tiered sizing whose budget at $5k is ~USD 1.50 per strategy, below the 0.01-lot floor, so it min-lots regardless; GotobiFix is fixed-lot only; Flash ORB / Overnight Bias / Vault / Sigma are `RiskMoney` (fixed cash); only Open Drive (`RiskPercent`) and Tokyo Coil (`RiskPct`) support percentage risk. Recommended: challenge = X9 manual 0.01, GotobiFix 0.05 per pair, Open Drive RiskMoney 8 (held unchanged through all three steps); funded = Flash 25, GotobiFix EURJPY 0.24, Tokyo Coil 25, Overnight Bias 25, and no Gold X9.

**Docs updated:** `reports/strategy_suitability.md` (executive bullet, configuration bullet, new minimum-lot subsection), `Prop-Firms/methodology.md` (lot-floor subsection), generated The5ers README now links the sizing report, workflow runs the sizing script.

**CI outcome (run 45130586210, commit 78d95d8).** The first attempt failed in 0s: the The5ers extra-links patch had written a raw newline into `build_live_and_prop_reports.py` (SyntaxError at import), which also meant the committed tree held a broken build script. Fixed in `78d95d8` by building the separator with `chr(10)`; `py_compile` passes for both scripts. The rerun succeeded in ~20 min and its commit `48aa30c` regenerated the The5ers README with working `stage_sizing.md`/`stage_sizing.csv` links and re-ran the sizing step. The committed numbers match the local run (A: 63.4% reach funded, 36.6% eval breach; F: 65.0% / 1.0% funded breach).

**Next action:** none outstanding. The sizing report regenerates automatically on the next `analysis/` or `Trades/` change.

## 2026-11-22 (later) — instrument correction and The5ers replaces FTMO

**Corrections to the entry below**
- **FVG Duo is an NQ strategy, not GC.** The export is `NinjaTrader FVGDuo Trades.csv`, instrument `NQ DEC26`, 1,407 trades. The "GC" line in the previous README was a documentation error; no FVG Duo GC backtest exists, so there is no GC-vs-NQ comparison to report. GC belongs only to NT8 Gold ORB (RBE). Fixed in `README.md`, `Source Codes/NT8/10. FVGDuo_NT/MODEL.md`, and regenerated `NT8/README.md` instrument coverage.
- **FTMO was the wrong firm.** The medium-horizon prop model is now **The5ers $20,000 Bootcamp**; `Prop-Firms/FTMO-10K-2Step-CFD/` was removed and replaced by `Prop-Firms/The5ers-20K-Bootcamp/`.

**The5ers model implemented** (`simulate_the5ers` in `analysis/build_live_and_prop_reports.py`)
- Steps on $5,000 / $10,000 / $15,000, each 6% target and 5% static max loss; no evaluation daily limit; no time limit.
- Funded $20,000: 4% static max loss ($19,200 floor), 3% daily pause modeled as a closed-PnL clip, 50% split, payouts every 14 calendar days approximated as 10 trading days, balance resets to $20,000 after withdrawal.
- No consistency rule. 5% funded scale-up ladder, fees and inactivity are not modeled.
- Risk ladder USD 10/25/50/100, base case USD 25 (was USD 50 for FTMO). Funded-stage book is chosen as the best training-funded-score book among the ten best training challenge books so it can realistically reach funding.

**Evidence from the completed rebuild**
- Challenge book Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive at USD 25: Step-1 93.38%, Step-2 conditional 99.10%, Step-3 conditional 93.60%, reach funded 86.62%, evaluation breach 7.46%, conditional funded breach 0.14%, first payout 83.96%, median 164 trading days, expected first payout USD 69.08.
- Funded-stage book Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil: reach funded 87.16%, conditional first payout 96.3%, conditional funded breach 0.05%.
- USD 50 rung: 78.0% reach funded, 21.9% evaluation breach, 13.8% conditional funded breach. USD 100: 57.9% / 42.1% / 69.0%.
- Recovery from a USD 100 cushion: Gold ORB (RBE) + Gold X9 at USD 5 gives 89.0% recovery / 7.3% breach; from USD 250 it clears the 50%/5% screen (98.3% / 0.38%).
- Tradeify account size confirmed: **USD 50,000** Growth (evaluation target USD 3,000; EOD trailing DD USD 2,000; funded floor USD 50,100; payout balance threshold USD 53,000). Tradeify results were unchanged by this work.

**Docs updated:** `README.md`, `analysis/README.md`, `Prop-Firms/methodology.md`, `Normalized-Live/methodology.md`, `reports/strategy_suitability.md` (all FTMO sections replaced with The5ers numbers). `Prop-Firms/README.md` and both firm READMEs were regenerated.

**CI verified (run 45072819532, commit acda6e2)** — success in 17.9 min total: equity build 1.2 min, schema inspect 0.2 min, prop build 16.1 min, all steps green under the 180-min job / 150-min prop timeouts. The CI-generated commit ecffc9c reproduces the local The5ers numbers exactly (challenge 86.6% reach funded / 84.0% challenge-to-payout, funded candidate 96.3% conditional payout), so the 1,940-book prop universe fits comfortably in CI.

**Next action:** Nothing outstanding; next rebuild happens automatically on the next `Trades/` or `analysis/` change.

## 2026-11-22 — new systems registered, engine + docs rebuilt

**Changed**
- Registered all three new systems in `analysis/strategies.json` (already present, now complete): Gold X9, FVG Duo, GotobiFix EURJPY/GBPJPY/USDJPY. Registry is the single source of truth for both engines; 10 NT8 + 15 MT5 exports.
- `analysis/build_equity_reports.py`: added generated platform READMEs (`NT8/README.md`, `MT5/README.md`) so they cannot go stale; added an unregistered-export preflight (build fails if a file sits in `Trades/` without a registry entry); added a position-size-over-time warning derived from the data (flags Gold X9 and Tokyo Coil as balance-compounding exports).
- `analysis/build_live_and_prop_reports.py`: MT5 cash flows are now divided by traded volume before the R unit is calibrated (per-lot normalization). Without this, Gold X9's balance-compounding run (~0.46 → 51.47 lots) produced an $82M raw PnL and dominated every normalized/prop book. Also added candidate progress logging and fixed a regex escape warning.
- New `analysis/ADDING-A-STRATEGY.md`: six-step onboarding procedure, generated-vs-hand-maintained doc list, edge cases.
- New `Source Codes/MT5/12. FVGDuo/MODEL.md`, `Source Codes/MT5/13. GotobiFix/MODEL.md`, `Source Codes/NT8/10. FVGDuo_NT/MODEL.md`.
- Removed the unreferenced `design-workflow templates/` folder (superseded NQ-era scripts; recoverable from git history).
- `.github/workflows/build-equity-reports.yml`: timeout raised 20 → 180 min because the prop engine now screens 1,940 MT5 books (was 385).
- Updated by hand: `README.md`, `analysis/README.md`, `reports/strategy_suitability.md`, `Normalized-Live/methodology.md`, `Prop-Firms/methodology.md`.

**Evidence (run in this session)**
- `python analysis/build_equity_reports.py` → NT8 10/10, MT5 15/15 parsed. Shortlists: NT8 Overnight Bias ORB, Sigma ORB, Vault Break, Gold ORB (RBE); MT5 Gold X9, GotobiFix EURJPY, GotobiFix USDJPY, Gold ORB (RBE).
- `python analysis/inspect_mt5_headers.py` → 15 files.
- `python analysis/build_live_and_prop_reports.py` → completed; wrote `Normalized-Live/` and both `Prop-Firms/` folders plus `Prop-Firms/reports/build_summary.json` (generated 2026-11-22T18:27Z).
- New selected books: MT5 live Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Tokyo Coil (Sharpe 4.12, 68.78% P(10R DD)); FTMO challenge Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive (98.48% pass both, 1.4% combined breach); Tradeify challenge FVG Duo + Flash + Gold RBE + Sigma (46.1% challenge-to-payout at USD 512 effective risk).

**Caveats recorded in the docs, not hidden**
- Gold X9's raw export compounds from USD 100k to USD 80.1M. Raw platform totals are still reported at exported sizing, labelled as a compounding tester run; only the normalized/prop layers are per-lot.
- NT8 `10. FVGDuo_NT/` is missing the referenced `FvgDuoCore.cs`, so that source drop is not compilable as-is (stated in its MODEL.md).
- Prop-firm results are closed-PnL simulations: FTMO's 98% pass rate is an upper bound because floating-loss breaches are invisible.
- The docs' FTMO/Tradeify recovery and monthly tables were regenerated by hand from the fresh CSVs; the authoritative values remain the CSVs.

**Blocked / awaiting approval**
- Nothing blocking. Local full prop rebuild takes ~50 minutes; CI is now allowed 180 minutes.

**Next action**
- Commit and push this state, then confirm the GitHub Action completes within the new timeout (first scheduled rebuild will exercise 1,940 MT5 books).
