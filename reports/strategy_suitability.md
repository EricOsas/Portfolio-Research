# Strategy and book suitability report

**Updated:** 2026-11-22  
**Scope:** 10 NT8 and 15 MT5 registered exports; all one-to-four-sleeve books re-screened.  
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
- **FTMO $10k 2-Step:** challenge book Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive; funded book Flash ORB + Gold ORB (RBE) + GotobiFix USDJPY + Tokyo Coil. The model's base case is USD 50 total risk per book trade.
- **Tradeify $50k Growth:** challenge book FVG Duo + Flash ORB + Gold ORB (RBE) + Sigma ORB; funded book Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB. Minimum-micro sizing raises the modeled effective risks to roughly USD 512 and USD 476 against a USD 100 request.
- **Tradeify lower-risk alternative:** Flash ORB + Overnight Bias ORB for both stages. It is slower, but has materially better modeled survival and payout probability than the four-sleeve leader.

## Executive decision summary

| Use case | NT8 / futures research book | MT5 / CFD research book |
|---|---|---|
| Standard live | Opening-Shock Continuation + Overnight Bias ORB + Sigma ORB + Vault Break | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Tokyo Coil |
| Generic challenge | FVG Duo + Flash ORB + Gold ORB (RBE) + Sigma ORB | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive |
| Generic funded | NQ Precision Bot + Opening-Shock Continuation + Sigma ORB + Vault Break (screen only) | Flash ORB + Gold ORB (RBE) + GotobiFix USDJPY + Tokyo Coil |
| Generic recovery score | Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB | Gold ORB (RBE) + GotobiFix EURJPY + Tokyo Coil + Vault Break |

These are generic portfolio-screening categories. They are not fixed labels attached to a strategy. The firm-specific simulations produce separate recommendations:

- **FTMO $10k 2-Step:** training-selected challenge book Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive at USD 50 total risk passes both phases in 98.48% of paths and reaches a first reward in 97.96%. The funded book Flash ORB + Gold ORB (RBE) + GotobiFix USDJPY + Tokyo Coil has a 95.68% conditional first-reward rate and a 0.02% conditional funded breach rate at USD 50 risk.
- **Tradeify $50k Growth:** the overall training-score challenge leader is FVG Duo + Flash ORB + Gold ORB (RBE) + Sigma ORB; the funded leader is Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB. Their USD 100 requests require about USD 511.97 and USD 475.65 effective risk after minimum-micro sizing. A lower-risk, two-sleeve alternative is Flash ORB + Overnight Bias ORB at USD 237.63 effective risk; it is slower but has stronger validation survival.

**Near-floor recovery:** FTMO is materially recoverable at every tested cushion with the new MT5 books, but the best recovery candidates carry meaningful breach risk. Tradeify's best eligible active recovery book still carries roughly a third to a half modeled breach risk. Neither firm has a recovery book that is both high-probability and low-breach at the strictest cushion.

## Prop-account results in plain numbers

All probabilities below are 5,000-path, 252-trading-day estimates. Breach means a modeled firm loss-limit violation. Payout probability means at least one first payout within the horizon.

### FTMO $10k 2-Step CFD

- Challenge book: Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive.
- Funded book: Flash ORB + Gold ORB (RBE) + GotobiFix USDJPY + Tokyo Coil.
- Total requested risk: USD 50 per book trade, split equally across four sleeves.
- Pass both phases: **98.48%**.
- Evaluation hard breach: **1.42%**.
- Funded hard breach, conditional on funding: **0.91%**.
- First-reward probability from challenge start: **97.96%**.
- Approximate combined hard-breach probability across evaluation and funded stages: **1.4%**.
- Expected first reward across all paths: **USD 253.40**; median reward on successful paths: **USD 215.71**.
- Median time to first reward: **81 trading days**.
- Geometric repeat estimate: **1.06 challenge accounts** and **1.05 funded accounts** per first reward.

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
- Median time to first payout: **164 trading days**.
- Geometric repeat estimate: **1.55 challenge accounts** and **1.34 funded accounts** per first payout.

The repeat estimates assume each new account has the same probability and is independent. They exclude challenge fees and resets. The combined breach figures combine evaluation breach with funded breach conditional on passing; funded breaches can occur after a payout, so breach and payout events are not mutually exclusive.

