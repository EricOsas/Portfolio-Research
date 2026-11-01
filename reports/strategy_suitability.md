# Strategy and book suitability report

**Updated:** 2026-11-01  
**Purpose:** classify sleeves and portfolios for standard live accounts, prop-firm challenges, funded accounts, and near-drawdown recovery. This is a historical research screen, not a live-deployment approval.

## Executive decision summary

| Use case | NT8 / futures research book | MT5 / CFD research book |
|---|---|---|
| Standard live | Opening-Shock Continuation + Overnight Bias ORB + Sigma ORB + Vault Break | Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Overnight Bias ORB |
| Generic challenge | Flash ORB + Gold ORB (RBE) + Sigma ORB + Vault Break | Flash ORB + Gold ORB (RBE) + Open Drive + Tokyo Coil |
| Generic funded | Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB | Flash ORB + Gold ORB (RBE) + Open Drive + Tokyo Coil |
| Generic recovery score | Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB | Gold ORB (RBE) + Opening-Shock Continuation + Tokyo Coil + Vault Break |

These are generic portfolio-screening categories. They are not fixed labels attached to a strategy. The firm-specific simulations produce separate recommendations:

- **FTMO $10k 2-Step:** training-selected challenge_book_1 — Flash ORB + Gold ORB (RBE) + Open Drive + Tokyo Coil, at USD 50 total risk. It passes both phases in 95.12% of paths and reaches a first reward in 92.88%. The validation-best challenge_book_3 is diagnostic only, not the selected book.
- **Tradeify $50k Growth:** overall training-score leaders are challenge_book_1 (Flash ORB + Gold ORB (RBE) + Sigma ORB + Vault Break) and funded_book_1 (Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB). Their USD 100 requests require USD 457.35 and USD 472.83 effective risk after minimum-micro sizing. A lower-risk, two-sleeve alternative is Flash ORB + Overnight Bias ORB at USD 237.23 effective risk; it is slower but has stronger validation survival.

**Near-floor recovery:** at the strict starting cushions ($100 FTMO; $200 Tradeify), no active book achieves both at least 50% recovery probability and at most 5% breach probability. Tradeify's best eligible active recovery book still has about 41% modeled breach risk; the lowest-exposure single sleeve is only marginally safer. FTMO becomes materially more recoverable as the remaining cushion grows.

## What the four categories mean

- **Live:** no evaluation deadline. Prioritize durable expectancy, drawdown control, stable monthly behavior, and a portfolio that can be run repeatedly. The normalized live books use the requested fixed sizing rather than an account balance.
- **Challenge:** reach the firm's target before breaching its loss limits. A faster or higher-return book can be useful here, but only if its pass probability survives the firm's actual drawdown rules.
- **Funded:** protect the funded account and generate eligible withdrawals. Survival, consistency, winning-day requirements, activity rules, and payout processing matter more than simply reaching the challenge target.
- **Recovery:** account is close to its maximum-loss floor. The objective changes from maximizing return to preserving the remaining cushion and recovering without forcing risk. If minimum executable size creates an unacceptable breach probability, no-trade is preferable to a forced recovery book.

A strategy can be suitable in one category and unsuitable in another. The category score is applied to a *book*, and the account rules determine whether the book is actually executable and payout-eligible.

## Dataset and normalization

- **NT8:** 9 strategies, 9,192 completed trades.
- **MT5:** 10 strategies, 11,918 completed trades. Gold X9 remains missing; the MT5 set is 10 of 11 expected exports.
- The refreshed Gold ORB (RBE) exports are included: **1,216 NT8 trades** on **GC DEC26** (full-size GC, not MGC) and **1,164 MT5 trades** on **XAUUSD**.
- Export history runs through **2026-10-30**. The normalized portfolio split is chronological: first 60% for training, later 40% for validation. Validation is **2024-02-07 to 2026-10-30**.
- All 255 NT8 and 385 MT5 one-to-four-sleeve combinations are screened on the normalized daily-R series and receive firm-specific 5,000-path Monte Carlo across the full risk ladder. Primary challenge/funded books are selected on training-only scores; validation MC is the holdout estimate, while the validation-best row is shown only as a diagnostic.
- The risk unit is each sleeve's **mean absolute realized losing-trade PnL from the training sample**, held fixed in validation. This is a reproducible normalization proxy, not verified initial stop risk.
- **NT8 live sizing:** one contract per strategy sleeve. One GC contract and one NQ contract are not equal-risk exposures; the combined dollar curve is not risk-equalized.
- **MT5 live sizing:** USD 100 risk proxy per completed trade, based on the training-period realized-loss unit. This is position-level normalization; broker minimum lots, symbol specifications, and fractional-size constraints are not enforced.
- Live equity curves start at USD 0. No account balance is assumed.

