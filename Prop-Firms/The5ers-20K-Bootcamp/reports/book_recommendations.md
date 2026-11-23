# The5ers $20k Bootcamp — book ranking

Base comparison risk: USD 25 requested total risk per book trade.

Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.
The funded-stage book is the highest training-funded-score book among the ten best training challenge books, so it is a book that can realistically reach funding.

## Challenge candidate
- **challenge_book_1** (Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive)
  - Challenge-to-payout: 76.3%
  - Reach funded: 86.6%
  - Evaluation hard-breach rate: 7.5%
  - Funded hard-breach rate (conditional on funding): 0.0%
  - Median trading days to Step 1 pass: 22.0
  - Median trading days through all evaluation steps: 152.0
  - Median trading days to first The5ers payout: 180.0
  - Expected first The5ers payout across all paths: USD 159.47
  - Median The5ers payout on successful paths: USD 197.66

## RBE-excluded challenge sensitivity
- **challenge_book_1** (Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive)
  - Challenge-to-first-reward: 76.3%
  - Reach funded: 86.6%
  - Evaluation hard-breach rate: 7.5%
  - Funded hard-breach rate (conditional on funding): 0.0%

## Holdout validation leader (diagnostic only)
- **FVG Duo + Gold ORB (RBE) + Gold X9 + GotobiFix EURJPY** (FVG Duo + Gold ORB (RBE) + Gold X9 + GotobiFix EURJPY)
  - Challenge-to-payout: 88.2%
  - Reach funded: 91.9%
  - Evaluation hard-breach rate: 6.7%

## Funded candidate
- **Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil** (Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil)
  - Conditional first-payout rate: 85.7%
  - Funded hard-breach rate (conditional on funding): 0.0%
  - Approximate 90-trading-day funded survival: 100.0%
  - Mean payout count over the horizon: 1.78
  - Median trading days to first The5ers payout: 189.5

### Challenge candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $10 | $10 | 1.5% | 0.3% | 0.0% | 0.0% | nan% | 238 | $0.07 | — | — | — | — |
| $25 | $25 | 86.6% | 7.5% | 76.3% | 0.0% | 100.0% | 180 | $159.47 | $238 | $-40 | $236 | $615 |
| $50 | $50 | 78.0% | 21.9% | 76.9% | 11.4% | 94.1% | 96 | $208.36 | — | — | — | — |
| $100 | $100 | 57.9% | 42.1% | 53.7% | 66.6% | 63.5% | 48 | $226.76 | — | — | — | — |

### Funded candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $10 | $10 | 0.4% | 0.1% | 0.0% | 0.0% | nan% | — | $0.00 | — | — | — | — |
| $25 | $25 | 87.2% | 5.2% | 74.7% | 0.0% | 100.0% | 190 | $151.86 | — | — | — | — |
| $50 | $50 | 80.5% | 19.5% | 79.4% | 6.1% | 96.8% | 102 | $208.08 | — | — | — | — |
| $100 | $100 | 61.3% | 38.7% | 57.7% | 56.2% | 71.0% | 52 | $227.56 | — | — | — | — |

## Expected account attempts before first payout
- Challenge pass probability: 86.6%.
- First-payout probability after funding with the selected funded book: 85.7%.
- Approximate payout probability per challenge start when switching to the selected funded book: 74.3%.
- Expected challenge accounts started per first payout: 1.35.
- Expected failed evaluation accounts before first payout: 0.18.
- Expected funded accounts entered per first payout: 1.17.
- Expected failed funded accounts before first payout: 0.17.
- Approximate combined hard-breach probability per challenge start: 7.5%.
These are geometric-repeat estimates. They assume each new account repeats the same probabilities; they are not a guarantee and do not include account fees.

## Near-floor recovery
No active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $100 cushion. No-trade preserves the account but cannot recover it to initial balance. Best recovery chance: Gold ORB (RBE) + Gold X9 at USD 5.00 risk (89.0% recovery; 7.3% breach). Lowest-breach active choice: GotobiFix USDJPY + Overnight Bias ORB at USD 5.00 risk (0.0% recovery; 0.0% breach). Lowest-exposure active choice: GotobiFix USDJPY + Overnight Bias ORB at USD 5.00 risk (0.0% recovery; 0.0% breach). Best RBE-excluded alternative: GotobiFix EURJPY + Overnight Bias ORB at USD 25.00 risk (84.1% recovery; 5.3% breach).

The5ers recovery is balance-only and targets return to the funded $20,000 initial balance above the static 4% loss floor; the 3% daily pause is modeled as a closed-PnL clip, and payout eligibility is not modeled in recovery paths.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.