**Tradeify switch caveat:** the challenge and funded books are simulated separately. The 51.70% combined first-payout estimate multiplies the challenge book's pass rate by the funded book's conditional first-payout rate. The model does not replay a mid-account strategy switch. Each book's expected payout-cash total is a same-book scenario.

## Expected monthly PnL and drawdown

These are 5,000-path validation bootstrap estimates at the base risk shown. A month is 21 trading sessions.

| Prop book | Effective risk | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252-day max DD |
|---|---:|---:|---:|---:|---:|
| FTMO challenge book | USD 50 | USD 476 | -USD 80 | USD 471 | USD 1,230 |
| FTMO funded book | USD 50 | USD 218 | -USD 101 | USD 266 | USD 687 |
| Tradeify challenge book | USD 512 | USD 1,995 | -USD 1,111 | USD 2,558 | USD 7,003 |
| Tradeify funded book | USD 476 | USD 1,527 | -USD 822 | USD 2,028 | USD 5,395 |
| Tradeify lower-risk pair | USD 238 | USD 634 | -USD 522 | USD 1,119 | — |

P10 monthly PnL is a weak-month estimate. P90 monthly DD is the 90th-percentile peak-to-trough drawdown inside a 21-session block. P95 252-day max DD is the 95th-percentile full-year strategy drawdown.

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
are comparable to each other and to the NT8 one-contract sleeve.

| Strategy | Trades | 1R loss proxy | Expectancy/trade | Win rate | Net PnL | Max DD | Daily PF | Daily Sharpe |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| FVG Duo | 1,257 | $87.62 | 0.161R | 51.9% | $20,297 | $1,825 | 1.317 | 1.247 |
| Flash ORB | 1,280 | $65.37 | 0.111R | 55.9% | $14,165 | $1,718 | 1.247 | 1.207 |
| Gold ORB (RBE) | 1,164 | $823.38 | 0.405R | 48.0% | $47,186 | $4,709 | 1.579 | 1.721 |
| Gold X9 | 13,436 | $1,295.70 | 0.128R | 86.1% | $171,524 | $9,186 | 2.024 | 3.114 |
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
| Gold X9 | Return engine / FTMO challenge anchor | 0.128R expectancy, 86.1% win rate, PF 2.024 and Sharpe 3.114 on per-lot normalized PnL over 13,436 trades. Single-sleeve FTMO evaluation breach is 50.0% at $50 risk, so it must be paired with defensive sleeves. The raw export is a balance-compounding tester run; never size it from the raw dollar curve. |
| GotobiFix EURJPY | High-quality low-drawdown contributor | 0.349R expectancy, PF 2.320, Sharpe 2.345, $1.2k max DD. Single-sleeve FTMO: 58.38% first reward, 0.26% evaluation breach. Best standalone risk/reward among the new sleeves. |
| GotobiFix USDJPY | Challenge contributor | 0.322R expectancy, PF 2.185, Sharpe 2.253, $2.0k max DD. Single-sleeve FTMO evaluation breach 24.38% at $50 risk; strong inside a book, not alone. |
| GotobiFix GBPJPY | Diversifier | 0.237R expectancy, PF 1.890, Sharpe 1.821. Lowest first-reward rate of the three pairs (39.96%) but a small 0.52% single-sleeve evaluation breach. |
| FVG Duo | Return/diversification sleeve | 0.161R expectancy, PF 1.317, Sharpe 1.247. Single-sleeve FTMO first reward 72.18% with 5.70% evaluation breach. |
| Gold ORB (RBE) | FTMO challenge/funded contributor; live return sleeve | 0.405R expectancy. At $50 book risk alone: 72.52% challenge-to-first-reward, 22.34% evaluation breach and 13.08% funded breach. Live PF/Sharpe are 1.579 / 1.721. MT5 Deals have no position IDs, so entry/exit pairing remains a data-quality caveat. |
| Overnight Bias ORB | Live anchor / FTMO stabilizer | Live PF/Sharpe 1.629 / 1.749 with $1.13k max DD. Lowest MT5 10R drawdown tail (35.12%). FTMO single-sleeve first reward 72.48% with 0.44% evaluation breach. |
| Tokyo Coil | High-expectancy challenge contributor | 0.269R expectancy, PF 1.452, Sharpe 1.399. FTMO single-sleeve first reward 54.40%, evaluation breach 3.88%; a stable book member after per-lot normalization. |
| Open Drive | Aggressive challenge accelerator, weak funded anchor | 0.139R expectancy, but FTMO evaluation breach 36.78% and funded breach 19.83% at $50 risk. It raises growth potential and account risk together. |
| Noise Band Momentum | Secondary challenge contributor | 0.136R expectancy; FTMO first-reward rate 50.88%, evaluation breach 15.74% and funded breach 5.38%. Live max DD is $3.74k. |
| Flash ORB | Portfolio complement | Lower standalone FTMO first-reward rate (34.04%) but only 6.38% evaluation breach and 1.62% funded breach at $50 risk. Useful for combining return streams, not a standalone pass engine. |
| Vault Break | Conservative/slow stabilizer | FTMO first-reward rate 16.38%, evaluation breach 4.46% and funded breach 0.36% at $50 risk. Lower breach does not make it a fast challenge choice. |
| Sigma ORB | Secondary/high-drawdown sleeve | Weak live PF/Sharpe (1.103 / 0.543); FTMO evaluation breach 33.26% and funded breach 12.90% at $50 risk. |
| Opening-Shock Continuation | Low-frequency diversifier | Standalone FTMO first-reward rate was 1.42% within one year. It may diversify a multi-sleeve book but should not be relied on as a solo pass engine. |
| NQ Precision Bot | Low-priority research sleeve | 0.030R expectancy and 0.379 daily Sharpe; standalone FTMO first-reward rate 2.44% within one year. |

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

