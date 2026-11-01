# Strategy and book suitability

## How to interpret the categories

- **Live book:** prioritize sustainable expectancy, drawdown control and repeatability without a prop firm's payout constraints.
- **Challenge book:** prioritize the probability of reaching the evaluation target before breaching the firm's loss limits. A challenge book can tolerate more variance than a funded book, but not uncontrolled risk.
- **Funded book:** prioritize payout eligibility and account survival. Consistency, weekly activity, microscalping and payout thresholds matter as much as raw expectancy.
- **Recovery mode:** prioritize not breaching the remaining drawdown cushion. If the minimum tradable size is too large relative to the cushion, no-trade is the correct control.

A strategy is not inherently a “challenge strategy” or “funded strategy.” Its suitability depends on the account rules, position minimums, risk budget, and the other sleeves in the book.

## Live-account candidates

### NT8

**Live book 1:** Opening-Shock Continuation + Overnight Bias ORB + Sigma ORB + Vault Break.

- One contract equivalent per sleeve.
- Full-sample normalized net PnL: approximately USD 875,185.
- Full-sample maximum drawdown: approximately USD 32,604.
- Daily PF: 1.63; daily Sharpe: 2.43.
- Validation: 69.13R net, 1.61 PF, 2.44 Sharpe, 5.05R max drawdown.

This is a research candidate, not a small-account sizing recommendation. It includes Sigma ORB, whose baseline intentionally has no protective stop; its account-level MAE should be monitored.

### MT5

**Live book 1:** Flash ORB + Gold ORB (RBE) + Tokyo Coil + Vault Break.

- USD 100 realized-loss risk proxy per trade per sleeve.
- Full-sample normalized net PnL: approximately USD 72,955.
- Full-sample maximum drawdown: approximately USD 2,304.
- Daily PF: 1.63; daily Sharpe: 2.62.
- Validation: 99.22R net, 1.72 PF, 3.00 Sharpe, 5.76R max drawdown.

The MT5 RBE export has residual entry/exit pairing uncertainty because it has no position IDs.

## FTMO USD 10k 2-Step CFD

**Challenge candidate:** Gold ORB (RBE) + Open Drive + Overnight Bias ORB + Tokyo Coil.

- At USD 75 total book risk per trade: 97.88% simulated phase-pass rate, 97.22% challenge-to-first-reward rate, and 1.20% maximum-loss breach rate over the 252-trading-day horizon.
- At USD 50 total book risk per trade: 93.70% phase-pass rate, 91.48% challenge-to-first-reward rate, and 0.06% maximum-loss breach rate.

**Funded candidate:** same four-sleeve book at USD 50 total book risk. Conditional first-reward rate is 97.63%; modeled maximum-loss breach rate is 0.06%. Median first reward is approximately USD 101 net after the 80% split. This counts a qualifying first reward, not a large payout target.

**Recovery:** near the floor with only USD 100 remaining cushion, no-trade is the safest control. At USD 500 cushion, a single Gold ORB (RBE) sleeve at USD 12.50 risk has a 76.92% simulated chance of returning to initial equity with 0.04% breach probability. At USD 750 cushion, the return probability rises to 95.92%.

## Tradeify USD 50k Growth futures

**Challenge and funded candidate:** Flash ORB + Overnight Bias ORB.

At USD 500 requested total book risk per trade:

- Effective risk after minimum-micro sizing: approximately USD 266.16.
- Position size: one micro per sleeve, 0.2 mini-equivalent total.
- Evaluation pass rate: 84.62%.
- Challenge-to-first-payout rate: 62.68%.
- Conditional first-payout rate after funding: 74.07%.
- Conditional funded hard-breach rate: 20.26%.
- Approximate 90-day funded survival: 90.02%.
- Median first payout on successful paths: USD 1,350 net.
- Mean total net payout cash across all paths: approximately USD 2,131 over the one-year horizon.

The 35% evaluation-consistency stress case produced the same rounded results for this pair. The book also passed the modeled weekly-activity and microscalping eligibility screens.

Its one-micro-per-sleeve MAE diagnostic has approximately USD 458 p95 daily stacked MAE and USD 790 maximum daily stacked MAE, below the USD 1,250 daily-loss threshold in this historical sample. This is a conservative daily stack, not a synchronized intraday replay.

The four-sleeve books had higher total risk and weaker funded survival. The two-sleeve Flash + Overnight Bias book is the better current Tradeify candidate.

**Recovery:** with only USD 200 remaining cushion above the locked floor, no-trade is the safest control. A single Overnight Bias ORB micro is not gentle enough at that cushion: its simulated probability of reaching the USD 500 buffer is 56.92%, but its breach probability is 43.08%. With USD 1,500 cushion, the same one-micro sleeve has a 95.90% chance of reaching the USD 53,000 payout balance with 2.94% breach probability.

## Practical sorting

| Account use | Current candidate | Main reason | Main caution |
|---|---|---|---|
| NT8 live | Opening-Shock + OBRB + Sigma + Vault | Strong normalized validation metrics | One full contract per sleeve; Sigma has no native protective stop |
| MT5 live | Flash + RBE + Tokyo Coil + Vault | Strong normalized validation metrics | USD 100 risk is a realized-loss proxy; RBE pairing caveat |
| FTMO challenge | RBE + Open Drive + OBRB + Tokyo Coil | High simulated pass and first-reward probability | Closed-PnL model; news and floating-loss rules not reconstructed |
| FTMO funded | Same book, lower USD 50 total risk | High conditional reward probability and low modeled breach | First reward amount is modest; continuous lot sizing |
| Tradeify challenge/funded | Flash ORB + OBRB | Best eligible two-sleeve payout/survival balance found | 20.26% conditional funded hard-breach estimate over one year |
| Near-floor recovery | No-trade until cushion improves | Minimum size is too large relative to the remaining cushion | Trading to recover can turn a recoverable account into a breach |

## Decision rule

Do not increase size simply because a strategy has high historical net PnL. Select the book against the account's rules, model minimum executable size, and compare pass probability, payout probability, funded breach risk, and recovery probability together. The prop simulations are historical scenario estimates, not promises.