### Fresh RBE results in the normalized live reports

| Platform | Trades | 1R realized-loss proxy | Expectancy | Win rate | Net PnL at requested live sizing | Max drawdown | Daily PF | Daily Sharpe |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| NT8 Gold ORB (RBE), 1 contract | 1,216 | $806.76 | 0.316R | 45.2% | $309,588 | $35,135 | 1.419 | 1.383 |
| MT5 Gold ORB (RBE), $100/trade | 1,164 | $740.20 | 0.239R | 48.0% | $27,820 | $2,061 | 1.554 | 1.825 |

MT5 RBE deals have no position ID. Entry/exit legs are paired by symbol and opposite side, exact volume first and FIFO fallback. The refreshed export has no unmatched exit legs, unclosed entry legs, or volume mismatches, but overlapping positions mean the reconstructed entry times and durations retain pairing uncertainty.

## Per-sleeve results — standard live sizing

The figures below are from the normalized live equity reports. Daily PF and Sharpe use daily aggregated net PnL. The 1R column is a training-period realized-loss proxy.

### NT8 — one contract per strategy

| Strategy | Trades | 1R loss proxy | Expectancy/trade | Win rate | Net PnL | Max DD | Daily PF | Daily Sharpe |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Flash ORB | 1,207 | $1,153.65 | 0.131R | 56.3% | $181,201 | $15,468 | 1.271 | 1.343 |
| Gold ORB (RBE) | 1,216 | $806.76 | 0.316R | 45.2% | $309,588 | $35,135 | 1.419 | 1.383 |
| NQ Precision Bot | 688 | $635.87 | 0.017R | 89.0% | $7,260 | $12,628 | 1.127 | 0.319 |
| Open Drive | 1,760 | $988.24 | 0.171R | 44.7% | $305,654 | $45,562 | 1.283 | 1.173 |
| Opening-Shock Continuation | 482 | $1,101.78 | 0.105R | 62.7% | $55,765 | $25,000 | 1.241 | 0.793 |
| Overnight Bias ORB | 673 | $1,218.60 | 0.326R | 57.1% | $267,561 | $14,852 | 1.712 | 1.865 |
| Sigma ORB | 1,066 | $1,666.14 | 0.238R | 58.0% | $417,329 | $34,422 | 1.522 | 1.779 |
| VWAP Pullback | 657 | $595.34 | 0.169R | 50.4% | $65,920 | $9,701 | 1.299 | 0.962 |
| Vault Break | 1,443 | $946.93 | 0.098R | 62.9% | $134,530 | $11,275 | 1.434 | 1.437 |

### MT5 — USD 100 risk proxy per trade

| Strategy | Trades | 1R loss proxy | Expectancy/trade | Win rate | Net PnL | Max DD | Daily PF | Daily Sharpe |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Flash ORB | 1,280 | $65.32 | 0.111R | 55.9% | $14,175 | $1,720 | 1.247 | 1.212 |
| Gold ORB (RBE) | 1,164 | $740.20 | 0.239R | 48.0% | $27,820 | $2,061 | 1.554 | 1.825 |
| NQ Precision Bot | 796 | $77.49 | 0.034R | 72.4% | $2,742 | $1,610 | 1.135 | 0.567 |
| Noise Band Momentum | 1,230 | $1,459.14 | 0.156R | 51.7% | $19,138 | $3,491 | 1.275 | 1.118 |
| Open Drive | 1,759 | $559.41 | 0.267R | 38.8% | $46,899 | $5,420 | 1.321 | 1.222 |
| Opening-Shock Continuation | 495 | $732.46 | 0.079R | 61.4% | $3,931 | $1,362 | 1.206 | 0.737 |
| Overnight Bias ORB | 722 | $729.61 | 0.224R | 56.1% | $16,202 | $1,222 | 1.582 | 1.705 |
| Sigma ORB | 2,149 | $83.53 | 0.052R | 48.9% | $11,111 | $4,801 | 1.103 | 0.545 |
| Tokyo Coil | 782 | $2,222.10 | 0.391R | 41.7% | $30,596 | $3,672 | 1.499 | 1.415 |
| Vault Break | 1,541 | $706.35 | 0.075R | 61.6% | $11,502 | $1,565 | 1.317 | 1.134 |

