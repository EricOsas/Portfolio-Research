# NT8 research pack

## Charts

- charts/individual/: one equity curve per parsed strategy, plus a multi-strategy dashboard.
- charts/portfolios/all_strategies.png: all NT8 exports combined.
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

NT8 source is NinjaTrader Strategy Analyzer CSV. The Profit field is net of the exported Commission; do not subtract commission again. Curves use exported contract quantity and USD PnL. Timestamps are retained as exported.
