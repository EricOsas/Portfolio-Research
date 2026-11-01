# Tradeify $50k Growth futures — book ranking

Base comparison risk: USD 100 requested total risk per book trade.

Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.

## Challenge candidate
- **challenge_book_1** (Flash ORB + Gold ORB (RBE) + Sigma ORB + Vault Break)
  - Challenge-to-payout: 51.9%
  - Pass rate: 71.1%
  - Evaluation hard-breach rate: 28.9%
  - Funded hard-breach rate (conditional on funding): 39.5%
  - Effective risk after minimum-micro sizing: USD 457.35
  - Median trading days to eligible evaluation pass: 24.0
  - Median trading days to first payout: 63.0

## Holdout validation leader (diagnostic only)
- **Flash ORB + NQ Precision Bot + Overnight Bias ORB + VWAP Pullback** (Flash ORB + NQ Precision Bot + Overnight Bias ORB + VWAP Pullback)
  - Challenge-to-payout: 68.2%
  - Pass rate: 85.5%
  - Evaluation hard-breach rate: 14.4%

## Funded candidate
- **funded_book_1** (Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB)
  - Conditional first-payout rate: 74.2%
  - Funded hard-breach rate (conditional on funding): 37.5%
  - Effective risk after minimum-micro sizing: USD 472.83
  - Approximate 90-trading-day funded survival: 68.2%
  - Median first net payout on successful paths: USD 1,350.00
  - Expected first net payout across all paths: USD 706.05
  - Expected total net payout cash across all paths: USD 4,200.03
  - Mean payout count over the horizon: 2.04
  - Median trading days to first payout: 68.0

## Near-floor recovery
No weekly-eligible active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $200 cushion. No-trade preserves the floor but is not a compliant long-term mode because weekly activity is required. Best recovery chance: Open Drive + VWAP Pullback at USD 158.36 risk (59.3% recovery; 40.7% breach). Lowest-breach active choice: Open Drive + VWAP Pullback at USD 158.36 risk (59.3% recovery; 40.7% breach). Lowest-exposure active choice: Open Drive at USD 98.82 risk (58.2% recovery; 41.8% breach).

Recovery outputs are balance-only. The $53,000 target is a balance threshold, not an approved payout; 35% consistency, five $150 winning days and payout processing are not enforced in the recovery path.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.