### Tradeify microscalping screen

The Tradeify payout rule requires more than 50% of trades and more than 50% of positive profit to come from trades lasting over 10 seconds. NT8 NQ Precision Bot fails this screen:

- Trades over 10 seconds: **23.4%**.
- Positive profit from trades over 10 seconds: **17.0%**.

The other NT8 sleeves in this dataset pass the historical duration/profit screen. The recommended Flash ORB + Overnight Bias ORB pair has 100% duration coverage, 100% of trades over 10 seconds, and 100% of positive profit from those trades. This is a historical validation check, not a guarantee that future executions remain eligible.

## Per-sleeve role assessment

These roles describe what each sleeve contributes inside a book. They are not instructions to run every sleeve alone. Tradeify's weekly-activity rule makes the distinction especially important: **Open Drive is the only NT8 single sleeve that passes the historical weekly screen**. Flash ORB and Overnight Bias ORB become eligible when combined.

### NT8 futures sleeves

| Sleeve | Best-supported role | Evidence and constraint |
|---|---|---|
| Overnight Bias ORB | Live anchor; Tradeify book stabilizer | Strongest NT8 single-sleeve daily PF/Sharpe (1.712 / 1.865), $14.9k max DD. Solo it fails Tradeify weekly activity; paired with Flash ORB it forms the leading eligible book. |
| Flash ORB | Portfolio complement; Tradeify frequency partner | Positive expectancy (0.131R) and PF 1.271. Solo it fails weekly activity, but Flash + Overnight Bias passes weekly and microscalping screens. |
| Vault Break | Live diversifier / lower-drawdown contributor | PF 1.434, Sharpe 1.437, $11.3k max DD. Useful as a smoother sleeve; weak as a standalone challenge engine. |
| Sigma ORB | Return enhancer, not a near-floor sleeve | Expectancy 0.238R and Sharpe 1.779, but bootstrap probability of a 10R drawdown is 78.44% and of 20R is 15.70%. |
| Gold ORB (RBE) | High-return sleeve; size carefully | 0.316R expectancy and $309.6k at one GC contract, but $35.1k max DD and 100% simulated chance of a 10R drawdown. One GC contract is not comparable to one NQ contract. |
| Open Drive | Growth/challenge accelerator; only weekly-eligible single | 0.171R expectancy and high net PnL, but $45.6k max DD and 99.8% simulated chance of a 10R drawdown. Tradeify solo funded hard-breach estimate is 41.15% conditional on funding. |
| VWAP Pullback | Secondary diversifier; recovery partner for Open Drive | PF 1.299 and $9.7k max DD. Open Drive + VWAP is the best Tradeify near-floor buffer-recovery pair by probability, but still has about 40.7% modeled breach risk at a $200 cushion. |
| Opening-Shock Continuation | Low-frequency diversifier | 482 trades, PF 1.241 and Sharpe 0.793. It can contribute diversification inside a book, but is weak as a standalone prop sleeve. |
| NQ Precision Bot | Low-priority research sleeve | 88.95% win rate masks only 0.017R expectancy and 0.319 daily Sharpe. It fails Tradeify microscalping: only 23.4% of trades and 17.0% of positive profit come from trades over 10 seconds. |

### MT5 CFD sleeves