### FTMO — USD 10,000 2-Step CFD

Modeled account rules: 10% Phase 1 target, 5% Verification target, USD 500 equity-based daily loss, USD 1,000 static maximum-loss floor, at least four trading days in each phase, and an 80% default reward split. The first Reward Day is modeled after approximately 10 elapsed trading days (the 11th sampled business day counting the first-trade day); four business days are reserved for review/payment with trading frozen. Cash withdrawal resets the next reference period to initial capital; rollover is not modeled and only the first reward is counted.

**Training-selected challenge book:** Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive.  
**Training-selected funded book:** Flash ORB + Gold ORB (RBE) + GotobiFix USDJPY + Tokyo Coil.  
**Risk:** USD 50 total per book trade, split equally across four sleeves. Minimum CFD lot sizes are not enforced.

| Metric | Challenge book | Funded book |
|---|---:|---:|
| Phase 1 pass rate | 99.16% | 97.86% |
| Verification pass rate, conditional on Phase 1 | 99.31% | 92.74% |
| Pass both phases | 98.48% | 90.76% |
| Challenge-to-first-reward probability | 97.96% | 86.84% |
| Evaluation hard-breach probability | 1.42% | 0.04% |
| Funded hard-breach probability, conditional on funding | 0.91% | 0.02% |
| Median trading days to Phase 1 pass | 40 | 90 |
| Median trading days to Verification pass | 64 | 135 |
| Median trading days to first reward | 81 | 152 |
| Expected first reward across all paths | USD 253.40 | USD 126.35 |
| Median first reward on successful paths | USD 215.71 | USD 104.79 |

**Challenge book risk ladder** (USD 25 / 50 / 75 / 100):

| Requested risk | Pass both | Evaluation breach | Challenge-to-payout | Funded breach, conditional | Median payout days | Expected first payout |
|---:|---:|---:|---:|---:|---:|---:|
| USD 25 | 96.9% | 0.0% | 94.7% | 0.0% | 145 | USD 125.43 |
| USD 50 | 98.5% | 1.4% | 98.0% | 0.9% | 81 | USD 253.40 |
| USD 75 | 86.8% | 13.2% | 83.8% | 7.3% | 57 | USD 324.38 |
| USD 100 | 71.1% | 28.9% | 63.7% | 21.3% | 43 | USD 347.40 |

**Funded book risk ladder:**

| Requested risk | Pass both | Evaluation breach | Challenge-to-payout | Funded breach, conditional | Median payout days | Expected first payout |
|---:|---:|---:|---:|---:|---:|---:|
| USD 25 | 34.3% | 0.0% | 26.0% | 0.0% | 217 | USD 20.53 |
| USD 50 | 90.8% | 0.0% | 86.8% | 0.0% | 152 | USD 126.35 |
| USD 75 | 97.1% | 0.8% | 95.3% | 0.6% | 111 | USD 205.09 |
| USD 100 | 96.3% | 3.1% | 94.9% | 2.1% | 88 | USD 260.33 |

