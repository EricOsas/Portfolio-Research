# FTMO $10k 2-Step CFD — book ranking

Base comparison risk: USD 50 requested total risk per book trade.

Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.

## Challenge candidate
- **challenge_book_1** (Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive)
  - Challenge-to-payout: 98.0%
  - Pass rate: 98.5%
  - Evaluation hard-breach rate: 1.4%
  - Funded hard-breach rate (conditional on funding): 0.9%
  - Median trading days to Phase 1 pass: 40.0
  - Median trading days to Verification pass: 64.0
  - Median trading days to first FTMO reward: 81.0
  - Expected first FTMO reward across all paths: USD 253.40
  - Median FTMO reward on successful paths: USD 215.71

## RBE-excluded challenge sensitivity
- **challenge_book_1** (Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive)
  - Challenge-to-first-reward: 98.0%
  - Pass both phases: 98.5%
  - Evaluation hard-breach rate: 1.4%
  - Funded hard-breach rate (conditional on funding): 0.9%

## Holdout validation leader (diagnostic only)
- **FVG Duo + Gold X9 + GotobiFix EURJPY + Overnight Bias ORB** (FVG Duo + Gold X9 + GotobiFix EURJPY + Overnight Bias ORB)
  - Challenge-to-payout: 99.3%
  - Pass rate: 99.5%
  - Evaluation hard-breach rate: 0.5%

## Funded candidate
- **funded_book_1** (Flash ORB + Gold ORB (RBE) + GotobiFix USDJPY + Tokyo Coil)
  - Conditional first-payout rate: 95.7%
  - Funded hard-breach rate (conditional on funding): 0.0%
  - Median trading days to first FTMO reward: 152.0

### Challenge candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $25 | $25 | 96.9% | 0.0% | 94.7% | 0.0% | 145 | $125.43 | — | — | — | — |
| $50 | $50 | 98.5% | 1.4% | 98.0% | 0.9% | 81 | $253.40 | $476 | $-80 | $471 | $1,230 |
| $75 | $75 | 86.8% | 13.2% | 83.8% | 7.3% | 57 | $324.38 | — | — | — | — |
| $100 | $100 | 71.1% | 28.9% | 63.7% | 21.3% | 43 | $347.40 | — | — | — | — |

### Funded candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $25 | $25 | 34.3% | 0.0% | 26.0% | 0.0% | 217 | $20.53 | — | — | — | — |
| $50 | $50 | 90.8% | 0.0% | 86.8% | 0.0% | 152 | $126.35 | $218 | $-101 | $266 | $687 |
| $75 | $75 | 97.1% | 0.8% | 95.3% | 0.6% | 111 | $205.09 | — | — | — | — |
| $100 | $100 | 96.3% | 3.1% | 94.9% | 2.1% | 88 | $260.33 | — | — | — | — |

## Expected account attempts before first payout
- Challenge pass probability: 98.5%.
- First-payout probability after funding with the selected funded book: 95.7%.
- Approximate payout probability per challenge start when switching to the selected funded book: 94.2%.
- Expected challenge accounts started per first payout: 1.06.
- Expected failed evaluation accounts before first payout: 0.02.
- Expected funded accounts entered per first payout: 1.05.
- Expected failed funded accounts before first payout: 0.05.
- Approximate combined hard-breach probability per challenge start: 1.4%.
These are geometric-repeat estimates. They assume each new account repeats the same probabilities; they are not a guarantee and do not include account fees.

## Near-floor recovery
No active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $100 cushion. No-trade preserves the account but cannot recover it to initial balance. Best recovery chance: Gold X9 + GotobiFix EURJPY at USD 10.00 risk (81.3% recovery; 17.6% breach). Lowest-breach active choice: GotobiFix USDJPY + Overnight Bias ORB at USD 5.00 risk (0.0% recovery; 0.0% breach). Lowest-exposure active choice: GotobiFix USDJPY + Overnight Bias ORB at USD 5.00 risk (0.0% recovery; 0.0% breach). Best RBE-excluded alternative: Gold X9 + GotobiFix EURJPY at USD 10.00 risk (81.3% recovery; 17.6% breach).

FTMO recovery is balance-only and targets return to initial equity above the static loss floor; reward eligibility and rollover are not modeled in recovery paths.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.