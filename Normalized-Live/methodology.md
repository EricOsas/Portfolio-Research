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
- One R is the mean absolute realized losing-trade PnL measured on the first 60% training period.
- The training-period R unit is held fixed and applied to the later validation period.
- Each completed trade is scaled as `normalized PnL = trade R × USD 100`.
- The full-sample loss estimate is retained separately for comparison, not used for validation sizing.
- The R unit is based on realized losses, not verified initial stop distance. It is a sizing proxy.

## Equity and book construction

- Curves start at USD 0. No starting balance or account capital is added.
- Individual sleeves and all one-to-four-sleeve combinations are measured.
- Portfolio PnL is the sum of the normalized sleeve PnLs. It does not assume that every strategy can always be executed simultaneously.
- Strategy book selection uses one chronological 60% training / 40% validation split. Each sleeve's R unit is calibrated on the training segment and held fixed for validation.
- This is a single holdout, not a multi-fold rolling walk-forward test; it is a screening stage, not final robustness certification.
- In `all_book_combinations.csv`, train/validation R metrics are the average constituent-sleeve R (`sum of sleeve R / number of sleeves`) so books of different sizes can be ranked comparably.
- Category book rankings are screening candidates; they are not optimized live portfolios.

## Category book selection

All one-to-four-sleeve combinations are scored using the training segment only. The top three combinations in each category are retained if training net R is positive and the book has at least 30 active days.

- **Live:** 35% training Sharpe, 25% daily profit factor, 20% positive-month share, 20% lower maximum drawdown.
- **Challenge:** 35% net-R-to-drawdown, 30% Sharpe, 20% net R, 15% active days.
- **Funded:** 30% Sharpe, 25% positive-month share, 20% less severe worst day, 15% lower best-day concentration, 10% profit factor.
- **Recovery:** 35% Sharpe, 25% lower maximum drawdown, 25% less severe worst day, 15% net R.

These are generic screening scores. They do not replace the FTMO- or Tradeify-specific pass, payout, consistency, and breach simulations.

## Bootstrap risk analysis

- 5,000 paths.
- 5-trading-day circular block bootstrap.
- 252-trading-day horizon.
- The bootstrap resamples validation daily PnL blocks to retain short-run clustering.
- The live drawdown-risk report bootstraps the average constituent-sleeve R series for each book and measures the probability of maximum drawdown reaching 10R, 20R and 50R barriers. These are balance-free drawdown proxies, not literal account ruin probabilities.

## Data handling

- Completed-trade PnL is placed on exit date; trade activity is counted on entry date.
- Timestamps are retained as exported. No timezone conversion is assumed.
- NT8 Profit is already net of Commission.
- MT5 standard reports use deal Profit + Commission + Swap.
- MT5 RBE has no position IDs. Matching uses symbol, side and exact volume where possible, with FIFO fallback. Its cashflows reconcile, but duration and trade-level risk pairing retain uncertainty.

## Limits

- These are trade-export analyses, not tick-level replay or a new NQ minute-bar backtest.
- The realized-loss R unit is not the strategy's initial stop risk. NT8 one-contract equity curves remain in exported contract dollars; their bootstrap R analysis is separately normalized by each sleeve's training-period loss proxy.
- Margin, slippage beyond exported costs, broker minimum lot sizes, execution conflicts, and simultaneous exposure are not fully modeled.
- No strategy entries, exits, stops, targets, or parameters were changed.
