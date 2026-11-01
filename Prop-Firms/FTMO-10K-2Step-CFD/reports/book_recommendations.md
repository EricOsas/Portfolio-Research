# FTMO $10k 2-Step CFD — book ranking

Base comparison risk: USD 50 requested total risk per book trade.

Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.

## Challenge candidate
- **challenge_book_1** (Flash ORB + Gold ORB (RBE) + Open Drive + Tokyo Coil)
  - Challenge-to-payout: 92.9%
  - Pass rate: 95.1%
  - Evaluation hard-breach rate: 0.9%
  - Funded hard-breach rate (conditional on funding): 0.5%
  - Median trading days to Phase 1 pass: 68.0
  - Median trading days to Verification pass: 109.0
  - Median trading days to first FTMO reward: 127.0
  - Expected first FTMO reward across all paths: USD 165.11
  - Median FTMO reward on successful paths: USD 127.52

## RBE-excluded challenge sensitivity
- **Flash ORB + Open Drive + Overnight Bias ORB + Tokyo Coil** (Flash ORB + Open Drive + Overnight Bias ORB + Tokyo Coil)
  - Challenge-to-first-reward: 90.6%
  - Pass both phases: 93.8%
  - Evaluation hard-breach rate: 0.9%
  - Funded hard-breach rate (conditional on funding): 0.3%

## Holdout validation leader (diagnostic only)
- **challenge_book_3** (Gold ORB (RBE) + Open Drive + Overnight Bias ORB + Tokyo Coil)
  - Challenge-to-payout: 94.6%
  - Pass rate: 96.5%
  - Evaluation hard-breach rate: 0.5%

## Funded candidate
- **challenge_book_1** (Flash ORB + Gold ORB (RBE) + Open Drive + Tokyo Coil)
  - Conditional first-payout rate: 97.6%
  - Funded hard-breach rate (conditional on funding): 0.5%
  - Median trading days to first FTMO reward: 127.0

## Near-floor recovery
No active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $100 cushion. No-trade preserves the account but cannot recover it to initial balance. Best recovery chance: Gold ORB (RBE) + Tokyo Coil at USD 25.00 risk (66.7% recovery; 29.3% breach). Lowest-breach active choice: Gold ORB (RBE) + Overnight Bias ORB at USD 5.00 risk (0.0% recovery; 0.0% breach). Lowest-exposure active choice: Gold ORB (RBE) + Overnight Bias ORB at USD 5.00 risk (0.0% recovery; 0.0% breach). Best RBE-excluded alternative: Overnight Bias ORB + Tokyo Coil at USD 25.00 risk (60.8% recovery; 28.0% breach).

FTMO recovery is balance-only and targets return to initial equity above the static loss floor; reward eligibility and rollover are not modeled in recovery paths.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.