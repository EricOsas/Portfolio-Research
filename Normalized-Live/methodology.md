# Normalized live-account methodology

## Purpose

Compare strategy sleeves and books on a common, balance-free equity basis for ordinary live accounts. These curves are separate from the raw export curves and from prop-firm simulations.

## Sizing

### NT8

- One exported contract equivalent per strategy.
- PnL is divided by exported quantity before building the one-contract curve.
- The refreshed Gold ORB (RBE) export identifies GC DEC26; the other NT8 exports identify NQ.
- One GC contract and one NQ contract are not equal-risk exposures. The curve preserves each instrument's contract economics rather than forcing equal dollar risk.

### MT5

- Fixed USD 100 risk proxy per completed trade.
- One R is the mean absolute realized losing-trade PnL for that strategy.
- Each completed trade is scaled as `normalized PnL = trade R × USD 100`.
- The R unit is based on realized losses, not verified initial stop distance. It is a sizing proxy.

## Equity and book construction

- Curves start at USD 0. No starting balance or account capital is added.
- Individual sleeves and all one-to-four-sleeve combinations are measured.
- Portfolio PnL is the sum of the normalized sleeve PnLs. It does not assume that every strategy can always be executed simultaneously.
- Strategy book selection uses a chronological 60% training / 40% validation split. The combination file reports both periods.
- Category book rankings are screening candidates; they are not optimized live portfolios.

## Bootstrap risk analysis

- 5,000 paths.
- 5-trading-day circular block bootstrap.
- 252-trading-day horizon.
- The bootstrap resamples validation daily PnL blocks to retain short-run clustering.
- The live drawdown-risk report measures the probability of maximum drawdown reaching 10R, 20R and 50R barriers. These are balance-free drawdown proxies, not literal account ruin probabilities.

## Data handling

- Completed-trade PnL is placed on exit date; trade activity is counted on entry date.
- Timestamps are retained as exported. No timezone conversion is assumed.
- NT8 Profit is already net of Commission.
- MT5 standard reports use deal Profit + Commission + Swap.
- MT5 RBE has no position IDs. Matching uses symbol, side and exact volume where possible, with FIFO fallback. Its cashflows reconcile, but duration and trade-level risk pairing retain uncertainty.

## Limits

- These are trade-export analyses, not tick-level replay or a new NQ minute-bar backtest.
- The realized-loss R unit is not the strategy's initial stop risk.
- Margin, slippage beyond exported costs, broker minimum lot sizes, execution conflicts, and simultaneous exposure are not fully modeled.
- No strategy entries, exits, stops, targets, or parameters were changed.