USD 50 is the base case for the challenge book; above USD 75 the same book starts breaching the daily loss limit often enough to reduce pass probability, even though expected payout keeps rising. The funded book is the opposite: its pass rate improves with size because the target is reached faster, and the breach cost stays low until USD 100.

**Holdout validation leader — diagnostic only:** FVG Duo + Gold X9 + GotobiFix EURJPY + Overnight Bias ORB records 99.5% pass-both, 99.3% challenge-to-first-reward and 0.5% evaluation breach at USD 50 risk. It is not the primary selection because it was identified as the validation leader after the training-only selection; promoting it would use the holdout to choose the book.

**RBE-excluded sensitivity:** the training-selected challenge and funded books already exclude MT5 Gold ORB (RBE), so the RBE-pairing caveat does not affect either primary selection. The RBE-excluded and RBE-included challenge candidates are identical in this run.

The full risk ladders are in [FTMO book recommendations](../Prop-Firms/FTMO-10K-2-Step-CFD/reports/book_recommendations.md) and [the Monte Carlo CSV](../Prop-Firms/FTMO-10K-2-Step-CFD/reports/monte_carlo_challenge_payout.csv). The simulation is close-only: FTMO's equity-based loss rules can be breached by floating losses that are absent from the MT5 exports. Phase review/KYC delays are also omitted, so time-to-funded estimates are optimistic, and the 98% challenge pass rate should be treated as a closed-PnL upper bound.

### Tradeify — USD 50,000 Growth futures

Modeled Growth rules: USD 3,000 evaluation target, no evaluation consistency rule, USD 2,000 EOD trailing drawdown with a USD 50,100 funded locked floor after the USD 52,100 threshold, USD 1,250 initial soft daily-loss limit, and a funded DLL increase to USD 2,000 from the next session after the balance reaches USD 53,000. This assumes current non-legacy rules for accounts purchased on or after September 12, 2025; older accounts have different DLL and payout thresholds. Funded payout modeling applies 35% consistency, five winning days above USD 150, the USD 53,000 balance threshold, the 90% payout share, payout caps and two trading days for processing. **The 35% consistency test uses gross daily PnL before commissions; account balance, drawdown, DLL and the $150 winning-day test use net closed PnL.** Weekly activity and microscalping are eligibility screens; position-limit compliance is required for executable sizing.

**Overall training-score challenge candidate:** FVG Duo + Flash ORB + Gold ORB (RBE) + Sigma ORB.

- USD 100 requested risk; **USD 511.97 effective risk** after one micro per active sleeve.
- Eligible evaluation pass: **66.80%**; evaluation hard-breach: **33.20%**.
- Challenge-to-first-payout: **46.12%**.
- Funded first-payout rate conditional on funding: **69.04%**.
- Funded hard-breach, conditional on funding: **38.38%**.
- Approximate 90-trading-day funded survival: **64.55%**.
- Median evaluation pass: **20 trading days**; median first payout: **57 trading days**.
- Expected first net payout across all paths: **USD 622.62**; expected total net payout cash: **USD 3,721.13** (1.80 payouts on average).

**Overall training-score funded candidate:** Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB.

- USD 100 requested risk; **USD 475.65 effective risk** after one micro per active sleeve.
- Eligible evaluation pass: **75.04%**; evaluation hard-breach: **24.96%**.
- Challenge-to-first-payout: **58.10%**.
- Conditional first-payout rate after funding: **77.43%**.
- Funded hard-breach, conditional on funding: **34.78%**.
- Approximate 90-trading-day funded survival: **72.16%**.
- Median evaluation pass: **30 trading days**; median first payout: **73 trading days**.
- Expected first net payout across all paths: **USD 784.35**; expected total net payout cash: **USD 4,585.71** (2.23 payouts on average).

**Lower-risk two-sleeve alternative:** Flash ORB + Overnight Bias ORB. This is the top training-funded-score candidate within the eligible two-sleeve subset, not the overall training-score winner.

