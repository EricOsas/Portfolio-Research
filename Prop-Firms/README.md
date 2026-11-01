# Prop-firm portfolio simulations

Separate account-rule simulations using normalized strategy R-multiples and 5,000-path, five-day block-bootstrap Monte Carlo over a 252-trading-day horizon.

## Account books

| Account | Challenge / funded book | Base sizing | Key one-year result |
|---|---|---:|---|
| [FTMO $10,000 2-Step CFD](FTMO-10K-2Step-CFD/README.md) | Gold ORB (RBE) + Open Drive + Overnight Bias ORB + Tokyo Coil | $50 total risk per book trade | 96.46% pass-both; 94.64% challenge-to-first-reward; 0.54% evaluation breach; 0.31% funded breach conditional on funding |
| [Tradeify $50,000 Growth futures](Tradeify-50K-Growth-Futures/README.md) | Flash ORB + Overnight Bias ORB | $100 requested; $237.23 effective after one-micro minimums | 84.30% eligible evaluation pass; 61.56% challenge-to-first-payout; 21.21% funded hard breach conditional on funding |

## Recovery

- At the tested near-floor cushions ($100 above FTMO's static floor; $200 above Tradeify's locked floor), no active book meets both a 50% recovery probability and a 5% breach-risk ceiling.
- Tradeify's minimum executable micro size makes active recovery especially difficult. No-trade preserves the floor but does not satisfy long-term weekly activity.
- Recovery CSVs compare all positive-training single sleeves and pairs. They are balance-recovery simulations, not payout approvals.

## Method and limits

Results are conditional on historical export distributions and the assumptions in each account folder. The MT5 Gold ORB (RBE) pairing fallback retains trade-level timing uncertainty. FTMO uses a closed-PnL model despite equity-based loss limits; Tradeify uses a closed-PnL approximation of its soft daily-loss limit. These are not guarantees of passing, funding, payout or survival.

See [full methodology](methodology.md) and [strategy/book suitability report](../reports/strategy_suitability.md).