| Sleeve | Best-supported role | Evidence and constraint |
|---|---|---|
| Gold ORB (RBE) | FTMO challenge/funded contributor; live return sleeve | At $50 book risk alone: 84.80% challenge-to-first-reward, 2.22% evaluation breach and 0.77% funded breach. Live PF/Sharpe are 1.554 / 1.825. MT5 Deals have no position IDs, so entry/exit pairing remains a data-quality caveat. |
| Overnight Bias ORB | Live anchor / FTMO stabilizer | Live PF/Sharpe 1.582 / 1.705 with $1.22k max DD. FTMO single-sleeve evaluation and funded breach were 0% in 5,000 paths, but first-reward rate was only 41.46%; it is a stabilizer, not a fast challenge engine. |
| Tokyo Coil | High-expectancy challenge contributor | 0.391R expectancy and FTMO first-reward rate 73.78% at $50 risk. Its single-sleeve evaluation breach was 15.60% and funded breach 8.71%; combine with lower-risk sleeves rather than treating it as safe alone. |
| Open Drive | Aggressive challenge accelerator, weak funded anchor | 0.267R expectancy, but FTMO evaluation breach 41.90% and funded breach 29.91% at $50 risk. It raises growth potential and account risk together. |
| Noise Band Momentum | Secondary challenge contributor | FTMO first-reward rate 62.60%, but evaluation breach 18.00% and funded breach 7.85%. Live max DD is $3.49k. |
| Flash ORB | Portfolio complement | Lower standalone FTMO first-reward rate (34.82%) but only 5.96% evaluation breach and 1.38% funded breach at $50 risk. Useful for combining return streams, not a standalone pass engine. |
| Vault Break | Conservative/slow stabilizer | FTMO first-reward rate 16.80%, evaluation breach 4.56% and funded breach 0.95% at $50 risk. Lower breach does not make it a fast challenge choice. |
| Sigma ORB | Secondary/high-drawdown sleeve | Weak live PF/Sharpe (1.103 / 0.545); FTMO evaluation breach 33.34% and funded breach 12.40% at $50 risk. |
| Opening-Shock Continuation | Low-frequency diversifier | Standalone FTMO first-reward rate was 0.06% within one year. It may diversify a multi-sleeve book but should not be relied on as a solo pass engine. |
| NQ Precision Bot | Low-priority research sleeve | 0.034R expectancy and 0.567 daily Sharpe; standalone FTMO first-reward rate was 0.04% within one year. |

**Key distinction:** a low-breach sleeve can still be a poor challenge sleeve because it may not reach the target in time. A high-expectancy sleeve can be a poor funded sleeve because its drawdown tail threatens the payout account. The book-level Monte Carlo, not the sleeve's win rate alone, determines the category fit.

## Generic live, challenge, funded and recovery books

Book selection uses the training segment only. The table shows full-sample one-contract / USD 100-per-trade equity metrics alongside later validation metrics. Validation net R, Sharpe and drawdown are based on the average constituent-sleeve R series, allowing books of different sizes to be compared. The bootstrap column is the probability that validation max drawdown reaches 10 average-sleeve R within 252 simulated trading days; it is **not literal account ruin**.

| Platform | Category | Selected book | Full-sample net PnL | Full-sample max DD | Daily PF | Daily Sharpe | Validation net R | Validation Sharpe | Validation max DD | Bootstrap P(max DD ≥ 10R) |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| NT8 | Live | Opening-Shock + Overnight Bias + Sigma + Vault | $875,185 | $32,604 | 1.629 | 2.429 | 76.68R | 2.449 | 5.60R | 5.60% |
| NT8 | Challenge | Flash + Gold RBE + Sigma + Vault | $1,042,648 | $33,755 | 1.621 | 2.648 | 134.21R | 2.719 | 9.72R | 36.84% |
| NT8 | Funded | Flash + Gold RBE + Opening-Shock + Sigma | $963,883 | $32,363 | 1.610 | 2.571 | 127.44R | 2.667 | 8.94R | 33.20% |
| NT8 | Recovery score | Flash + Gold RBE + Opening-Shock + Sigma | $963,883 | $32,363 | 1.610 | 2.571 | 127.44R | 2.667 | 8.94R | 31.64% |
| MT5 | Live | Flash + Gold RBE + Opening-Shock + Overnight Bias | $62,128 | $2,623 | 1.614 | 2.641 | 82.10R | 3.104 | 6.56R | 1.26% |
| MT5 | Challenge | Flash + Gold RBE + Open Drive + Tokyo Coil | $119,490 | $5,111 | 1.628 | 2.435 | 190.10R | 2.929 | 12.78R | 59.12% |
| MT5 | Funded | Flash + Gold RBE + Open Drive + Tokyo Coil | $119,490 | $5,111 | 1.628 | 2.435 | 190.10R | 2.929 | 12.78R | 58.36% |
| MT5 | Recovery score | Gold RBE + Opening-Shock + Tokyo Coil + Vault | $73,848 | $2,423 | 1.635 | 2.466 | 103.35R | 2.808 | 6.06R | 6.30% |