| Requested risk/book trade | Effective risk | Evaluation pass | Evaluation breach | Challenge-to-first-payout | Funded breach, conditional | 90-day funded survival | Expected first net payout | Median days to first payout |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| USD 100 | USD 237.63 | 86.58% | 12.76% | 64.68% | 18.50% | 91.16% | USD 873.18 | 164 |

The USD 100 request produces USD 237.63 effective risk because both sleeves are already at the minimum one micro. It is slower than the four-sleeve score leaders (79 trading days median to evaluation pass and 164 days to first payout) but shows lower funded breach and higher 90-day survival. It was included based on its training-funded score within the two-sleeve subset; do not treat its stronger holdout result as proof that it is superior. Expected total net payout cash across all paths during the 252-day horizon is **USD 2,168.67**, with a mean of **1.29 payouts**. Weekly activity, position-limit and microscalping screens all pass for this pair.

**Challenge and funded risk ladders:**

| Book | Requested risk | Effective risk | Pass both | Evaluation breach | Challenge-to-payout | Funded breach, conditional | 90-day survival | Median payout days | Expected first payout |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Challenge | USD 100–500 | USD 511.97 | 66.8% | 33.2% | 46.1% | 38.4% | 64.6% | 57 | USD 622.62 |
| Challenge | USD 750 | USD 593.28 | 62.5% | 37.5% | 39.3% | 44.1% | 57.9% | 45 | USD 531.09 |
| Funded | USD 100–500 | USD 475.65 | 75.0% | 25.0% | 58.1% | 34.8% | 72.2% | 73 | USD 784.35 |
| Funded | USD 750 | USD 556.96 | 65.7% | 34.3% | 42.0% | 43.9% | 58.7% | 53 | USD 567.00 |

**Holdout validation leader — diagnostic only:** Flash ORB + NQ Precision Bot + Overnight Bias ORB + VWAP Pullback shows 87.3% evaluation pass, 12.5% evaluation breach and 71.7% challenge-to-payout. It is not a recommendation: NQ Precision Bot fails the funded microscalping eligibility screen, so this book could not be paid out as modeled.

The full risk ladders for the challenge and funded score leaders, plus the two-sleeve alternative, are in [Tradeify book recommendations](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/book_recommendations.md) and [the Monte Carlo CSV](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/monte_carlo_evaluation_funded_payout.csv).

The USD 2,000 DLL step-up is modeled as persistent once unlocked. Daily loss clipping is an approximation: intraday trigger timing, trade order, floating equity, slippage and overshoot are not reconstructable from closed-trade exports. Same-entry-day MAEs are stacked conservatively in the separate MAE report; this is not a synchronized intraday replay.

## Near-floor recovery

Recovery starts from a defined cushion above the account's breach floor. It asks whether a fixed low-size book can reach a target before the floor is breached. It does not increase size to recover losses.

### FTMO

At a USD 100 cushion above the USD 9,000 static floor (USD 9,100 equity), the target is return to the USD 10,000 initial balance.

- Highest recovery probability: **Gold X9 + GotobiFix EURJPY**, USD 10 total risk; 81.28% chance to return to USD 10,000, with 17.58% modeled breach (median 110 trading days).
- Next best: **FVG Duo + Gold X9**, USD 10 risk; 80.64% recovery and 18.70% breach; **Gold X9 + GotobiFix GBPJPY**, USD 10 risk; 80.58% recovery and 18.62% breach.
- Lowest-breach active book: **GotobiFix USDJPY + Overnight Bias ORB** at USD 5 total risk; 0% recovery and 0% observed breach. This preserves the remaining cushion in the sample but does not rebuild it.
- At a USD 250 cushion, **Gold X9 + Noise Band Momentum** at USD 10 risk reaches initial equity in 95.96% of paths with 3.40% breach; **Gold X9 + GotobiFix EURJPY** gives 95.94% recovery and 3.20% breach.
- At a USD 500 cushion, **FVG Duo + Gold X9** at USD 10 risk gives 99.68% recovery with 0.16% breach; **Gold ORB (RBE) + Gold X9** at USD 5 risk gives 99.04% recovery with no breach observed.
- At a USD 750 cushion, **FVG Duo + Gold X9** at USD 10 risk gives 100% recovery with no breach observed in 5,000 paths.

