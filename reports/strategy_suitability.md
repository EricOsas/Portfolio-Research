# Strategy and book suitability

**Status:** research shortlist only. These classifications are account-specific, not permanent labels attached to a strategy.

## How to read the four categories

- **Live book:** prioritize sustainable expectancy, validation performance, manageable drawdown and operational simplicity. No evaluation target or payout consistency rule.
- **Challenge book:** prioritize reaching the evaluation target before a hard breach. A faster/higher-risk variant may be acceptable, but more risk does not automatically improve pass probability.
- **Funded book:** prioritize payout eligibility and survival. Consistency, winning-day requirements, weekly activity, microscalping and payout processing matter alongside expectancy.
- **Recovery book:** protect the remaining drawdown cushion and work back toward break-even or a buffer. If minimum executable size is too large for the cushion, no-trade is the correct control.

A strategy can appear in more than one category. The account rules, minimum position size, risk budget and other sleeves determine suitability.

## Standard live accounts

### NT8 — one contract equivalent per sleeve

**Primary live book:** Opening-Shock Continuation + Overnight Bias ORB + Sigma ORB + Vault Break.

- Full-sample equity gain: **$875,184.76**
- Full-sample maximum drawdown: **$32,603.88**
- Daily PF: **1.63**
- Daily Sharpe: **2.43**
- Positive-month share: **82.9%**
- Validation: **76.68R** net, **1.62** PF, **2.45** Sharpe, **5.60R** max drawdown
- 5,000-path validation bootstrap: **5.60%** chance of a 10R maximum-drawdown barrier; **0.04%** at 20R; 0% at 50R

This book was selected using training-period metrics, then checked on the later validation period. Sigma ORB's native baseline has no protective stop; that behavior was preserved and not researched or changed.

**Lower 10R-tail alternative:** NQ Precision Bot + Opening-Shock Continuation + Overnight Bias ORB + Sigma ORB.

- Full-sample equity gain: **$747,915.08**
- Full-sample maximum drawdown: **$39,397.88**
- Validation: **66.10R** net, **1.65** PF, **2.39** Sharpe, **7.36R** max drawdown
- Bootstrap 10R barrier: **2.62%**; 20R and 50R: 0%

This reduces the bootstrap 10R barrier probability but has lower full-sample net PnL and a larger dollar drawdown. Treat it as a lower-tail alternative, not an automatic replacement.

### MT5 — fixed USD 100 realized-loss risk proxy per trade

**Primary live book:** Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Overnight Bias ORB.

- Full-sample normalized equity gain: **$62,128.25**
- Full-sample maximum drawdown: **$2,622.93**
- Daily PF: **1.61**
- Daily Sharpe: **2.64**
- Positive-month share: **76.8%**
- Validation: **82.10R** net, **1.73** PF, **3.10** Sharpe, **6.56R** max drawdown
- 5,000-path validation bootstrap: **1.26%** chance of a 10R maximum-drawdown barrier; 0% at 20R and 50R

The USD 100 R unit is calibrated from the first 60% of history using each strategy's mean absolute realized losing-trade PnL. It is a sizing proxy, not verified initial stop risk.

**RBE-excluded validation sensitivity:** Flash ORB + Opening-Shock Continuation + Overnight Bias ORB + Tokyo Coil.

- Training: **73.02R** net, **7.71R** max drawdown
- Validation: **89.24R** net, **1.70** PF, **2.69** Sharpe, **6.15R** max drawdown

This alternative avoids dependence on the MT5 RBE trade-pair reconstruction. It has stronger validation net R and slightly lower validation drawdown, but lower validation Sharpe and a weaker training drawdown profile. Keep it as a robustness alternative.

### Refreshed Gold ORB (RBE) exports

- **NT8:** 1,216 trades; export identifies **GC DEC26**. One-contract normalized equity gain is approximately **$309,588**, with **$35,135** maximum drawdown.
- **MT5:** 1,164 trades; export identifies **XAUUSD**. Raw export net PnL is approximately **$205,923**; at fixed USD 100 risk per trade, normalized equity gain is **$27,819.93**, with **$2,060.98** maximum drawdown.

The MT5 Deals export has no position IDs and contains overlapping positions. Entry/exit legs are paired by symbol/side and exact volume where possible, with FIFO fallback. Cashflows reconcile, but trade duration and per-trade risk pairing remain uncertain. This is why the FTMO report includes RBE-excluded candidates.

