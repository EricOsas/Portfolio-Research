# Normalized live-account research

This directory removes the exported starting balances and normalizes strategy exposure.

- NT8: one contract equivalent per strategy. Trade PnL is divided by exported quantity.
- MT5: fixed $100 risk per trade. 1R is proxied by each strategy's mean absolute realized losing-trade PnL. The export does not provide a complete per-trade initial-stop risk series, so this is explicitly a realized-loss proxy.
- Equity starts at $0. No account balance is added.
- The strategy's native exits and stop behavior are preserved. No protective stops or strategy redesign are introduced.

Each platform has individual strategy curves, all-sleeve curves, category-book curves, normalized trade ledgers, risk-unit correlations, and bootstrap drawdown/ruin estimates. The live book categories are screening candidates, not deployment approval.

## Methodology

- [Normalization, book scoring and bootstrap methodology](methodology.md)

## Platform reports

- [NT8 normalized live](NT8/README.md)
- [MT5 normalized live](MT5/README.md)

## Charts

See the platform READMEs for the equity curves at the end of each report.
