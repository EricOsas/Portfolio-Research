# MT5 strategy selection

Screening is a transparent evidence filter, not parameter optimization. Eligible strategies must have positive net PnL, daily PF > 1.00, at least 30 active days, at least 45% positive active months, and net PnL/max drawdown > 0.50. Candidates are ranked by daily Sharpe, daily PF, net-PnL/max-DD, positive-month share and sample size. Up to four are retained, excluding candidates with absolute daily-PnL correlation above 0.80 to an already selected strategy. Correlation requires 30 overlapping business days. The shortlist is provisional and is not a sizing instruction.

## Selected strategies

- **Overnight Bias ORB** — included in the provisional portfolio.
- **Tokyo Coil** — included in the provisional portfolio.
- **Open Drive** — included in the provisional portfolio.
- **Flash ORB** — included in the provisional portfolio.

## Eligible candidates (ranked)

| strategy                   |   screen_score |   total_net_pnl_usd |   daily_profit_factor |   daily_sharpe_252 |   max_drawdown_usd |   net_profit_to_max_drawdown |   positive_active_month_share |   active_days |
|:---------------------------|---------------:|--------------------:|----------------------:|-------------------:|-------------------:|-----------------------------:|------------------------------:|--------------:|
| Overnight Bias ORB         |       0.916667 |           118213    |               1.58166 |           1.70472  |            8913.04 |                     13.2629  |                      0.731707 |           642 |
| Tokyo Coil                 |       0.827778 |           679864    |               1.49861 |           1.41837  |           81592.2  |                      8.33246 |                      0.731707 |           781 |
| Open Drive                 |       0.8      |           262357    |               1.32088 |           1.22232  |           30321.7  |                      8.65243 |                      0.658537 |          1753 |
| Flash ORB                  |       0.622222 |             9259.47 |               1.24746 |           1.21238  |            1123.31 |                      8.24302 |                      0.670732 |          1140 |
| Vault Break                |       0.544444 |            81245.1  |               1.31674 |           1.13497  |           11054.3  |                      7.34962 |                      0.609756 |           730 |
| Noise Band Momentum        |       0.527778 |           279244    |               1.27453 |           1.11945  |           50935.5  |                      5.48229 |                      0.682927 |          1063 |
| Opening-Shock Continuation |       0.316667 |            28792.3  |               1.20562 |           0.737741 |            9975.94 |                      2.88617 |                      0.609756 |           495 |
| NQ Precision Bot           |       0.233333 |             2124.95 |               1.13453 |           0.567737 |            1247.36 |                      1.70356 |                      0.573171 |           795 |
| Sigma ORB                  |       0.211111 |             9281.31 |               1.10322 |           0.545285 |            4010.45 |                      2.31428 |                      0.560976 |          1727 |

## Interpretation limits

- PnL is the exported amount at original strategy-test size. No contract/lot scaling was applied.
- Curves start at USD 0 and show cumulative net PnL, not a capital-normalized account balance.
- The all-strategy curve assumes every strategy can run simultaneously; it does not model margin, overlap, portfolio risk limits or prop-firm rules.
- NT8 Profit already includes commission. MT5 deal cash flow uses Profit + Commission + Swap.
- MT5 entry commissions can be recognized on entry-deal dates; NT8 reports completed-trade PnL at exit.
- Export timestamps are not timezone-normalized. Do not treat cross-platform daily correlations as synchronized.
- This is a research shortlist, not a guarantee or position-sizing recommendation.