Interpretation:

- The **MT5 live book** has the lowest 10R drawdown-barrier probability in this comparison and strong validation Sharpe/PF. It is the cleanest normalized live-account candidate in this screen.
- The **NT8 live book** has lower validation max drawdown than the generic NT8 challenge/funded books. Its full-sample dollar result is not directly comparable with MT5 because NT8 uses one contract per sleeve and includes GC as well as NQ.
- The generic **challenge books** show higher returns but materially higher 10R drawdown-barrier probabilities. That is the trade-off: a book that looks attractive for hitting a target can be too volatile for long-term live use.
- The generic **funded books** are not automatically safe funded portfolios. Firm-specific payout and breach simulations below take precedence.
- MT5's funded rank-2 alternative, **Gold RBE + Noise Band Momentum + Overnight Bias ORB + Tokyo Coil**, had better validation tail metrics than rank 1: 138.23R validation net, 3.273 Sharpe, 7.10R max drawdown, and 11.26% bootstrap probability of a 10R drawdown. It is a useful holdout challenger, but one 60/40 split is not enough to promote it without rolling validation.
- The generic **recovery score** is a statistical screen. It is not the same as a prop account already sitting near its drawdown floor.

## Prop-firm account simulations

Both firms use 5,000 Monte Carlo paths over 252 trading days, with five-day blocks aligned to complete Monday-Friday weeks and sampled from the later 40% validation period.

### FTMO — USD 10,000 2-Step CFD

Modeled account rules: 10% Phase 1 target, 5% Verification target, USD 500 equity-based daily loss, USD 1,000 static maximum-loss floor, at least four trading days in each phase, and an 80% default reward split. The first Reward Day is modeled after approximately 10 elapsed trading days (the 11th sampled business day counting the first-trade day); four business days are reserved for review/payment with trading frozen. Cash withdrawal resets the next reference period to initial capital; rollover is not modeled and only the first reward is counted.

**Training-selected challenge/funded book:** challenge_book_1 — Flash ORB + Gold ORB (RBE) + Open Drive + Tokyo Coil.  
**Risk:** USD 50 total per book trade, split equally across four sleeves. Minimum CFD lot sizes are not enforced.

| Metric | Holdout result |
|---|---:|
| Phase 1 pass rate | 98.50% |
| Verification pass rate, conditional on Phase 1 | 96.57% |
| Pass both phases | 95.12% |
| Challenge-to-first-reward probability | 92.88% |
| Evaluation hard-breach probability | 0.88% |
| Funded hard-breach probability, conditional on funding | 0.55% |
| Median trading days to Phase 1 pass | 68 |
| Median trading days to Verification pass | 109 |
| Median trading days to first reward | 127 |
| Expected first reward across all paths | USD 165.11 |
| Median first reward on successful paths | USD 127.52 |

**Holdout validation leader — diagnostic only:** challenge_book_3 — Gold ORB (RBE) + Open Drive + Overnight Bias ORB + Tokyo Coil. It records 96.46% pass-both, 94.64% challenge-to-first-reward, 0.54% evaluation breach and 0.31% funded breach at USD 50 risk. It is not the primary selection because it was identified as the validation leader after the training-only selection; promoting it would use the holdout to choose the book.

**RBE-excluded sensitivity:** Flash ORB + Open Drive + Overnight Bias ORB + Tokyo Coil at USD 50 risk reaches a first reward in 90.56% of paths, with 93.82% pass-both, 0.90% evaluation breach and 0.34% funded breach. Use this alternative if the MT5 RBE pairing uncertainty is unacceptable.

The full risk ladder for the training-selected book is in [FTMO book recommendations](../Prop-Firms/FTMO-10K-2Step-CFD/reports/book_recommendations.md) and [the Monte Carlo CSV](../Prop-Firms/FTMO-10K-2Step-CFD/reports/monte_carlo_challenge_payout.csv). The simulation is close-only: FTMO's equity-based loss rules can be breached by floating losses that are absent from the MT5 exports. Phase review/KYC delays are also omitted, so time-to-funded estimates are optimistic.

### Tradeify — USD 50,000 Growth futures

