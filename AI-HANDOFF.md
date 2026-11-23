# AI handoff — Portfolio-Research

Newest entry first. Only what was verified in this session is recorded here.

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
