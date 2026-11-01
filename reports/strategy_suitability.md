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

- **FTMO $10k 2-Step:** Gold ORB (RBE) + Open Drive + Overnight Bias ORB + Tokyo Coil at USD 50 total risk per book trade.
- **Tradeify $50k Growth:** Flash ORB + Overnight Bias ORB. USD 100 requested risk still requires USD 237.23 effective risk after the minimum one-micro-per-sleeve rule. A USD 250 request produces the same position size.

**Near-floor recovery:** no active book passes the 5% modeled breach-risk screen at the tested near-floor cushions. No-trade is the control. The best active Tradeify recovery candidate still has substantial modeled breach risk, and the apparent higher-recovery alternatives fail the weekly-activity rule.

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
- All 255 NT8 and 385 MT5 one-to-four-sleeve combinations are screened on the normalized daily-R series. The prop Monte Carlo covers every single sleeve plus selected category finalists and leading two-/three-sleeve candidates; it does not run 5,000 paths for every possible combination.
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

Modeled account rules: 10% Phase 1 target, 5% Verification target, USD 500 equity-based daily loss, USD 1,000 static maximum-loss floor, at least four trading days in each phase, 80% reward split, and first reward request after the 14-day waiting period. The model uses 10 elapsed trading days (the 11th sampled business day counting the first-trade day) as the waiting-period approximation and four business days for reward review/payment processing.

**Selected book:** Gold ORB (RBE) + Open Drive + Overnight Bias ORB + Tokyo Coil.  
**Risk:** USD 50 total per book trade, split equally across the four sleeves. Minimum CFD lot sizes are not enforced.

| Requested risk/book trade | Pass Phase 1 | Pass both phases | Evaluation breach | Funded breach, conditional | Challenge-to-first-reward | Expected first reward across all paths | Median reward if paid | Median days to first reward |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| $25 | 92.46% | 67.82% | 0.00% | 0.00% | 57.54% | $53.99 | $69.29 | 199 |
| $50 | 98.92% | 96.46% | 0.54% | 0.35% | 94.06% | $164.02 | $125.78 | 127 |
| $75 | 98.12% | 96.26% | 3.26% | 1.79% | 94.42% | $243.56 | $185.80 | 93 |
| $100 | 95.38% | 92.20% | 7.74% | 5.36% | 88.94% | $312.96 | $249.54 | 74 |

At USD 50, the model gives the best balanced result: 96.46% pass-both probability and 94.06% challenge-to-first-reward probability, with a 0.54% modeled evaluation breach rate and 0.35% funded breach rate conditional on funding. USD 75 reaches the first reward sooner and has a slightly higher challenge-to-reward rate, but breach probability rises. USD 100 is materially more aggressive.

The high modeled pass rates must be read with the close-only limitation: FTMO's loss rules are equity-based, while these exports do not contain complete floating equity. Phase review/KYC delays are also omitted, so time-to-funded estimates are optimistic.

### Tradeify — USD 50,000 Growth futures

Modeled Growth rules: USD 3,000 evaluation target, no evaluation consistency rule, USD 2,000 EOD trailing drawdown with a USD 50,100 locked floor after the USD 52,100 threshold, USD 1,250 initial soft daily-loss limit, and a funded DLL increase to USD 2,000 from the next session after the balance reaches USD 53,000. This assumes the current non-legacy rules for accounts purchased on or after September 12, 2025; older accounts have different DLL and payout thresholds. Funded payout modeling applies 35% consistency, five winning days above USD 150, the USD 53,000 balance threshold, the 90% payout share, payout caps and two trading days for processing. Weekly activity and microscalping are funded payout-eligibility checks, not evaluation pass conditions. Position-limit compliance is required for executable book sizing.

**Selected book:** Flash ORB + Overnight Bias ORB.

