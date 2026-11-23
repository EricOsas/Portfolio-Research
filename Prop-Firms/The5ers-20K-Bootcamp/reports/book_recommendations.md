# The5ers $20k Bootcamp — book ranking

Base comparison risk: USD 25 requested total risk per book trade.

Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.
The funded-stage book is the highest training-funded-score book among the ten best training challenge books, so it is a book that can realistically reach funding.

## Challenge candidate
- **challenge_book_1** (Flash ORB + Gold X9 (Very high) + GotobiFix USDJPY + Tokyo Coil)
  - Challenge-to-payout: 71.0%
  - Reach funded: 85.3%
  - Evaluation hard-breach rate: 5.7%
  - Funded hard-breach rate (conditional on funding): 0.0%
  - Median trading days to Step 1 pass: 25.0
  - Median trading days through all evaluation steps: 166.0
  - Median trading days to first The5ers payout: 192.0
  - Expected first The5ers payout across all paths: USD 145.31
  - Median The5ers payout on successful paths: USD 194.22

## RBE-excluded challenge sensitivity
- **challenge_book_1** (Flash ORB + Gold X9 (Very high) + GotobiFix USDJPY + Tokyo Coil)
  - Challenge-to-first-reward: 71.0%
  - Reach funded: 85.3%
  - Evaluation hard-breach rate: 5.7%
  - Funded hard-breach rate (conditional on funding): 0.0%

## Holdout validation leader (diagnostic only)
- **Gold ORB (RBE) + Gold X9 (Very high) + GotobiFix EURJPY + Overnight Bias ORB** (Gold ORB (RBE) + Gold X9 (Very high) + GotobiFix EURJPY + Overnight Bias ORB)
  - Challenge-to-payout: 89.1%
  - Reach funded: 92.8%
  - Evaluation hard-breach rate: 5.6%

## Funded candidate
- **Gold X9 (Very high) + GotobiFix EURJPY + GotobiFix USDJPY + Sigma ORB** (Gold X9 (Very high) + GotobiFix EURJPY + GotobiFix USDJPY + Sigma ORB)
  - Conditional first-payout rate: 85.5%
  - Funded hard-breach rate (conditional on funding): 0.0%
  - Approximate 90-trading-day funded survival: 100.0%
  - Mean payout count over the horizon: 1.76
  - Median trading days to first The5ers payout: 190.0

### Challenge candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $10 | $10 | 0.5% | 0.2% | 0.0% | 0.0% | nan% | 251 | $0.03 | — | — | — | — |
| $25 | $25 | 85.3% | 5.7% | 71.0% | 0.0% | 100.0% | 192 | $145.31 | $220 | $-32 | $224 | $555 |
| $50 | $50 | 79.3% | 20.6% | 78.1% | 6.4% | 96.6% | 104 | $203.99 | — | — | — | — |
| $100 | $100 | 60.8% | 39.2% | 57.5% | 60.2% | 67.9% | 52 | $229.93 | — | — | — | — |

### Funded candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $10 | $10 | 0.4% | 0.1% | 0.0% | 0.0% | nan% | — | $0.00 | — | — | — | — |
| $25 | $25 | 87.3% | 5.5% | 74.6% | 0.0% | 100.0% | 190 | $152.44 | — | — | — | — |
| $50 | $50 | 80.2% | 19.8% | 79.1% | 7.2% | 96.2% | 102 | $205.95 | — | — | — | — |
| $100 | $100 | 59.8% | 40.2% | 56.0% | 58.5% | 70.2% | 51 | $221.35 | — | — | — | — |

## Expected account attempts before first payout
- Challenge pass probability: 85.3%.
- First-payout probability after funding with the selected funded book: 85.5%.
- Approximate payout probability per challenge start when switching to the selected funded book: 72.9%.
- Expected challenge accounts started per first payout: 1.37.
- Expected failed evaluation accounts before first payout: 0.20.
- Expected funded accounts entered per first payout: 1.17.
- Expected failed funded accounts before first payout: 0.17.
- Approximate combined hard-breach probability per challenge start: 5.7%.
These are geometric-repeat estimates. They assume each new account repeats the same probabilities; they are not a guarantee and do not include account fees.

## Near-floor recovery
Gold X9 (Low) + GotobiFix EURJPY at USD 12.50 risk per book trade: recovery probability 95.3%, breach probability 1.5%.

The5ers recovery is balance-only and targets return to the funded $20,000 initial balance above the static 4% loss floor; the 3% daily pause is modeled as a closed-PnL clip, and payout eligibility is not modeled in recovery paths.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.