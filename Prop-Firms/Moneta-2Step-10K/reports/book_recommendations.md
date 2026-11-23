# Moneta Funded $10k 2-Step Standard — book ranking

Base comparison risk: USD 50 requested total risk per book trade.

Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.
The funded-stage book is the highest training-funded-score book among the ten best training challenge books, so it is a book that can realistically reach funding.

## Challenge candidate
- **challenge_book_1** (Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive)
  - Challenge-to-payout: 95.1%
  - Pass rate: 96.3%
  - Evaluation hard-breach rate: 3.6%
  - Funded hard-breach rate (conditional on funding): 13.4%
  - Median trading days to Step 1 pass: 20.0
  - Median trading days to first payout: 80.0

## Holdout validation leader (diagnostic only)
- **Gold X9 + GotobiFix EURJPY + Overnight Bias ORB + Tokyo Coil** (Gold X9 + GotobiFix EURJPY + Overnight Bias ORB + Tokyo Coil)
  - Challenge-to-payout: 98.1%
  - Pass rate: 98.6%
  - Evaluation hard-breach rate: 1.4%

## Funded candidate
- **Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil** (Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil)
  - Conditional first-payout rate: 99.3%
  - Funded hard-breach rate (conditional on funding): 7.2%
  - Approximate 90-trading-day funded survival: 96.9%
  - Mean payout count over the horizon: 9.05
  - Median trading days to first payout: 86.0

### Challenge candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $12 | $12 | 34.8% | 0.0% | 7.3% | 0.0% | 100.0% | — | — | — | — | — | — |
| $25 | $25 | 96.8% | 0.1% | 93.4% | 0.2% | 99.9% | — | — | — | — | — | — |
| $50 | $50 | 96.3% | 3.6% | 95.1% | 13.4% | 93.9% | — | — | $476 | $-80 | $471 | $1,230 |
| $75 | $75 | 71.9% | 28.1% | 65.4% | 80.4% | 49.7% | — | — | — | — | — | — |
| $100 | $100 | 58.8% | 41.2% | 48.2% | 98.1% | 20.4% | — | — | — | — | — | — |

### Funded candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $12 | $12 | 20.8% | 0.0% | 1.5% | 0.0% | 100.0% | — | — | — | — | — | — |
| $25 | $25 | 96.3% | 0.0% | 92.1% | 0.1% | 99.9% | — | — | — | — | — | — |
| $50 | $50 | 97.9% | 2.0% | 97.3% | 7.2% | 96.9% | — | — | — | — | — | — |
| $75 | $75 | 77.4% | 22.6% | 72.0% | 67.0% | 61.9% | — | — | — | — | — | — |
| $100 | $100 | 60.6% | 39.4% | 51.1% | 96.1% | 26.8% | — | — | — | — | — | — |

## Expected account attempts before first payout
- Challenge pass probability: 96.3%.
- First-payout probability after funding with the selected funded book: 99.3%.
- Approximate payout probability per challenge start when switching to the selected funded book: 95.7%.
- Expected challenge accounts started per first payout: 1.05.
- Expected failed evaluation accounts before first payout: 0.04.
- Expected funded accounts entered per first payout: 1.01.
- Expected failed funded accounts before first payout: 0.01.
- Approximate combined hard-breach probability per challenge start: 10.5%.
These are geometric-repeat estimates. They assume each new account repeats the same probabilities; they are not a guarantee and do not include account fees.

## Near-floor recovery
No active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $100 cushion. No-trade preserves the account but cannot recover it to initial balance. No active candidate passed the eligibility screen.

The5ers recovery is balance-only and targets return to the funded $20,000 initial balance above the static 4% loss floor; the 3% daily pause is modeled as a closed-PnL clip, and payout eligibility is not modeled in recovery paths.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.