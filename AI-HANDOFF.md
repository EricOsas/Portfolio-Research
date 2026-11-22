# AI handoff — Portfolio-Research

Newest entry first. Only what was verified in this session is recorded here.

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
