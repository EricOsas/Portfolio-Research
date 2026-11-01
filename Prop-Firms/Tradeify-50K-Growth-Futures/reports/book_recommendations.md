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
No weekly-eligible active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $200 cushion. No-trade preserves the floor but is not a compliant long-term mode because weekly activity is required. Best recovery chance: Open Drive + VWAP Pullback at USD 158.36 risk (59.3% recovery; 40.7% breach). Lowest-breach active choice: Open Drive + VWAP Pullback at USD 158.36 risk (59.3% recovery; 40.7% breach). Lowest-exposure active choice: Open Drive at USD 98.82 risk (58.2% recovery; 41.8% breach).

Recovery outputs are balance-only. The $53,000 target is a balance threshold, not an approved payout; 35% consistency, five $150 winning days and payout processing are not enforced in the recovery path.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.