| Requested risk/book trade | Effective risk after micro minimums | Evaluation pass | Evaluation breach | Challenge-to-first-payout | Funded first payout, conditional | Funded breach, conditional | 90-day funded survival | Expected first net payout across all paths | Median first payout if paid | Median days to first payout |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| $100 | $237.23 | 84.30% | 15.10% | 61.56% | 73.02% | 21.21% | 89.31% | $831.06 | $1,350 | 163 |
| $250 | $237.23 | 84.30% | 15.10% | 61.56% | 73.02% | 21.21% | 89.31% | $831.06 | $1,350 | 163 |
| $500 | $474.45 | 64.16% | 35.84% | 40.50% | 63.12% | 46.01% | 59.88% | $546.75 | $1,350 | — |
| $750 | $711.68 | 58.74% | 41.26% | 31.66% | 53.90% | 53.76% | 48.69% | $427.41 | $1,350 | — |

The USD 100 and USD 250 requests produce identical sizing because both sleeves are already at the minimum one micro. The effective risk proxy is USD 237.23, not USD 100. Increasing the request to USD 500 or USD 750 increases actual exposure sharply and worsens pass probability, funded breach probability and 90-day survival.

For the USD 100/250 case:

- Median time to eligible evaluation pass: **76 trading days**.
- Median time from funding to first payout: **81 trading days**.
- Expected total net payout cash across all paths during the 252-day horizon: **USD 2,000.40**.
- Mean payout count: **1.20**.
- Weekly activity, position limit and microscalping screens all pass for this pair.

The USD 2,000 DLL step-up is modeled as persistent once unlocked. Daily loss clipping is still only an approximation: intraday trigger timing, trade order, floating equity, slippage and overshoot are not reconstructable from the closed-trade exports.

## Near-floor recovery

Recovery starts from a defined cushion above the account's breach floor. It asks whether a fixed low-size book can reach a target before the floor is breached. It does not increase size to recover losses.

### FTMO

At USD 100 cushion above the USD 9,000 static floor (USD 9,100 equity), the target is return to the USD 10,000 initial balance. Recovery sizing is USD 12.50 total risk per book trade.

- Best active candidate by recovery probability: **Tokyo Coil**, 40.56% chance to return to initial balance, but 37.68% modeled breach probability.
- **No-trade:** 0% modeled breach, but also 0% chance of recovery.
- No active candidate meets the 5% breach-risk threshold at this near-floor cushion.
- At a USD 500 cushion, Gold ORB (RBE) + Tokyo Coil at USD 12.50 total book risk has an 86.66% chance to return to initial balance, with 0% breach observed in 5,000 paths; at USD 750 cushion, recovery rises to 98.08%, with 0% breach observed. This pair inherits the MT5 RBE pairing uncertainty. Tokyo Coil alone avoids RBE and gives 84.66% recovery with 0.60% breach at USD 500 cushion.

### Tradeify

The near-floor scenario starts USD 200 above the USD 50,100 locked floor (USD 50,300 account balance), with one micro per active sleeve.

Only books that pass the weekly-activity screen are treated as executable recovery candidates. The $53,000 chart additionally requires microscalping eligibility, but payout consistency, five winning days and payout processing are not enforced in the balance-recovery simulation.

For the weekly-eligible **Flash ORB + Overnight Bias ORB** pair:

- Chance to rebuild a USD 500 buffer above the locked floor: **56.62%**; modeled breach probability: **43.38%**.
- Chance to reach the USD 53,000 balance target: **39.78%**; modeled breach probability: **60.12%**.
- With USD 1,500 cushion instead of USD 200, chance to reach USD 53,000 rises to **91.02%**, but breach probability remains **8.86%**.

Some apparently stronger recovery candidates, including Overnight Bias ORB alone and Opening-Shock Continuation + Overnight Bias ORB, fail the weekly-activity screen and are not valid Tradeify recovery choices. No weekly-eligible active candidate meets the 5% near-floor breach-risk threshold. **No-trade is the mathematical drawdown control, not a compliant long-term Tradeify operating mode:** the minimum-activity rule still requires at least one trade per Monday-Friday week. The model does not simulate Tradeify's idle-time warning/grace process.

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