Modeled Growth rules: USD 3,000 evaluation target, no evaluation consistency rule, USD 2,000 EOD trailing drawdown with a USD 50,100 funded locked floor after the USD 52,100 threshold, USD 1,250 initial soft daily-loss limit, and a funded DLL increase to USD 2,000 from the next session after the balance reaches USD 53,000. This assumes current non-legacy rules for accounts purchased on or after September 12, 2025; older accounts have different DLL and payout thresholds. Funded payout modeling applies 35% consistency, five winning days above USD 150, the USD 53,000 balance threshold, the 90% payout share, payout caps and two trading days for processing. Weekly activity and microscalping are eligibility screens; position-limit compliance is required for executable sizing.

**Overall training-score challenge candidate:** challenge_book_1 — Flash ORB + Gold ORB (RBE) + Sigma ORB + Vault Break.

- USD 100 requested risk; **USD 457.35 effective risk** after one micro per active sleeve.
- Eligible evaluation pass: **71.06%**; evaluation hard-breach: **28.94%**.
- Challenge-to-first-payout: **51.92%**.
- Funded hard-breach, conditional on funding: **39.54%**.
- Approximate 90-trading-day funded survival: **66.51%**.
- Median evaluation pass: **24 trading days**; median first payout: **63 trading days**.
- Expected first net payout across all paths: **USD 700.92**; expected total net payout cash: **USD 4,523.67**.

**Overall training-score funded candidate:** funded_book_1 — Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB.

- USD 100 requested risk; **USD 472.83 effective risk** after one micro per active sleeve.
- Eligible evaluation pass: **70.52%**; evaluation hard-breach: **29.48%**.
- Challenge-to-first-payout: **52.30%**.
- Funded hard-breach, conditional on funding: **37.49%**.
- Approximate 90-trading-day funded survival: **68.15%**.
- Median evaluation pass: **28 trading days**; median first payout: **68 trading days**.
- Expected first net payout across all paths: **USD 706.05**; expected total net payout cash: **USD 4,200.03**.

**Lower-risk two-sleeve alternative:** Flash ORB + Overnight Bias ORB. This is the top training-funded-score candidate within the eligible two-sleeve subset, not the overall training-score winner.

| Requested risk/book trade | Effective risk | Evaluation pass | Evaluation breach | Challenge-to-first-payout | Funded breach, conditional | 90-day funded survival | Expected first net payout | Median days to first payout |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| USD 100 | USD 237.23 | 84.30% | 15.10% | 61.56% | 21.21% | 89.31% | USD 831.06 | 163 |
| USD 250 | USD 237.23 | 84.30% | 15.10% | 61.56% | 21.21% | 89.31% | USD 831.06 | 163 |
| USD 500 | USD 474.45 | 64.16% | 35.84% | 40.50% | 46.01% | 59.88% | USD 546.75 | — |
| USD 750 | USD 711.68 | 58.74% | 41.26% | 31.66% | 53.76% | 48.69% | USD 427.41 | — |

The USD 100 and USD 250 requests produce identical sizing because both sleeves are already at the minimum one micro. At USD 100 requested risk, the pair's effective risk is USD 237.23, not USD 100. It is slower than the four-sleeve score leaders (76 trading days median to evaluation pass and 163 days to first payout), but the validation sample shows lower funded breach and higher 90-day survival. It was included based on its training-funded score within the two-sleeve subset; do not treat its stronger holdout result as proof that it is superior.

For the USD 100/250 case, expected total net payout cash across all paths during the 252-day horizon is **USD 2,000.40**, with a mean of **1.20 payouts**. Weekly activity, position-limit and microscalping screens all pass for this pair.

The full risk ladders for the challenge and funded score leaders, plus the two-sleeve alternative, are in [Tradeify book recommendations](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/book_recommendations.md) and [the Monte Carlo CSV](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/monte_carlo_evaluation_funded_payout.csv).

The USD 2,000 DLL step-up is modeled as persistent once unlocked. Daily loss clipping is an approximation: intraday trigger timing, trade order, floating equity, slippage and overshoot are not reconstructable from closed-trade exports. Same-entry-day MAEs are stacked conservatively in the separate MAE report; this is not a synchronized intraday replay.

## Near-floor recovery

Recovery starts from a defined cushion above the account's breach floor. It asks whether a fixed low-size book can reach a target before the floor is breached. It does not increase size to recover losses.

### FTMO

