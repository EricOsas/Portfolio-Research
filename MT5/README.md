# MT5 research pack

**19 of 19 registered exports parsed.**

## Snapshot

| Portfolio | Net PnL | Max drawdown | Daily PF | Daily Sharpe |
|---|---:|---:|---:|---:|
| All 19 exports | $292,476,593.33 | $16,661,015.76 | 2.90 | 2.50 |
| Core 4 shortlist | $85,381,229.66 | $5,194,033.52 | 2.64 | 2.48 |

## Core shortlist

- Gold X9 (Very high)
- GotobiFix EURJPY
- GotobiFix USDJPY
- Gold ORB (RBE)

## Reports

- [Strategy metrics](reports/strategy_metrics.csv)
- [Portfolio metrics](reports/portfolio_metrics.csv)
- [Daily PnL](reports/daily_pnl.csv)
- [Daily PnL correlation matrix](reports/correlation_matrix.csv)
- [Annual PnL](reports/annual_pnl.csv)
- [Normalized event ledger](reports/normalized_event_ledger.csv)
- [Strategy manifest](reports/strategy_manifest.csv)
- [Data-quality checks](reports/data_quality.json)
- [Selection rationale](reports/recommendations.md)
- [Build summary](reports/summary.json)

MT5 standard reports use deal `Profit + Commission + Swap`; custom completed-trade ledgers use their adjusted net PnL. Timestamps are retained as exported broker/server time.

Instrument coverage: EURJPY; GBPJPY; USDJPY; USTEC; XAUUSD.

### Position sizing over time

These exports size from account balance rather than a fixed lot/contract. Their raw dollar curve is a compounding tester run at the reported initial deposit, not a fixed-size strategy comparison; the normalized live and prop-firm layers divide cash flow by traded volume to remove that effect.

| Strategy | Mean size, first year | Mean size, last year |
|---|---:|---:|
| Gold X9 (Extremely low) | 3.99 | 83.81 |
| Gold X9 (Low) | 2.29 | 99.20 |
| Gold X9 (Moderate) | 1.38 | 99.49 |
| Gold X9 (High) | 1.09 | 99.74 |
| Gold X9 (Very high) | 0.46 | 52.40 |
| Tokyo Coil | 9.41 | 38.40 |

## Equity curves

### Individual-strategy dashboard

![MT5 strategy dashboard](charts/individual/strategy_dashboard.png)

### All strategies combined

![All MT5 strategies](charts/portfolios/all_strategies.png)

### Core shortlist

![MT5 recommended strategies](charts/portfolios/recommended_strategies.png)

### Individual curves

- [Gold X9 (Extremely low)](charts/individual/gold-x9-extremely-low.png)
- [Gold X9 (Low)](charts/individual/gold-x9-low.png)
- [Gold X9 (Moderate)](charts/individual/gold-x9-moderate.png)
- [Gold X9 (High)](charts/individual/gold-x9-high.png)
- [Gold X9 (Very high)](charts/individual/gold-x9-very-high.png)
- [Gold ORB (RBE)](charts/individual/gold-orb-rbe.png)
- [Tokyo Coil](charts/individual/tokyo-coil.png)
- [Vault Break](charts/individual/vault-break.png)
- [Overnight Bias ORB](charts/individual/overnight-bias-orb.png)
- [Open Drive](charts/individual/open-drive.png)
- [NQ Precision Bot](charts/individual/nq-precision-bot.png)
- [Opening-Shock Continuation](charts/individual/opening-shock-continuation.png)
- [Sigma ORB](charts/individual/sigma-orb.png)
- [Flash ORB](charts/individual/flash-orb.png)
- [Noise Band Momentum](charts/individual/noise-band-momentum.png)
- [FVG Duo](charts/individual/fvg-duo.png)
- [GotobiFix EURJPY](charts/individual/gotobifix-eurjpy.png)
- [GotobiFix GBPJPY](charts/individual/gotobifix-gbpjpy.png)
- [GotobiFix USDJPY](charts/individual/gotobifix-usdjpy.png)
