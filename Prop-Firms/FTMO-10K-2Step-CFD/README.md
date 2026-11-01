# FTMO $10,000 2-Step CFD

See [account rules](reports/account_rules.json), Monte Carlo results in [reports/monte_carlo_challenge_payout.csv](reports/monte_carlo_challenge_payout.csv), and [recovery-mode scenarios](reports/recovery_mode.csv).

The model uses normalized daily R-multiples, equal risk allocation across the sleeves in each book, and a 5-trading-day circular block bootstrap. Each simulation uses 5,000 paths over 252 trading days.

## Important limits

- The source exports are closed-trade records, not a complete tick-by-tick account equity path.
- Daily rules are approximated from closed PnL. Floating losses can breach equity limits before a trade closes.
- MT5 standard Deals exports lack position IDs; entry/exit legs are paired FIFO.
- Timestamps remain as exported. The firm's timezone/session boundaries are not reconstructed.
- Strategy execution, native exits and stop behavior are not changed.
- Treat results as historical scenario estimates, not promises.

## Charts

Charts and book comparisons will be listed here after the simulation build.
