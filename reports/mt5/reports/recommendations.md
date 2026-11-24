# MT5 strategy selection

Screening is a transparent evidence filter, not parameter optimization. Eligible strategies must have positive net PnL, daily PF > 1.00, at least 30 active days, at least 45% positive active months, and net PnL/max drawdown > 0.50. Candidates are ranked by daily Sharpe, daily PF, net-PnL/max-DD, positive-month share and sample size. Up to four are retained, excluding candidates with absolute daily-PnL correlation above 0.80 to an already selected strategy. Correlation requires 30 overlapping business days. The shortlist is provisional and is not a sizing instruction.

## Selected strategies

- **Gold X9 (Very high)** — included in the provisional portfolio.
- **GotobiFix EURJPY** — included in the provisional portfolio.
- **GotobiFix USDJPY** — included in the provisional portfolio.
- **Gold ORB (RBE)** — included in the provisional portfolio.

## Eligible candidates (ranked)

| strategy                   |   screen_score |   total_net_pnl_usd |   daily_profit_factor |   daily_sharpe_252 |   max_drawdown_usd |   net_profit_to_max_drawdown |   positive_active_month_share |   active_days |
|:---------------------------|---------------:|--------------------:|----------------------:|-------------------:|-------------------:|-----------------------------:|------------------------------:|--------------:|
| Gold X9 (Very high)        |       0.886842 |         8.51095e+07 |               2.63602 |           2.46906  |        5.19297e+06 |                     16.3894  |                      0.743902 |          1632 |
| Gold X9 (Moderate)         |       0.826316 |         6.94357e+07 |               2.88901 |           2.44214  |        4.93871e+06 |                     14.0595  |                      0.743902 |           878 |
| Gold X9 (Low)              |       0.818421 |         4.18446e+07 |               3.3199  |           2.22288  |        1.684e+06   |                     24.8483  |                      0.743902 |           812 |
| Gold X9 (High)             |       0.813158 |         8.04753e+07 |               2.76815 |           2.42022  |        5.26689e+06 |                     15.2795  |                      0.731707 |           908 |
| GotobiFix EURJPY           |       0.794737 |     34351.7         |               2.32004 |           2.35894  |     1244.74        |                     27.5975  |                      0.841463 |           488 |
| Gold X9 (Extremely low)    |       0.713158 |         1.36816e+07 |               4.68409 |           1.58954  |   634022           |                     21.579   |                      0.759494 |           232 |
| GotobiFix USDJPY           |       0.692105 |     31498.1         |               2.18543 |           2.26585  |     2076.47        |                     15.1691  |                      0.743902 |           488 |
| GotobiFix GBPJPY           |       0.602632 |     33367.1         |               1.88975 |           1.83098  |     2274.32        |                     14.6712  |                      0.719512 |           488 |
| Gold ORB (RBE)             |       0.573684 |    205923           |               1.55424 |           1.82549  |    15255.3         |                     13.4984  |                      0.703704 |           861 |
| Overnight Bias ORB         |       0.547368 |    118213           |               1.58166 |           1.70472  |     8913.04        |                     13.2629  |                      0.731707 |           642 |
| Tokyo Coil                 |       0.463158 |    679864           |               1.49861 |           1.41837  |    81592.2         |                      8.33246 |                      0.731707 |           781 |
| Open Drive                 |       0.444737 |    262357           |               1.32088 |           1.22232  |    30321.7         |                      8.65243 |                      0.658537 |          1753 |
| FVG Duo                    |       0.442105 |    154356           |               1.31219 |           1.26796  |    15530.8         |                      9.93869 |                      0.674699 |          1191 |
| Flash ORB                  |       0.336842 |      9259.47        |               1.24746 |           1.21238  |     1123.31        |                      8.24302 |                      0.670732 |          1140 |
| Noise Band Momentum        |       0.297368 |    279244           |               1.27453 |           1.11945  |    50935.5         |                      5.48229 |                      0.682927 |          1063 |
| Vault Break                |       0.292105 |     81245.1         |               1.31674 |           1.13497  |    11054.3         |                      7.34962 |                      0.609756 |           730 |
| Opening-Shock Continuation |       0.171053 |     28792.3         |               1.20562 |           0.737741 |     9975.94        |                      2.88617 |                      0.609756 |           495 |
| Sigma ORB                  |       0.152632 |      9281.31        |               1.10322 |           0.545285 |     4010.45        |                      2.31428 |                      0.560976 |          1727 |
| NQ Precision Bot           |       0.131579 |      2124.95        |               1.13453 |           0.567737 |     1247.36        |                      1.70356 |                      0.573171 |           795 |

## Interpretation limits

- PnL is the exported amount at original strategy-test size. No contract/lot scaling was applied.
- Curves start at USD 0 and show cumulative net PnL, not a capital-normalized account balance.
- The all-strategy curve assumes every strategy can run simultaneously; it does not model margin, overlap, portfolio risk limits or prop-firm rules.
- NT8 Profit already includes commission. MT5 deal cash flow uses Profit + Commission + Swap.
- MT5 entry commissions can be recognized on entry-deal dates; NT8 reports completed-trade PnL at exit.
- Export timestamps are not timezone-normalized. Do not treat cross-platform daily correlations as synchronized.
- This is a research shortlist, not a guarantee or position-sizing recommendation.
