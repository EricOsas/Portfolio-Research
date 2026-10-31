# MT5 research pack

## Charts

- charts/individual/: one equity curve per parsed strategy, plus a multi-strategy dashboard.
- charts/portfolios/all_strategies.png: all MT5 exports combined.
- charts/portfolios/recommended_strategies.png: evidence-screened shortlist.

## Reports

- reports/strategy_metrics.csv
- reports/portfolio_metrics.csv
- reports/daily_pnl.csv
- reports/correlation_matrix.csv
- reports/annual_pnl.csv
- reports/normalized_event_ledger.csv
- reports/strategy_manifest.csv
- reports/data_quality.json
- reports/recommendations.md
- reports/summary.json

MT5 source is MetaTrader 5 Strategy Tester XLSX. Deal cash flow is Profit + Commission + Swap. Entry and exit commissions remain on their exported deal timestamps. Server timestamps are retained without conversion.

Gold X9 and Gold ORB (RBE) are pending MT5 exports. VWAP Pullback is NT8-specific.
