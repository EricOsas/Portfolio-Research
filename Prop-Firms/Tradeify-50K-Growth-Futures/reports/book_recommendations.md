# Tradeify $50k Growth futures — book ranking

Base comparison risk: USD 100 requested total risk per book trade.

## Challenge candidate
- **funded_score_2sleeve_candidate_1** (Flash ORB + Overnight Bias ORB)
  - Challenge-to-payout: 61.6%
  - Pass rate: 84.3%
  - Evaluation hard-breach rate: 15.1%
  - Funded hard-breach rate (conditional on funding): 21.2%
  - Effective risk after minimum-micro sizing: USD 237.23
  - Median trading days to eligible evaluation pass: 76.0
  - Median trading days to first payout: 163.0

## Funded candidate
- **funded_score_2sleeve_candidate_1** (Flash ORB + Overnight Bias ORB)
  - Conditional first-payout rate: 73.0%
  - Funded hard-breach rate (conditional on funding): 21.2%
  - Effective risk after minimum-micro sizing: USD 237.23
  - Approximate 90-trading-day funded survival: 89.3%
  - Median first net payout on successful paths: USD 1,350.00
  - Expected first net payout across all paths: USD 831.06
  - Expected total net payout cash across all paths: USD 2,000.40
  - Mean payout count over the horizon: 1.20
  - Median trading days to first payout: 163.0

## Near-floor recovery
No-trade is the mathematical drawdown control, but it is not a compliant long-term Tradeify mode because minimum weekly activity applies; none of the weekly-eligible active candidates stayed within a 5% modeled breach probability.

Recovery outputs are balance-only; the Tradeify $53,000 target does not enforce payout consistency, five $150 winning days or payout processing.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.