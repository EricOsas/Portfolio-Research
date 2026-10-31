# NT8 strategy selection

Screening is a transparent evidence filter, not parameter optimization. Eligible strategies must have positive net PnL, daily PF > 1.00, at least 30 active days, at least 45% positive active months, and net PnL/max drawdown > 0.50. Candidates are ranked by daily Sharpe, daily PF, net-PnL/max-DD, positive-month share and sample size. Up to four are retained, excluding candidates with absolute daily-PnL correlation above 0.80 to an already selected strategy. Correlation requires 30 overlapping business days. The shortlist is provisional and is not a sizing instruction.

## Selected strategies

- **Overnight Bias ORB** — included in the provisional portfolio.
- **Sigma ORB** — included in the provisional portfolio.
- **Gold ORB (RBE)** — included in the provisional portfolio.
- **Vault Break** — included in the provisional portfolio.

## Eligible candidates (ranked)

| strategy                   |   screen_score |   total_net_pnl_usd |   daily_profit_factor |   daily_sharpe_252 |   max_drawdown_usd |   net_profit_to_max_drawdown |   positive_active_month_share |   active_days |
|:---------------------------|---------------:|--------------------:|----------------------:|-------------------:|-------------------:|-----------------------------:|------------------------------:|--------------:|
| Overnight Bias ORB         |       0.911111 |           267561    |               1.71229 |           1.88099  |           14851.6  |                    18.0157   |                      0.703704 |           606 |
| Sigma ORB                  |       0.888889 |           422052    |               1.528   |           1.79811  |           34422.5  |                    12.2609   |                      0.743902 |          1040 |
| Gold ORB (RBE)             |       0.666667 |            27789    |               1.48313 |           1.55498  |            3572.6  |                     7.77837  |                      0.655172 |           628 |
| Vault Break                |       0.622222 |           134530    |               1.43369 |           1.45083  |           11275    |                    11.9317   |                      0.604938 |           683 |
| Flash ORB                  |       0.577778 |           182897    |               1.27318 |           1.35518  |           15468    |                    11.8243   |                      0.695122 |          1207 |
| Open Drive                 |       0.455556 |           298131    |               1.27438 |           1.14133  |           45561.7  |                     6.54347  |                      0.609756 |          1760 |
| VWAP Pullback              |       0.427778 |            65920.5  |               1.29912 |           0.962463 |            9701.44 |                     6.79492  |                      0.621951 |           657 |
| Opening-Shock Continuation |       0.255556 |            55765    |               1.24054 |           0.798403 |           25000    |                     2.2306   |                      0.658537 |           481 |
| NQ Precision Bot           |       0.194444 |             7260.32 |               1.12676 |           0.318917 |           12627.6  |                     0.574955 |                      0.621951 |           688 |

## Interpretation limits

- PnL is the exported amount at original strategy-test size. No contract/lot scaling was applied.
- Curves start at USD 0 and show cumulative net PnL, not a capital-normalized account balance.
- The all-strategy curve assumes every strategy can run simultaneously; it does not model margin, overlap, portfolio risk limits or prop-firm rules.
- NT8 Profit already includes commission. MT5 deal cash flow uses Profit + Commission + Swap.
- MT5 entry commissions can be recognized on entry-deal dates; NT8 reports completed-trade PnL at exit.
- Export timestamps are not timezone-normalized. Do not treat cross-platform daily correlations as synchronized.
- This is a research shortlist, not a guarantee or position-sizing recommendation.
