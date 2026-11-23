# Strategy and book suitability report

**Updated:** 2026-11-22  
**Scope:** 10 NT8 and 19 MT5 registered exports (Gold X9 is one EA at five mutually exclusive `TradeFrequency` presets); all one-to-four-sleeve books re-screened.  
**Purpose:** classify sleeves and portfolios for standard live accounts, prop-firm challenges, funded accounts, and near-drawdown recovery. This is a historical research screen, not a live-deployment approval.

## Plain assignments

These are the actual strategy combinations selected by the research. A plus sign means all listed strategies are run together.

**NT8 futures books**
- **Live account:** Opening-Shock Continuation + Overnight Bias ORB + Sigma ORB + Vault Break.
- **Challenge:** FVG Duo + Flash ORB + Gold ORB (RBE) + Sigma ORB.
- **Funded account:** NQ Precision Bot + Opening-Shock Continuation + Sigma ORB + Vault Break (statistical screen only — NQ Precision Bot fails Tradeify's microscalping rule, so it is not a Tradeify funded book).
- **Recovery score:** Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB. This is a ranking label, not approval to trade near the loss limit.

**MT5 CFD books**
- **Live account:** Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Tokyo Coil.
- **Challenge:** Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive.
- **Funded account:** Flash ORB + Gold ORB (RBE) + GotobiFix USDJPY + Tokyo Coil.
- **Recovery score:** Gold ORB (RBE) + GotobiFix EURJPY + Tokyo Coil + Vault Break. This is not a near-floor recovery recommendation.

**The two prop-account configurations**
- **The5ers $20k Bootcamp:** challenge book Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive; funded-stage book Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil in the continuous-sizing model, and Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB at the real minimum-lot size. The model's base case is USD 25 total risk per book trade across a 3-step evaluation ($5k/$10k/$15k) and a $20k funded account; the minimum-lot stage-sizing report supersedes it for execution decisions.
- **Tradeify $50k Growth:** challenge book FVG Duo + Flash ORB + Gold ORB (RBE) + Sigma ORB; funded book Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB. Minimum-micro sizing raises the modeled effective risks to roughly USD 512 and USD 476 against a USD 100 request.
- **Tradeify lower-risk alternative:** Flash ORB + Overnight Bias ORB for both stages. It is slower, but has materially better modeled survival and payout probability than the four-sleeve leader.

- **Moneta $10k 2-Step:** Phase 1 +5%, Phase 2 +10%, 4% daily and 8% static loss, three 0.5% days per phase and cycle, 88% split. Runs a two-sleeve gold-anchored phase book and a gold-free funded book.
## Executive decision summary

| Use case | NT8 / futures research book | MT5 / CFD research book |
|---|---|---|
| Standard live | Opening-Shock Continuation + Overnight Bias ORB + Sigma ORB + Vault Break | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Tokyo Coil |
| Generic challenge | FVG Duo + Flash ORB + Gold ORB (RBE) + Sigma ORB | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive |
| Generic funded | NQ Precision Bot + Opening-Shock Continuation + Sigma ORB + Vault Break (screen only) | Flash ORB + Gold ORB (RBE) + GotobiFix USDJPY + Tokyo Coil |
| Generic recovery score | Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB | Gold ORB (RBE) + GotobiFix EURJPY + Tokyo Coil + Vault Break |

These are generic portfolio-screening categories. They are not fixed labels attached to a strategy. The firm-specific simulations produce separate recommendations:

- **The5ers $20k Bootcamp:** challenge book Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive at a USD 50 target (**USD 46.83**) reaches the funded account in **90.0%** of paths with a **5.6%** evaluation breach. Switching to Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB at a USD 100 target when funded gives **91.0%** conditional first payout, a **0.2%** funded breach and **81.8%** first payout from challenge start (175 median trading days, USD 185 expected).
- **Tradeify $50k Growth:** the overall training-score challenge leader is FVG Duo + Flash ORB + Gold ORB (RBE) + Sigma ORB; the funded leader is Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB. Their USD 100 requests require about USD 511.97 and USD 475.65 effective risk after minimum-micro sizing. A lower-risk, two-sleeve alternative is Flash ORB + Overnight Bias ORB at USD 237.63 effective risk; it is slower but has stronger validation survival.

**Near-floor recovery:** The5ers is recoverable from a USD 250 cushion upward, but at the strict USD 100 cushion the best pair still carries 7.3% breach risk. Tradeify's best eligible active recovery book carries roughly a third to a half modeled breach risk. Neither firm has a recovery book that is both high-probability and low-breach at the strictest cushion.

## Gold X9 preset family

The five X9 exports are **one EA at five `TradeFrequency` settings**, not five strategies: `Extremely low` enables strategies 1-3, `Low` 1-5, `Moderate` 1-7, `High` 1-8, `Very high` 1-9. They are mutually exclusive — a book may hold **one** preset, never two — and the registry, the screening and the set-file builder all enforce that.

| Preset | Frequency | Trades | Deals | 1R at 0.01 lot | Mean R | Win rate | Trades/day | R/day | Worst validation day |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Extremely low | 0 | 558 | 1,117 | $10.15 | 0.536 | 77.6% | 0.31 | 0.31 | -9.6R |
| Low | 1 | 1,871 | 3,743 | $9.90 | 0.312 | 80.3% | 1.05 | 0.62 | -12.5R |
| Moderate | 2 | 4,147 | 8,295 | $11.65 | 0.194 | 83.8% | 2.33 | 0.83 | -19.7R |
| High | 3 | 5,525 | 11,051 | $11.02 | 0.173 | 84.6% | 3.10 | 1.04 | -30.1R |
| Very high | 4 | 13,403 | 26,807 | $13.09 | 0.087 | 88.2% | 7.52 | 1.34 | -26.4R |

All five run 2020.01.01 to 2026.11.01 on XAUUSD, M1 OHLC, USD 100k initial deposit. Higher frequency buys speed (R/day rises 4x from Extremely low to Very high) and pays for it in tail risk: the worst validation day goes from -9.6R to -30.1R. On a prop budget that spends 8% of the account on a bad day, the tail is what decides the account, so **`Low` is the standard preset** in every book below: it keeps the The5ers evaluation breach at 5.6% and the Moneta evaluation breach at 0.0% while still finishing in 116-175 days. `Moderate` is the alternative when speed matters more than breach risk; `High` and `Very high` are too tail-heavy for an account that is bought once. The prop-firm ladder therefore screens **only the standard preset**, so the raw-score book ranking cannot shortlist a preset the lot-floor study rejects; all five presets stay in the per-sleeve metrics and the normalized-live reports.

## Prop-account results in plain numbers

All probabilities below are 5,000-path, 252-trading-day estimates. Breach means a modeled firm loss-limit violation. Payout probability means at least one first payout within the horizon.

### The5ers $20k Bootcamp

- Challenge book (Steps 1-3): **Gold X9 (Low)** + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive, sized to a **USD 50** target → **USD 46.83** actual (0.94% of the $5k Step 1; gold 0.01 lot, the two GotobiFix pairs 0.12 lot, Open Drive 0.32 lot).
- Funded book: Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB at a **USD 100** target → **USD 97.68** (0.49% of $20k). No gold.
- Reach the funded account: **90.0%**. Evaluation hard breach: **5.6%**.
- First payout from a challenge start: **81.8%**; conditional on funding **91.0%**; funded hard breach **0.2%**.
- Median time to first payout: **175 trading days**; expected first payout **USD 185**.
- The old continuous USD 25 ladder still appears in the book-ranking tables for comparison only; on XAUUSD it is not placeable (one 0.01 lot already risks USD 9.90 at the Low preset).
- Presets: [The5ers set files](../Set-Files/The5ers-20K-Bootcamp/README.md).

### Moneta $10k 2-Step Standard

- Rules: Phase 1 **+5%** (USD 500), Phase 2 **+10%** (USD 1,000), **4% daily** (USD 400) and **8% static** (USD 800) maximum loss, **3 profitable days of at least 0.5%** (USD 50) per phase and per payout cycle, **88% split**, 14-day payout cycle, no consistency rule, own EAs allowed, news window **5 minutes either side** of high-impact releases in evaluation and funded alike.
- Phase book: **Gold X9 (Low)** + Overnight Bias ORB at a **USD 50** target → **USD 44.26** actual (0.44% of the account; gold 0.02 lot = USD 19.80, OBR 0.40 lot = USD 24.46).
- Funded book: Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB at a **USD 100** target → **USD 97.68** (0.98%), no gold.
- Reach funding: **99.7%**. Evaluation hard breach: **0.0%**.
- First payout from a challenge start: **98.8%**; conditional on funding **99.1%**; funded hard breach **0.4%**.
- Median time to first payout: **116 trading days**; expected first payout **USD 249**.
- Phase 2 is the constraint: 10% against an 8% static budget. The USD 44 book needs 23R for it.
- Presets: [Moneta set files](../Set-Files/Moneta-2Step-10K/README.md).

### Tradeify $50k Growth — higher-return four-sleeve route

- Challenge book: FVG Duo + Flash ORB + Gold ORB (RBE) + Sigma ORB.
- Funded book: Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB.
- USD 100 requested risk becomes **USD 511.97** effective challenge risk and **USD 475.65** effective funded risk after minimum-micro sizing.
- Challenge pass: **66.80%**; evaluation hard breach: **33.20%**.
- Funded first-payout probability, conditional on funding with the funded book: **77.43%**.
- Funded hard breach, conditional on funding: **34.78%**.
- Approximate first-payout probability per challenge start when switching to the funded book: **51.70%**.
- Approximate combined hard-breach probability across both stages: **56.43%**.
- Funded-book expected first payout across all paths: **USD 784.35**; median payout on successful paths: **USD 1,350**.
- Median time to first payout: **73 trading days**.
- Approximate 90-trading-day funded survival: **72.16%**.
- Geometric repeat estimate: **1.93 challenge accounts** and **1.29 funded accounts** per first payout.

### Tradeify — lower-risk two-sleeve alternative

- Use Flash ORB + Overnight Bias ORB for both challenge and funded stages.
- USD 100 requested risk becomes **USD 237.63** effective risk.
- Challenge pass: **86.58%**; evaluation hard breach: **12.76%**.
- First-payout probability from challenge start: **64.68%**.
- Funded hard breach, conditional on funding: **18.50%**.
- Approximate combined hard-breach probability across both stages: **28.78%**.
- Approximate 90-trading-day funded survival: **91.16%**.
- Expected first payout across all paths: **USD 873.18**; median payout on successful paths: **USD 1,350**.
- Median time to first payout: **180 trading days**.
- Geometric repeat estimate: **1.55 challenge accounts** and **1.34 funded accounts** per first payout.

**Minimum contract reality (this is the size you actually place).** NT8 sizing is whole contracts, and one contract on MNQ or MGC is already one micro. 1R per micro in the exports is USD 127-182 depending on the sleeve (FVG Duo 168, Sigma ORB 182, Overnight Bias 139, Gold ORB RBE 134, Opening-Shock 130, Flash ORB 127), which makes the broker minimum a large position on this account:

| Allocation per sleeve | Risk per book trade | % of USD 50k | R to the USD 2,000 trail | Challenge pass | Payout from challenge start | Funded breach |
|---|---:|---:|---:|---:|---:|---:|
| 1 micro (Flash + Overnight pair) | USD 237.63 | 0.48% | 8.4 | 86.4% | 64.1% | 19.0% |
| 1 micro (four-sleeve challenge book) | USD 511.97 | 1.02% | 3.9 | 67.4% | 45.6% | 40.0% |
| 2 micros (four-sleeve) | USD 1,023.94 | 2.05% | 2.0 | not reliable | not reliable | not reliable |
| 5 micros (four-sleeve) | USD 2,559.85 | 5.12% | 0.8 | not reliable | not reliable | not reliable |

Above one micro the simulator's USD 1,250 soft-DLL clip binds on 3-21% of days and hides the loss instead of breaching, so those rows are scale illustrations, not odds. At one micro the clip binds on 0.6% of challenge-book days and never on the two-sleeve pair, which is why the pair is the only allocation the model evaluates exactly.

Settings, both stages: `FixedContracts = 1` on MNQ/MGC for each sleeve; on Flash ORB, FVG Duo and Open Drive keep `UseFixedContracts = true` so `RiskPercent` cannot scale the book up as the balance grows. The four-mini cap is not the binding constraint — the USD 2,000 trail is. Your 0.5%-per-sleeve rule (about USD 250, i.e. ~2 micros) is physically placeable under the cap but leaves roughly 2R to the trail. Do not scale anything at funding; only swap FVG Duo for Opening-Shock Continuation. Full table: [stage sizing in whole contracts](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/stage_sizing.md).

The repeat estimates assume each new account has the same probability and is independent. They exclude challenge fees and resets. The combined breach figures combine evaluation breach with funded breach conditional on passing; funded breaches can occur after a payout, so breach and payout events are not mutually exclusive.

**Tradeify switch caveat:** the challenge and funded books are simulated separately. The 51.70% combined first-payout estimate multiplies the challenge book's pass rate by the funded book's conditional first-payout rate. The model does not replay a mid-account strategy switch. Each book's expected payout-cash total is a same-book scenario.

## Expected monthly PnL and drawdown

These are 5,000-path validation bootstrap estimates at the base risk shown. A month is 21 trading sessions.

| Prop book | Effective risk | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252-day max DD |
|---|---:|---:|---:|---:|---:|
| The5ers challenge book | USD 25 | USD 238 | -USD 40 | USD 236 | USD 615 |
| Tradeify challenge book | USD 512 | USD 1,995 | -USD 1,111 | USD 2,558 | USD 7,003 |
| Tradeify funded book | USD 476 | USD 1,527 | -USD 822 | USD 2,028 | USD 5,395 |
| Tradeify lower-risk pair | USD 238 | USD 634 | -USD 522 | USD 1,119 | — |

P10 monthly PnL is a weak-month estimate. P90 monthly DD is the 90th-percentile peak-to-trough drawdown inside a 21-session block. P95 252-day max DD is the 95th-percentile full-year strategy drawdown.

Monthly figures are not reported for the The5ers funded-stage book in this build; its funded-stage payout and survival estimates are in the table above.

**Important:** monthly PnL and drawdown are the strategy stream before account failures, daily-loss clipping, payout rules, payout splits and withdrawal resets. They are not monthly cash withdrawals. Account-level payout expectations are listed above and in each firm's `book_recommendations.md`.

## What the four categories mean

- **Live:** no evaluation deadline. Prioritize durable expectancy, drawdown control, stable monthly behavior, and a portfolio that can be run repeatedly. The normalized live books use the requested fixed sizing rather than an account balance.
- **Challenge:** reach the firm's target before breaching its loss limits. A faster or higher-return book can be useful here, but only if its pass probability survives the firm's actual drawdown rules.
- **Funded:** protect the funded account and generate eligible withdrawals. Survival, consistency, winning-day requirements, activity rules, and payout processing matter more than simply reaching the challenge target.
- **Recovery:** account is close to its maximum-loss floor. The objective changes from maximizing return to preserving the remaining cushion and recovering without forcing risk. If minimum executable size creates an unacceptable breach probability, no-trade is preferable to a forced recovery book.

A strategy can be suitable in one category and unsuitable in another. The category score is applied to a *book*, and the account rules determine whether the book is actually executable and payout-eligible.

## Dataset and normalization

- **NT8:** 10 strategies, 10,599 completed trades.
- **MT5:** 15 strategies, 29,462 completed trades, including the three GotobiFix pairs, FVG Duo and Gold X9.
- The refreshed Gold ORB (RBE) exports are included: **1,216 NT8 trades** on **GC DEC26** (full-size GC, not MGC) and **1,164 MT5 trades** on **XAUUSD**.
- Export history runs through **2026-10-30** on NT8 and **2026-11-19** on MT5. The normalized portfolio split is chronological: first 60% for training, later 40% for validation. Validation starts **2023-09-13** on NT8 and **2024-02-19** on MT5.
- All 385 NT8 and 1,940 MT5 one-to-four-sleeve combinations are screened on the normalized daily-R series and receive firm-specific 5,000-path Monte Carlo across the full risk ladder. Primary challenge/funded books are selected on training-only scores; validation MC is the holdout estimate, while the validation-best row is shown only as a diagnostic.
- The risk unit is each sleeve's **mean absolute realized losing-trade PnL from the training sample**, held fixed in validation. MT5 cash flows are divided by traded volume before calibration, so the balance-compounding Gold X9 and Tokyo Coil exports enter at per-lot risk. This is a reproducible normalization proxy, not verified initial stop risk.
- **NT8 live sizing:** one contract per strategy sleeve. One GC contract and one NQ contract are not equal-risk exposures; the combined dollar curve is not risk-equalized.
- **MT5 live sizing:** USD 100 risk proxy per completed trade, based on the training-period per-lot realized-loss unit. This is position-level normalization; broker minimum lots, symbol specifications, and fractional-size constraints are not enforced.
- Live equity curves start at USD 0. No account balance is assumed.

### Fresh RBE results in the normalized live reports

| Platform | Trades | 1R realized-loss proxy | Expectancy | Win rate | Net PnL at requested live sizing | Max drawdown | Daily PF | Daily Sharpe |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| NT8 Gold ORB (RBE), 1 contract | 1,216 | $813.14 | 0.313R | 45.2% | $309,588 | $35,135 | 1.419 | 1.291 |
| MT5 Gold ORB (RBE), $100/trade | 1,164 | $823.38 | 0.405R | 48.0% | $47,186 | $4,709 | 1.579 | 1.721 |

MT5 RBE deals have no position ID. Entry/exit legs are paired by symbol and opposite side, exact volume first and FIFO fallback. The refreshed export has no unmatched exit legs, unclosed entry legs, or volume mismatches, but overlapping positions mean the reconstructed entry times and durations retain pairing uncertainty.

## Per-sleeve results — standard live sizing

The figures below are from the normalized live equity reports. Daily PF and Sharpe use daily aggregated net PnL. The 1R column is a training-period realized-loss proxy.

### NT8 — one contract per strategy

| Strategy | Trades | 1R loss proxy | Expectancy/trade | Win rate | Net PnL | Max DD | Daily PF | Daily Sharpe |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| FVG Duo | 1,407 | $1,452.22 | 0.177R | 52.0% | $361,400 | $30,443 | 1.327 | 1.248 |
| Flash ORB | 1,207 | $1,149.96 | 0.132R | 56.3% | $181,201 | $15,468 | 1.271 | 1.254 |
| Gold ORB (RBE) | 1,216 | $813.14 | 0.313R | 45.2% | $309,588 | $35,135 | 1.419 | 1.291 |
| NQ Precision Bot | 688 | $635.87 | 0.017R | 89.0% | $7,260 | $12,628 | 1.127 | 0.298 |
| Open Drive | 1,760 | $1,007.80 | 0.168R | 44.7% | $305,654 | $45,562 | 1.283 | 1.096 |
| Opening-Shock Continuation | 482 | $1,088.99 | 0.106R | 62.7% | $55,765 | $25,000 | 1.241 | 0.741 |
| Overnight Bias ORB | 673 | $1,226.39 | 0.324R | 57.1% | $267,561 | $14,852 | 1.712 | 1.741 |
| Sigma ORB | 1,066 | $1,704.38 | 0.232R | 58.0% | $417,329 | $34,422 | 1.522 | 1.660 |
| VWAP Pullback | 657 | $600.86 | 0.167R | 50.4% | $65,920 | $9,701 | 1.299 | 0.898 |
| Vault Break | 1,443 | $946.00 | 0.099R | 62.9% | $134,530 | $11,275 | 1.434 | 1.342 |

### MT5 — USD 100 risk proxy per trade

The MT5 figures are computed on **per-lot** PnL: each trade's cash flow is divided
by its traded volume before the 1R unit is calibrated. This removes the
balance-based compounding in the Gold X9 and Tokyo Coil exports, so the sleeves
are comparable to each other and to the NT8 one-contract sleeve. Gold X9 appears
once per preset; the five are the same EA at different frequencies, and the net
and drawdown columns are in risk units (R) so the presets can be compared without
the compounding run's dollar scale.

| Strategy | Trades | 1R loss proxy | Expectancy/trade | Win rate | Net PnL | Max DD | Daily PF | Daily Sharpe |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| FVG Duo | 1,257 | $87.62 | 0.161R | 51.9% | $20,297 | $1,825 | 1.317 | 1.247 |
| Flash ORB | 1,280 | $65.37 | 0.111R | 55.9% | $14,165 | $1,718 | 1.247 | 1.207 |
| Gold ORB (RBE) | 1,164 | $823.38 | 0.405R | 48.0% | $47,186 | $4,709 | 1.579 | 1.721 |
| Gold X9 (Extremely low) | 558 | $1,015.47 | 0.614R | 76.5% | $342.58R | $16.79R | 3.631 | 1.916 |
| Gold X9 (Low) | 1,871 | $989.96 | 0.396R | 79.7% | $741.48R | $18.94R | 2.904 | 2.860 |
| Gold X9 (Moderate) | 4,147 | $1,165.35 | 0.250R | 82.3% | $1,035.83R | $64.44R | 2.387 | 2.904 |
| Gold X9 (High) | 5,525 | $1,102.11 | 0.235R | 82.3% | $1,299.30R | $79.99R | 2.279 | 2.842 |
| Gold X9 (Very high) | 13,403 | $1,309.00 | 0.128R | 86.3% | $1,720.56R | $90.94R | 2.056 | 3.145 |
| GotobiFix EURJPY | 946 | $104.11 | 0.349R | 61.7% | $32,994 | $1,196 | 2.320 | 2.345 |
| GotobiFix GBPJPY | 953 | $147.63 | 0.237R | 61.2% | $22,602 | $1,541 | 1.890 | 1.821 |
| GotobiFix USDJPY | 952 | $102.61 | 0.322R | 63.4% | $30,698 | $2,024 | 2.185 | 2.253 |
| NQ Precision Bot | 796 | $26.23 | 0.030R | 72.4% | $2,404 | $2,386 | 1.099 | 0.379 |
| Noise Band Momentum | 1,230 | $66.89 | 0.136R | 51.7% | $16,752 | $3,737 | 1.271 | 1.074 |
| Open Drive | 1,759 | $37.89 | 0.139R | 38.8% | $24,470 | $5,845 | 1.195 | 0.897 |
| Opening-Shock Continuation | 495 | $54.06 | 0.075R | 61.4% | $3,691 | $2,490 | 1.165 | 0.566 |
| Overnight Bias ORB | 722 | $61.14 | 0.284R | 56.1% | $20,530 | $1,131 | 1.629 | 1.749 |
| Sigma ORB | 2,149 | $83.32 | 0.052R | 48.9% | $11,140 | $4,813 | 1.103 | 0.543 |
| Tokyo Coil | 782 | $167.09 | 0.269R | 41.7% | $21,070 | $2,760 | 1.452 | 1.399 |
| Vault Break | 1,541 | $47.44 | 0.075R | 61.6% | $11,493 | $1,564 | 1.317 | 1.130 |

### Tradeify microscalping screen

The Tradeify payout rule requires more than 50% of trades and more than 50% of positive profit to come from trades lasting over 10 seconds. NT8 NQ Precision Bot fails this screen:

- Trades over 10 seconds: **23.4%**.
- Positive profit from trades over 10 seconds: **17.0%**.

The other NT8 sleeves in this dataset pass the historical duration/profit screen. The recommended Flash ORB + Overnight Bias ORB pair has 100% duration coverage, 100% of trades over 10 seconds, and 100% of positive profit from those trades. This is a historical validation check, not a guarantee that future executions remain eligible.

## Per-sleeve role assessment

These roles describe what each sleeve contributes inside a book. They are not instructions to run every sleeve alone. Tradeify's weekly-activity rule makes the distinction especially important: **FVG Duo and Open Drive are the only NT8 single sleeves that pass the historical weekly screen**. Flash ORB and Overnight Bias ORB become eligible when combined.

### NT8 futures sleeves

| Sleeve | Best-supported role | Evidence and constraint |
|---|---|---|
| FVG Duo | New return anchor; challenge contributor | 0.177R expectancy, PF 1.327, Sharpe 1.248 and $30.4k max DD over 1,407 trades. One of only two NT8 singles that pass Tradeify weekly activity; its 10R bootstrap tail is 93.78%, so it belongs in a return book, not a near-floor one. |
| Overnight Bias ORB | Live anchor; Tradeify book stabilizer | Strongest NT8 single-sleeve daily PF/Sharpe (1.712 / 1.741), $14.9k max DD. Solo it fails Tradeify weekly activity; paired with Flash ORB it forms the leading eligible book. |
| Flash ORB | Portfolio complement; Tradeify frequency partner | Positive expectancy (0.132R) and PF 1.271. Solo it fails weekly activity, but Flash + Overnight Bias passes weekly and microscalping screens. |
| Vault Break | Live diversifier / lower-drawdown contributor | PF 1.434, Sharpe 1.342, $11.3k max DD. Useful as a smoother sleeve; weak as a standalone challenge engine. |
| Sigma ORB | Return enhancer, not a near-floor sleeve | Expectancy 0.232R and Sharpe 1.660, but bootstrap probability of a 10R drawdown is 67.56% and of 20R is 9.18%. |
| Gold ORB (RBE) | High-return sleeve; size carefully | 0.313R expectancy and $309.6k at one GC contract, but $35.1k max DD and a 99.94% simulated chance of a 10R drawdown. One GC contract is not comparable to one NQ contract. |
| Open Drive | Growth/challenge accelerator; weekly-eligible single | 0.168R expectancy and high net PnL, but $45.6k max DD and a 99.62% simulated chance of a 10R drawdown. |
| VWAP Pullback | Secondary diversifier; recovery partner for Open Drive | PF 1.299 and $9.7k max DD. Open Drive + VWAP remains a Tradeify near-floor option, but it is not the highest-probability recovery pair in this run. |
| Opening-Shock Continuation | Low-frequency diversifier | 482 trades, PF 1.241 and Sharpe 0.741. It can contribute diversification inside a book, but is weak as a standalone prop sleeve. |
| NQ Precision Bot | Low-priority research sleeve; screen artifact | 88.95% win rate masks only 0.017R expectancy and 0.298 daily Sharpe. It fails Tradeify microscalping: only 23.4% of trades and 17.0% of positive profit come from trades over 10 seconds. Its appearance in the generic funded/recovery score books is a low-drawdown artifact of the screen, not a payout-eligible recommendation. |

### MT5 CFD sleeves

| Sleeve | Best-supported role | Evidence and constraint |
|---|---|---|
| Gold X9 | Return engine / The5ers challenge anchor | 0.128R expectancy, 86.1% win rate, PF 2.024 and Sharpe 3.114 on per-lot normalized PnL over 13,436 trades. Alone at $25 book risk it passes Step 1 70.7% of the time but breaches evaluation 45.3% and funded 65.4%; it must be paired with defensive sleeves. The raw export is a balance-compounding tester run; never size it from the raw dollar curve. |
| GotobiFix EURJPY | High-quality low-drawdown contributor | 0.349R expectancy, PF 2.320, Sharpe 2.345, $1.2k max DD. Alone at $25 book risk it passes Step 1 94.3% of the time with only 4.4% evaluation breach and 0% funded breach; best standalone risk/reward among the new sleeves. |
| GotobiFix USDJPY | Challenge contributor | 0.322R expectancy, PF 2.185, Sharpe 2.253, $2.0k max DD. Alone at $25 book risk: 83.7% Step-1 pass, 14.5% evaluation breach, 0% funded breach. Strong inside a book, not alone. |
| GotobiFix GBPJPY | Diversifier | 0.237R expectancy, PF 1.890, Sharpe 1.821. Alone at $25 risk: 91.1% Step-1 pass with 5.2% evaluation breach; the slowest of the three pairs to translate that into a payout. |
| FVG Duo | Return/diversification sleeve | 0.161R expectancy, PF 1.317, Sharpe 1.247. Alone at $25 risk: 83.7% Step-1 pass, 19.1% evaluation breach, 11.5% challenge-to-payout. |
| Gold ORB (RBE) | The5ers recovery/return sleeve; live return sleeve | 0.405R expectancy. Alone at $25 risk: 72.3% Step-1 pass, 39.7% evaluation breach, 10.7% funded breach, 53.6% challenge-to-payout. Live PF/Sharpe are 1.579 / 1.721. MT5 Deals have no position IDs, so entry/exit pairing remains a data-quality caveat. |
| Overnight Bias ORB | Live anchor / recovery stabilizer | Live PF/Sharpe 1.629 / 1.749 with $1.13k max DD. Lowest MT5 10R drawdown tail (35.12%). Alone at $25 risk: 95.0% Step-1 pass with 4.4% evaluation breach. |
| Tokyo Coil | High-expectancy challenge contributor | 0.269R expectancy, PF 1.452, Sharpe 1.399. Alone at $25 risk: 83.4% Step-1 pass, 16.8% evaluation breach, 0% funded breach; a stable book member after per-lot normalization. |
| Open Drive | Aggressive challenge accelerator, weak funded anchor | 0.139R expectancy; alone at $25 risk it passes Step 1 only 64.0% of the time, with 58.0% evaluation breach and 13.9% funded breach. It raises growth potential and account risk together. |
| Noise Band Momentum | Secondary challenge contributor | 0.136R expectancy; alone at $25 risk: 72.7% Step-1 pass, 33.6% evaluation breach, 0% funded breach. Live max DD is $3.74k. |
| Flash ORB | Portfolio complement | Low standalone Step-1 pass (75.5%) and 23.7% evaluation breach at $25 risk, but 0% funded breach when it does fund. Useful for combining return streams, not a standalone pass engine. |
| Vault Break | Conservative/slow stabilizer | Alone at $25 risk: 71.1% Step-1 pass, 21.5% evaluation breach, 0% challenge-to-payout within one year. Lower breach does not make it a fast challenge choice. |
| Sigma ORB | Secondary/high-drawdown sleeve | Weak live PF/Sharpe (1.103 / 0.543); alone at $25 risk it passes Step 1 only 62.5% of the time with 53.6% evaluation breach. |
| Opening-Shock Continuation | Low-frequency diversifier | Alone at $25 risk it passes Step 1 only 45.3% of the time and reaches no payout within one year. It may diversify a multi-sleeve book but is not a solo pass engine. |
| NQ Precision Bot | Low-priority research sleeve | 0.030R expectancy and 0.379 daily Sharpe; alone at $25 risk: 63.3% Step-1 pass, 7.7% evaluation breach, no payout within one year. |

**Key distinction:** a low-breach sleeve can still be a poor challenge sleeve because it may not reach the target in time. A high-expectancy sleeve can be a poor funded sleeve because its drawdown tail threatens the payout account. The book-level Monte Carlo, not the sleeve's win rate alone, determines the category fit.

## Generic live, challenge, funded and recovery books

Book selection uses the training segment only. The table shows full-sample one-contract / USD 100-per-trade equity metrics alongside the validation block-bootstrap for the same book. `Terminal R` is the median simulated 252-day cumulative R (average constituent sleeve), `Max DD p50` is the median simulated maximum drawdown in R, and the bootstrap column is the probability that simulated max drawdown reaches 10 average-sleeve R. It is **not literal account ruin**.

| Platform | Category | Selected book | Full-sample net PnL | Full-sample max DD | Daily PF | Daily Sharpe | Bootstrap terminal R (p50) | Bootstrap max DD (R, p50) | Bootstrap P(max DD ≥ 10R) |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| NT8 | Live | Opening-Shock + Overnight Bias + Sigma + Vault | $875,185 | $32,604 | 1.629 | 2.266 | 26.50R | 5.15R | 4.12% |
| NT8 | Challenge | FVG Duo + Flash + Gold RBE + Sigma | $1,269,519 | $41,127 | 1.575 | 2.271 | 52.21R | 8.40R | 30.70% |
| NT8 | Funded | NQ Precision + Opening-Shock + Sigma + Vault | $614,884 | $32,204 | 1.549 | 2.000 | 16.91R | 4.57R | 1.94% |
| NT8 | Recovery score | Flash + Gold RBE + Opening-Shock + Sigma | $963,883 | $32,363 | 1.610 | 2.397 | 41.93R | 7.76R | 25.86% |
| MT5 | Live | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Tokyo Coil | $256,287 | $9,544 | 2.313 | 4.124 | 110.05R | 12.26R | 68.78% |
| MT5 | Challenge | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $259,686 | $7,997 | 2.152 | 3.904 | 114.17R | 13.18R | 76.28% |
| MT5 | Funded | Flash + Gold RBE + GotobiFix USDJPY + Tokyo Coil | $113,119 | $3,400 | 1.829 | 3.091 | 51.67R | 7.61R | 20.64% |
| MT5 | Recovery score | Gold RBE + GotobiFix EURJPY + Tokyo Coil + Vault | $112,744 | $4,511 | 1.845 | 3.095 | 53.46R | 7.53R | 19.88% |

Interpretation:

- The **MT5 live book** has the strongest normalized Sharpe in the screen (4.12) but a 68.78% bootstrap probability of a 10R drawdown, because Gold X9 dominates its return. It is a high-return book, not a low-risk one; the MT5 funded-category book (20.64% at 10R) is the defensive alternative.
- The **NT8 live book** has the lowest 10R drawdown-barrier probability among the NT8 category leaders (4.12%). Its full-sample dollar result is not directly comparable with MT5 because NT8 uses one contract per sleeve and includes GC as well as NQ.
- The generic **challenge books** show higher returns but materially higher 10R drawdown-barrier probabilities. That is the trade-off: a book that looks attractive for hitting a target can be too volatile for long-term live use.
- The generic **funded books** are not automatically safe funded portfolios. The NT8 funded leader contains NQ Precision Bot, which is ineligible for Tradeify payouts under the microscalping rule; use the firm-specific Tradeify funded book instead.
- The generic **recovery score** is a statistical screen. It is not the same as a prop account already sitting near its drawdown floor.

## Prop-firm account simulations

Both firms use 5,000 Monte Carlo paths over 252 trading days, with five-day blocks aligned to complete Monday-Friday weeks and sampled from the later 40% validation period.

### The5ers — USD 20,000 Bootcamp

Modeled account structure (The5ers Bootcamp, checked 2026-11-22): three sequential evaluation steps on $5,000, $10,000 and $15,000, each with a 6% target and a 5% static max loss; no daily loss limit and no time limit. The funded account is $20,000 with a 4% static max loss ($19,200 floor), a 3% daily pause, a 50% split, and payouts every 14 calendar days (modeled as 10 trading days) with a USD 300 gross minimum per payout. Bootcamp has no consistency rule. The 5% funded scale-up ladder is not modeled.

**Execution plan (whole lots, `Gold X9 (Low)`):**

| Stage | Sleeves | Lots | Risk | % of stage |
|---|---|---|---:|---:|
| Steps 1-3 | Gold X9 (Low) / GotobiFix EURJPY / GotobiFix USDJPY / Open Drive | 0.01 / 0.12 / 0.12 / 0.32 | $46.83 | 0.94% of $5k |
| Funded | Flash ORB / GotobiFix EURJPY / Tokyo Coil / Overnight Bias ORB | 0.38 / 0.24 / 0.14 / 0.40 | $97.68 | 0.49% of $20k |

- Reach the funded account: **90.0%**. Evaluation hard breach: **5.6%**.
- First payout from a challenge start: **81.8%**; conditional on funding **91.0%**; funded hard breach **0.2%**.
- Median time to first payout: **175 trading days**; expected first payout **USD 185**.
- Presets: [The5ers set files](../Set-Files/The5ers-20K-Bootcamp/README.md).

**Why there is no single headline "pass rate" any more.** The old USD 25-equal-split ladder (86.62% reach, 7.46% breach, 76.34% first payout) was built on the legacy single X9 export — the Very-high frequency run — and on continuous sizing that cannot be placed on XAUUSD. It is kept in the generated CSVs for comparison with earlier work, but it describes neither the current export set nor an executable book. The lot-floor plan above is the execution estimate; the training-score book rankings are a shortlist, not odds.


## Near-floor recovery

Recovery starts from a defined cushion above the account's breach floor. It asks whether a fixed low-size book can reach a target before the floor is breached. It does not increase size to recover losses.

### The5ers

At a USD 100 cushion above the USD 19,200 funded floor (USD 19,300 equity), the target is return to the USD 20,000 funded initial balance.

- Highest recovery probability: **Gold ORB (RBE) + Gold X9**, USD 5 total risk; 89.02% chance to return to USD 20,000, with 7.30% modeled breach (median 141 trading days).
- Best RBE-excluded alternative: **GotobiFix EURJPY + Overnight Bias ORB**, USD 25 risk; 84.06% recovery with 5.28% breach (median 158 days).
- Lowest-breach active book: **GotobiFix USDJPY + Overnight Bias ORB** at USD 5 total risk; 0% recovery and 0% observed breach. This preserves the remaining cushion in the sample but does not rebuild it.
- At a USD 250 cushion, **Gold ORB (RBE) + Gold X9** at USD 5 risk reaches the funded balance in 98.30% of paths with 0.38% breach; **Gold X9 + GotobiFix EURJPY** gives 96.54% recovery and 3.20% breach in a median of 69 days.
- At a USD 500 cushion, **FVG Duo + Gold X9** at USD 10 risk gives 99.84% recovery with 0.16% breach; **Gold ORB (RBE) + Gold X9** at USD 5 risk gives 99.80% recovery with no breach observed.
- At a USD 750 cushion, **GotobiFix USDJPY + Overnight Bias ORB** at USD 25 risk and **GotobiFix EURJPY + Overnight Bias ORB** at USD 12.50 risk both reach the funded balance in 100% of paths with no breach observed.

At the strict USD 100 cushion no book meets both the 50% recovery / 5% breach screen: the highest-probability pair carries 7.3% breach risk. From USD 250 upward the best pairs clear it comfortably. No-trade preserves the account but cannot recover it. Zero observed breaches in 5,000 paths is not proof of zero risk; the approximate one-sided 95% upper bound is 0.06%. RBE-inclusive recovery candidates inherit MT5 pairing uncertainty.

### Tradeify

The near-floor scenario starts USD 200 above the USD 50,100 locked floor (USD 50,300 account balance), with one micro per active sleeve.

- To rebuild a USD 500 buffer, **Gold ORB (RBE) + Sigma ORB** is the best weekly-eligible active book: 61.36% recovery and 38.64% breach at USD 251.75 effective risk per book trade. **NQ Precision Bot + VWAP Pullback** is slightly higher (62.22% / 37.78% at USD 123.67) but fails weekly activity, so it is not a compliant choice.
- To reach the USD 53,000 balance threshold from USD 200, **NQ Precision Bot + Overnight Bias ORB** leads at 47.98% recovery / 50.82% breach (USD 186.23 effective risk), but it also fails weekly activity. **Overnight Bias ORB + VWAP Pullback** gives 47.86% / 51.70% at USD 182.72.
- From a USD 500 cushion, rebuilding the USD 500 buffer is essentially immediate for qualifying sleeves: **Vault Break** at USD 94.60 effective risk and **Sigma ORB** at USD 170.44 both reach it in a median of one trading day in the simulation.
- From the same USD 500 cushion to the USD 53,000 balance target, **NQ Precision Bot + Overnight Bias ORB** gives 73.84% recovery / 24.66% breach; **Overnight Bias ORB** alone gives 72.44% / 25.82% at USD 122.64 effective risk. Neither is weekly-eligible as a single low-frequency book.

No weekly-eligible active candidate meets the 5% near-floor breach-risk threshold from USD 200. **No-trade is the mathematical drawdown control, not a compliant long-term Tradeify operating mode:** the minimum-activity rule still requires at least one trade per Monday-Friday week. The model does not simulate Tradeify's idle-time warning/grace process.

## How to use the results

1. Use the **Normalized-Live** category books as starting points for standard accounts, not as prop-firm recommendations.
2. Use the **The5ers Bootcamp** and **Tradeify** Monte Carlo reports for account-specific challenge/funded decisions. Do not transfer a risk setting from one firm to the other.
3. For Tradeify, compare requested risk with effective risk after minimum micro sizing. The minimum contract rule can make actual risk more than twice the requested USD 100 budget.
4. Treat recovery as a separate account state. Near the floor, do not assume a positive-expectancy strategy is a safe recovery book.
5. Keep the original strategy-native entries and exits unchanged. No strategy stop redesign or parameter optimization was performed in this report.

## Method and limitations

- One chronological 60/40 train/validation split; this is not multi-fold walk-forward certification.
- Monte Carlo uses 5,000 paths, a 252-trading-day horizon and five-day Monday-Friday block bootstrap. These are one-year scenario probabilities, not lifetime pass or payout probabilities. Paths that have not completed a phase or payout by day 252 count as non-passes/no payout, not necessarily hard breaches. Conditional funded breach and payout rates cover only the remaining horizon after funding, not a full 252 days post-funding. Tradeify's separate 90-day survival statistic uses only paths funded early enough to observe 90 further trading days.
- Live drawdown barriers of 10R/20R/50R are balance-free R-based diagnostics, not literal account ruin.
- The5ers phase transitions occur on the next simulated trading day; account activation delays and the funded 5% scale-up ladder are not simulated.
- The5ers evaluation has no daily loss limit; its funded 3% daily pause is a soft-pause rule modeled as a closed-PnL clip. Tradeify's daily limits are also soft-pause rules. Closed-PnL simulations cannot see intraday floating losses or exact trigger sequences.
- Tradeify's five $150 winning-day test uses net closed daily PnL; the 35% consistency test uses gross daily PnL before commissions. Both use exit-date calendar buckets. Export timestamps are not converted to the firm's 6 PM–5 PM ET trading-day boundary.
- Tradeify weekly activity is treated as a strict evaluation/funded eligibility screen; the official idle-time warning/grace process is not modeled.
- The Tradeify soft DLL is clipped at USD 1,250 initially and USD 2,000 after the USD 53,000 threshold. The model assumes the higher limit remains after payouts.
- The MT5 RBE Deals export has no position IDs; FIFO matching leaves residual uncertainty in reconstructed entry times and durations, though cash flows reconcile.
- No independent minute-bar strategy replay, tick-level replay, margin simulation, broker-specific spread/slippage model, or live execution certification was performed. The uploaded NQ M1 archive has since been decoded locally into an unadjusted continuous Last series, but it has not yet been used to validate exported trades.
- NT8 live curves use one contract per strategy; one GC and one NQ contract are not equal-risk. MT5 live curves use a USD 100 per-lot realized-loss risk proxy and do not enforce broker minimum lots.
- MT5 Gold X9 and Tokyo Coil are balance-compounding tester runs. Raw exporter dollars are shown only in the raw platform reports; the normalized and prop layers divide each trade's cash flow by its traded volume first, so those results are per-lot and directly comparable across sleeves.
- These are historical scenario estimates, not guarantees or live-deployment approvals.

## Detailed files

- [NT8 normalized strategy metrics](../Normalized-Live/NT8/reports/strategy_metrics.csv)
- [MT5 normalized strategy metrics](../Normalized-Live/MT5/reports/strategy_metrics.csv)
- [NT8 all book combinations](../Normalized-Live/NT8/reports/all_book_combinations.csv)
- [MT5 all book combinations](../Normalized-Live/MT5/reports/all_book_combinations.csv)
- [NT8 live bootstrap drawdown risk](../Normalized-Live/NT8/reports/live_bootstrap_risk_of_ruin.csv)
- [MT5 live bootstrap drawdown risk](../Normalized-Live/MT5/reports/live_bootstrap_risk_of_ruin.csv)
- [The5ers Monte Carlo results](../Prop-Firms/The5ers-20K-Bootcamp/reports/monte_carlo_challenge_payout.csv)
- [Tradeify Monte Carlo results](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/monte_carlo_evaluation_funded_payout.csv)
- [The5ers recovery scenarios](../Prop-Firms/The5ers-20K-Bootcamp/reports/recovery_mode.csv)
- [Tradeify recovery scenarios](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/recovery_mode.csv)
- [NQ minute archive data audit](nq_minute_data_audit.md)
- [Prop-firm methodology and official rule sources](../Prop-Firms/methodology.md)
