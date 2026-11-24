# Normalized live-account research

This directory removes the exported starting balances and normalizes strategy exposure.

- NT8: one contract equivalent per strategy. Trade PnL is divided by exported quantity.
- MT5: fixed $100 risk per trade. Every trade's cash flow is divided by its traded volume first, so 1R is a per-lot realized-loss proxy rather than a balance-scaled dollar amount. That keeps compounding tester runs (Gold X9 grows from ~0.09 to 50+ lots) comparable with fixed-size runs. The export does not provide a complete per-trade initial-stop risk series, so this is explicitly a realized-loss proxy.
- Equity starts at $0. No account balance is added.
- The strategy's native exits and stop behavior are preserved. No protective stops or strategy redesign are introduced.

Each platform has individual strategy curves, all-sleeve curves, category-book curves, normalized trade ledgers, risk-unit correlations, and bootstrap drawdown/ruin estimates. The live book categories are screening candidates, not deployment approval.

## Platform reports

- [NT8 normalized live](NT8/README.md)
- [MT5 normalized live](MT5/README.md)

## Charts

See the platform READMEs for the equity curves at the end of each report.
