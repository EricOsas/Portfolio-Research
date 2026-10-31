# MT5 research pack

**9 of 9 available exports parsed**

Gold X9 and Gold ORB (RBE) remain pending exports. VWAP Pullback is NT8-specific.

## Snapshot

| Portfolio | Net PnL | Max drawdown | Daily PF | Daily Sharpe |
|---|---:|---:|---:|---:|
| All 9 available exports | $1,470,380.01 | $94,936.84 | 1.57 | 2.23 |
| Core 4 shortlist | $1,069,692.84 | $65,338.78 | 1.57 | 2.01 |

## Core shortlist

- Overnight Bias ORB
- Tokyo Coil
- Open Drive
- Flash ORB

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

Standard MT5 Strategy Tester reports use deal Profit + Commission + Swap; all 8 reconcile to final balance less initial deposit. NQ Precision Bot uses the custom completed-trade ledger and Adj. Net P&L, which reconciles to the report summary. Tokyo Coil uses USDJPY; the other eight exports use USTEC. Timestamps are retained as exported broker/server time.

## Equity curves

### Individual-strategy dashboard

![MT5 strategy dashboard](charts/individual/strategy_dashboard.png)

### All available strategies combined

![All MT5 strategies](charts/portfolios/all_strategies.png)

### Core shortlist

![MT5 recommended strategies](charts/portfolios/recommended_strategies.png)

### Individual curves

- [Tokyo Coil](charts/individual/tokyo-coil.png)
- [Vault Break](charts/individual/vault-break.png)
- [Overnight Bias ORB](charts/individual/overnight-bias-orb.png)
- [Open Drive](charts/individual/open-drive.png)
- [NQ Precision Bot](charts/individual/nq-precision-bot.png)
- [Opening-Shock Continuation](charts/individual/opening-shock-continuation.png)
- [Sigma ORB](charts/individual/sigma-orb.png)
- [Flash ORB](charts/individual/flash-orb.png)
- [Noise Band Momentum](charts/individual/noise-band-momentum.png)
