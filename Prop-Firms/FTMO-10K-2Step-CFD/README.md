# FTMO $10,000 2-Step CFD

- [Account rules and assumptions](reports/account_rules.json)
- [Monte Carlo results](reports/monte_carlo_challenge_payout.csv)
- [Methodology](../methodology.md)
- [Book rankings](reports/book_rankings.csv)
- [Book recommendations](reports/book_recommendations.md)
- [Recovery-mode scenarios](reports/recovery_mode.csv)

The model uses normalized daily R-multiples and a 5-trading-day circular block bootstrap. Each simulation uses 5,000 paths over 252 trading days. Risk ladder is USD 25–100 total book risk per trade, allocated equally across sleeves. Sizing is continuous; instrument-specific minimum lots are not enforced.

## Important limits

- The source exports are closed-trade records, not a complete tick-by-tick account equity path.
- FTMO equity-based daily and maximum loss limits can be breached by floating losses not visible in closed-trade exports.
- MT5 RBE entry/exit legs use exact-volume matching where possible and FIFO fallback because the Deals export has no position IDs.
- Timestamps remain as exported. The firm's timezone/session boundaries are not reconstructed.
- Strategy execution, native exits and stop behavior are not changed.
- Treat results as historical scenario estimates, not promises.

## Charts

![Challenge-to-payout probability](charts/challenge_to_payout_probability.png)

![Drawdown breach probability](charts/drawdown_breach_probability.png)

![Recovery probability](charts/recovery_probability.png)


