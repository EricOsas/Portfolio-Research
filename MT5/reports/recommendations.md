# MT5 strategy selection

No parsed strategies.

## Selected strategies

- None. No strategy passed the evidence screen; do not treat the all-strategy curve as a deployment recommendation.

## Eligible candidates (ranked)

No eligible candidates.

## Interpretation limits

- PnL is the exported amount at original strategy-test size. No contract/lot scaling was applied.
- Curves start at USD 0 and show cumulative net PnL, not a capital-normalized account balance.
- The all-strategy curve assumes every strategy can run simultaneously; it does not model margin, overlap, portfolio risk limits or prop-firm rules.
- NT8 Profit already includes commission. MT5 deal cash flow uses Profit + Commission + Swap.
- MT5 entry commissions can be recognized on entry-deal dates; NT8 reports completed-trade PnL at exit.
- Export timestamps are not timezone-normalized. Do not treat cross-platform daily correlations as synchronized.
- This is a research shortlist, not a guarantee or position-sizing recommendation.