At a USD 100 cushion above the USD 9,000 static floor (USD 9,100 equity), the target is return to the USD 10,000 initial balance.

- Highest recovery probability: **Gold ORB (RBE) + Tokyo Coil**, USD 25 total risk; 66.74% chance to return to USD 10,000, with 29.34% modeled breach.
- RBE-excluded alternative: **Overnight Bias ORB + Tokyo Coil**, USD 25 risk; 60.78% recovery and 28.02% breach.
- Lowest-risk single-sleeve option: **Tokyo Coil** at USD 5 risk; only 0.36% recovery and 8.94% breach. It is low exposure, but not a practical recovery engine.
- Lowest-breach active book: **Gold ORB (RBE) + Overnight Bias ORB** at USD 5 total risk; 0% recovery and 0% observed breach. This preserves the remaining cushion in the sample but does not rebuild it.
- At a USD 250 cushion, **Gold ORB (RBE) + Overnight Bias ORB** at USD 25 risk reaches initial equity in 84.06% of paths with 0.96% breach; the RBE-excluded **Overnight Bias ORB + Tokyo Coil** gives 84.36% recovery and 4.68% breach.
- At a USD 500 cushion, **Gold ORB (RBE) + Tokyo Coil** at USD 12.50 risk gives 86.20% recovery with no breach observed in 5,000 paths. The RBE-excluded **Tokyo Coil** at USD 12.50 risk gives 84.66% recovery and 0.60% breach. At a USD 750 cushion, Tokyo Coil alone at USD 5 risk gives 75.52% recovery with no breach observed.

No active book meets both the 50% recovery / 5% breach screen at the $100 cushion. No-trade preserves the account but cannot recover it. Zero observed breaches in 5,000 paths is not proof of zero risk; the approximate one-sided 95% upper bound is 0.06%. RBE-inclusive recovery candidates inherit MT5 pairing uncertainty.

### Tradeify

The near-floor scenario starts USD 200 above the USD 50,100 locked floor (USD 50,300 account balance), with one micro per active sleeve.

- To rebuild a USD 500 buffer, **Open Drive + VWAP Pullback** gives 59.30% recovery and 40.70% breach at USD 158.36 effective risk per book trade.
- The lower-exposure single-sleeve option, **Open Drive alone**, gives 58.20% recovery and 41.80% breach at USD 98.82 effective risk. The small recovery-probability difference does not justify the extra pair exposure if minimizing size is the priority.
- To reach the USD 53,000 balance threshold, the leading eligible book is **Flash ORB + Overnight Bias ORB**: 38.26% recovery and 61.66% breach at USD 237.23 effective risk.

For the USD 53,000 balance target, the same Flash ORB + Overnight Bias ORB book gives 61.28% recovery / 38.60% breach from a USD 500 cushion, 81.96% / 17.90% from USD 1,000, and 91.86% / 8.06% from USD 1,500. These are balance-recovery probabilities only, not approved payouts; funded consistency, five $150 winning days and payout processing are not enforced in this recovery simulation.

No weekly-eligible active candidate meets the 5% near-floor breach-risk threshold. **No-trade is the mathematical drawdown control, not a compliant long-term Tradeify operating mode:** the minimum-activity rule still requires at least one trade per Monday-Friday week. The model does not simulate Tradeify's idle-time warning/grace process.

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
- Tradeify profitable days and 35% consistency use exit-date calendar buckets. Export timestamps are not converted to the firm's 6 PM–5 PM ET trading-day boundary.
- Tradeify weekly activity is treated as a strict evaluation/funded eligibility screen; the official idle-time warning/grace process is not modeled.
- The Tradeify soft DLL is clipped at USD 1,250 initially and USD 2,000 after the USD 53,000 threshold. The model assumes the higher limit remains after payouts.
- The MT5 RBE Deals export has no position IDs; FIFO matching leaves residual uncertainty in reconstructed entry times and durations, though cash flows reconcile.
- No independent tick-level replay, margin simulation, broker-specific spread/slippage model, or live execution certification was performed.
- NT8 live curves use one contract per strategy; one GC and one NQ contract are not equal-risk. MT5 live curves use a USD 100 realized-loss risk proxy per trade and do not enforce broker minimum lots.
- MT5 Gold X9 remains missing.
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
- [Prop-firm methodology and official rule sources](../Prop-Firms/methodology.md)
