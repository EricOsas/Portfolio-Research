# FTMO $10k 2-Step CFD — book ranking

Base comparison risk: USD 50 requested total risk per book trade.

## Challenge candidate
- **challenge_book_3** (Gold ORB (RBE) + Open Drive + Overnight Bias ORB + Tokyo Coil)
  - Challenge-to-payout: 94.6%
  - Pass rate: 96.5%
  - Evaluation hard-breach rate: 0.5%
  - Funded hard-breach rate (conditional on funding): 0.3%
  - Median trading days to Phase 1 pass: 66.0
  - Median trading days to Verification pass: 105.0
  - Median trading days to first FTMO reward: 124.0
  - Expected first FTMO reward across all paths: USD 167.70
  - Median FTMO reward on successful paths: USD 128.53

## Funded candidate
- **challenge_book_3** (Gold ORB (RBE) + Open Drive + Overnight Bias ORB + Tokyo Coil)
  - Conditional first-payout rate: 98.1%
  - Funded hard-breach rate (conditional on funding): 0.3%
  - Median trading days to first FTMO reward: 124.0

## Near-floor recovery
No active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $100 cushion. No-trade preserves the account but cannot recover it to initial balance. Best recovery chance: Gold ORB (RBE) + Tokyo Coil at USD 25.00 risk (66.7% recovery; 29.3% breach). Lowest-breach active choice: Gold ORB (RBE) + Overnight Bias ORB at USD 5.00 risk (0.0% recovery; 0.0% breach). Lowest-exposure active choice: Gold ORB (RBE) + Overnight Bias ORB at USD 5.00 risk (0.0% recovery; 0.0% breach). Best RBE-excluded alternative: Overnight Bias ORB + Tokyo Coil at USD 25.00 risk (60.8% recovery; 28.0% breach).

FTMO recovery is balance-only and targets return to initial equity above the static loss floor; reward eligibility and rollover are not modeled in recovery paths.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.