## FTMO — USD 10,000 Standard 2-Step CFD

**Primary book:** Gold ORB (RBE) + Open Drive + Overnight Bias ORB + Tokyo Coil.

At **USD 50 total book risk per trade**:

- Pass both phases: **96.46%**
- Challenge-to-first-approved-reward probability: **94.06%**
- Evaluation hard-breach probability: **0.54%**
- Funded hard-breach probability, conditional on funding: **0.35%**
- First-reward probability conditional on funding: **97.51%**
- Median first reward after the 80% split: **$125.78**
- Mean first reward across all challenge paths: **$164.02**
- Median time from challenge start to first reward approval: **127 trading days**

**Challenge speed variant:** same book at **USD 75 total risk**.

- Pass both phases: **96.26%**
- Challenge-to-first-reward probability: **94.42%**
- Evaluation hard-breach probability: **3.26%**
- Funded hard-breach probability conditional on funding: **1.79%**
- Median first reward: **$185.80**
- Median time to first reward: **93 trading days**

The USD 75 setting is faster and produces a larger median first reward, but the overall payout probability improves only slightly while evaluation and funded breach probabilities rise. USD 50 is the better default for challenge and funded use; USD 75 is an optional speed variant, not the conservative setting. USD 100 materially worsens pass and breach rates.

**RBE-excluded alternative:** Flash ORB + Open Drive + Tokyo Coil at USD 50 total risk.

- Pass both phases: **92.02%**
- Challenge-to-first-reward probability: **88.20%**
- Evaluation hard-breach probability: **3.88%**
- Funded hard-breach probability conditional on funding: **2.65%**
- First-reward probability conditional on funding: **95.85%**
- Median first reward: **$143.04**

This is a credible alternative if the MT5 RBE pairing uncertainty is considered unacceptable, but it gives up some simulated pass/payout probability.

The FTMO model uses the default 80% cash reward split, deducts the modeled cash reward from account equity and leaves the remaining 20% of requested profit in the account. FTMO's rollover option is not simulated. The model approximates the 14-calendar-day first request rule as 10 elapsed trading days after the first funded trade, then applies a four-business-day processing delay.

## Tradeify — USD 50,000 Growth futures

**Primary challenge and funded book:** Flash ORB + Overnight Bias ORB.

At **USD 100 requested total book risk per trade**:

- Effective risk after minimum-micro sizing: **USD 237.23**
- Position size: **one micro per sleeve**, 0.2 mini-equivalent total
- Evaluation pass rate: **84.30%**
- Challenge-to-first-payout probability: **61.56%**
- Evaluation hard-breach probability: **15.10%**
- First-payout probability conditional on funding: **73.02%**
- Funded hard-breach probability conditional on funding: **21.21%**
- Approximate 90-trading-day funded survival: **89.31%**
- Median first payout net of the 90% split: **USD 1,350**
- Mean first payout across all challenge paths: **USD 831.06**
- Mean total net payout cash across all paths over the one-year horizon: **USD 2,000.40**

The book passes the modeled weekly-activity, microscalping and position-limit eligibility checks. The 5,000-path one-micro-per-sleeve MAE diagnostic gives **USD 457.90** p95 daily stacked MAE and **USD 790** maximum daily stacked MAE, with no active days above the USD 1,250 soft daily-loss threshold in this sample.

**Do not scale this book up casually.** At USD 250 requested risk, the same one-micro-per-sleeve size is selected, so effective risk and simulated results are identical. At USD 500 requested risk, effective risk rises to USD 474.45, pass probability falls to **64.16%**, challenge-to-payout falls to **40.62%**, and conditional funded hard-breach probability rises to **45.48%**. At USD 750, the corresponding figures deteriorate further.

The evaluation has no consistency rule under the current Growth evaluation guide. The funded payout stage applies 35% consistency, five winning days above USD 150, weekly activity, microscalping eligibility, payout caps and the 90% split. The Flash + Overnight Bias pair is the strongest currently eligible candidate found, but a **21.21% conditional funded hard-breach estimate is not low risk**.

## Recovery mode — accounts near the drawdown floor