The USD 100 cushion now clears the 50% recovery bar, but at roughly 17–19% breach risk. That is a real trade-off, not a safe recovery: if the account is only USD 100 above the floor, the highest-probability recovery books risk losing it about one time in five. No-trade preserves the account but cannot recover it. Zero observed breaches in 5,000 paths is not proof of zero risk; the approximate one-sided 95% upper bound is 0.06%. RBE-inclusive recovery candidates inherit MT5 pairing uncertainty.

### Tradeify

The near-floor scenario starts USD 200 above the USD 50,100 locked floor (USD 50,300 account balance), with one micro per active sleeve.

- To rebuild a USD 500 buffer, **Gold ORB (RBE) + Sigma ORB** is the best weekly-eligible active book: 61.36% recovery and 38.64% breach at USD 251.75 effective risk per book trade. **NQ Precision Bot + VWAP Pullback** is slightly higher (62.22% / 37.78% at USD 123.67) but fails weekly activity, so it is not a compliant choice.
- To reach the USD 53,000 balance threshold from USD 200, **NQ Precision Bot + Overnight Bias ORB** leads at 47.98% recovery / 50.82% breach (USD 186.23 effective risk), but it also fails weekly activity. **Overnight Bias ORB + VWAP Pullback** gives 47.86% / 51.70% at USD 182.72.
- From a USD 500 cushion, rebuilding the USD 500 buffer is essentially immediate for qualifying sleeves: **Vault Break** at USD 94.60 effective risk and **Sigma ORB** at USD 170.44 both reach it in a median of one trading day in the simulation.
- From the same USD 500 cushion to the USD 53,000 balance target, **NQ Precision Bot + Overnight Bias ORB** gives 73.84% recovery / 24.66% breach; **Overnight Bias ORB** alone gives 72.44% / 25.82% at USD 122.64 effective risk. Neither is weekly-eligible as a single low-frequency book.

No weekly-eligible active candidate meets the 5% near-floor breach-risk threshold from USD 200. **No-trade is the mathematical drawdown control, not a compliant long-term Tradeify operating mode:** the minimum-activity rule still requires at least one trade per Monday-Friday week. The model does not simulate Tradeify's idle-time warning/grace process.

## How to use the results

1. Use the **Normalized-Live** category books as starting points for standard accounts, not as prop-firm recommendations.
2. Use the **FTMO** and **Tradeify** Monte Carlo reports for account-specific challenge/funded decisions. Do not transfer a risk setting from one firm to the other.
3. For Tradeify, compare requested risk with effective risk after minimum micro sizing. The minimum contract rule can make actual risk more than twice the requested USD 100 budget.
4. Treat recovery as a separate account state. Near the floor, do not assume a positive-expectancy strategy is a safe recovery book.
5. Keep the original strategy-native entries and exits unchanged. No strategy stop redesign or parameter optimization was performed in this report.

## Method and limitations

- One chronological 60/40 train/validation split; this is not multi-fold walk-forward certification.
- Monte Carlo uses 5,000 paths, a 252-trading-day horizon and five-day Monday-Friday block bootstrap. These are one-year scenario probabilities, not lifetime pass or payout probabilities. Paths that have not completed a phase or payout by day 252 count as non-passes/no payout, not necessarily hard breaches. Conditional funded breach and payout rates cover only the remaining horizon after funding, not a full 252 days post-funding. Tradeify's separate 90-day survival statistic uses only paths funded early enough to observe 90 further trading days.
- Live drawdown barriers of 10R/20R/50R are balance-free R-based diagnostics, not literal account ruin.
- FTMO phase review/verification/KYC delays are omitted; phase transitions occur on the next simulated trading day.
- FTMO and Tradeify daily loss rules are equity-based/soft-pause rules. Closed-PnL simulations cannot see intraday floating losses or exact trigger sequences.
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
- [FTMO Monte Carlo results](../Prop-Firms/FTMO-10K-2Step-CFD/reports/monte_carlo_challenge_payout.csv)
- [Tradeify Monte Carlo results](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/monte_carlo_evaluation_funded_payout.csv)
- [FTMO recovery scenarios](../Prop-Firms/FTMO-10K-2Step-CFD/reports/recovery_mode.csv)
- [Tradeify recovery scenarios](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/recovery_mode.csv)
- [NQ minute archive data audit](nq_minute_data_audit.md)
- [Prop-firm methodology and official rule sources](../Prop-Firms/methodology.md)