Recovery probabilities below are balance-recovery estimates before breach. Tradeify's recovery simulation does **not** enforce funded 35% consistency, five winning days or payout processing; reaching USD 53,000 is a balance target, not an approved payout.

### FTMO

- With only **USD 100** remaining above the static loss floor, **no-trade** is the safest control. The tested active books have material breach probabilities at that cushion.
- At **USD 500** remaining cushion, Gold ORB (RBE) + Tokyo Coil at **USD 12.50 total book risk** has an **86.66%** chance of returning to break-even before breach, with **0%** simulated breach in 5,000 paths.
- At **USD 750** cushion, the same book has a **98.08%** break-even probability and 0% simulated breach.
- If avoiding MT5 RBE pairing uncertainty is more important, Tokyo Coil alone at USD 12.50 risk gives **84.66%** break-even probability and **0.60%** breach probability at USD 500 cushion.

### Tradeify

- With only **USD 200** remaining above the locked floor, **no-trade** is safest. One-micro active books have roughly 41–44% breach probability before reaching the USD 500 buffer.
- At **USD 1,500** cushion, one-micro Overnight Bias ORB alone has a **95.00%** chance of reaching the USD 53,000 balance target with **3.82%** breach probability, but it fails the weekly-activity check and is **not payout-eligible by itself**.
- Flash ORB + Overnight Bias ORB at one micro per sleeve has a **91.02%** chance of reaching the USD 53,000 balance target with **8.86%** breach probability. It passes the weekly-activity and microscalping checks, but the recovery simulation does not enforce the remaining payout rules.

Do not force trades simply to recover an account. When the remaining cushion is smaller than the risk imposed by minimum executable size, standing aside is the lowest-risk decision.

## Model scope and limitations

- Book selection uses a chronological **60% training / 40% validation** split. Risk units are calibrated on training data and held fixed in validation. This is one holdout, not a rolling multi-fold walk-forward test.
- Normalized live analysis screens all one-to-four-sleeve combinations. Prop Monte Carlo covers every single sleeve, selected category finalists and leading two-/three-sleeve candidates, including RBE-excluded FTMO sensitivities; it does not Monte Carlo every possible combination.
- Monte Carlo uses **5,000 paths**, a **252-trading-day** horizon and week-aligned Monday-Friday five-day block resampling. Results describe variability under the historical validation distribution; they do not remove regime-change or model uncertainty.
- Live-account 10R/20R/50R barriers are drawdown proxies in R units, not literal account-ruin probabilities because no live starting balance was specified.
- Prop-firm breach estimates use completed-trade daily PnL. FTMO equity-based limits can be breached by floating losses not visible in MT5 exports.
- Tradeify soft daily-loss behavior is approximated by clipping closed daily losses at USD 1,250. Intraday overshoot and exact pause timing are unknown; MAE stress is a separate daily diagnostic, not a synchronized intraday replay.
- Timestamps remain as exported; platform and firm timezone/session boundaries are not fully normalized. Margin, correlated-product hedging restrictions, broker-specific minimum lots, and slippage beyond source costs are not fully modeled.
- These are trade-export analyses, **not** a fresh tick-level or NQ minute-bar replay. The NQ minute archive has not yet been used for independent execution replication.
- No strategy entries, exits, native stops, targets or parameters were redesigned or optimized.

## Detailed outputs

- [Raw export metrics — NT8](../NT8/reports/strategy_metrics.csv)
- [Raw export metrics — MT5](../MT5/reports/strategy_metrics.csv)
- [Normalized live reports](../Normalized-Live/README.md)
- [NT8 all book combinations](../Normalized-Live/NT8/reports/all_book_combinations.csv)
- [MT5 all book combinations](../Normalized-Live/MT5/reports/all_book_combinations.csv)
- [FTMO Monte Carlo](../Prop-Firms/FTMO-10K-2Step-CFD/reports/monte_carlo_challenge_payout.csv)
- [FTMO recovery scenarios](../Prop-Firms/FTMO-10K-2Step-CFD/reports/recovery_mode.csv)
- [Tradeify Monte Carlo](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/monte_carlo_evaluation_funded_payout.csv)
- [Tradeify recovery scenarios](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/recovery_mode.csv)
- [Tradeify MAE / soft-DLL stress](../Prop-Firms/Tradeify-50K-Growth-Futures/reports/mae_soft_dll_stress.csv)
