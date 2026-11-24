# The5ers $20k Bootcamp — book ranking

Base comparison risk: USD 25 requested total risk per book trade.

Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.
The funded-stage book is the highest training-funded-score book among the ten best training challenge books, so it is a book that can realistically reach funding.

## Challenge candidate
- **funded_book_1** (Flash ORB + Gold X9 (Low) + GotobiFix USDJPY + Tokyo Coil)
  - Challenge-to-payout: 3.0%
  - Reach funded: 18.3%
  - Evaluation hard-breach rate: 0.1%
  - Funded hard-breach rate (conditional on funding): 0.0%
  - Median trading days to Step 1 pass: 49.0
  - Median trading days through all evaluation steps: 230.0
  - Median trading days to first The5ers payout: 236.0
  - Expected first The5ers payout across all paths: USD 5.45
  - Median The5ers payout on successful paths: USD 176.97

## RBE-excluded challenge sensitivity
- **funded_book_1** (Flash ORB + Gold X9 (Low) + GotobiFix USDJPY + Tokyo Coil)
  - Challenge-to-first-reward: 3.0%
  - Reach funded: 18.3%
  - Evaluation hard-breach rate: 0.1%
  - Funded hard-breach rate (conditional on funding): 0.0%

## Holdout validation leader (diagnostic only)
- **Gold ORB (RBE) + Gold X9 (Low)** (Gold ORB (RBE) + Gold X9 (Low))
  - Challenge-to-payout: 87.6%
  - Reach funded: 92.5%
  - Evaluation hard-breach rate: 5.4%

## Funded candidate
- **funded_book_1** (Flash ORB + Gold X9 (Low) + GotobiFix USDJPY + Tokyo Coil)
  - Conditional first-payout rate: 16.4%
  - Funded hard-breach rate (conditional on funding): 0.0%
  - Approximate 90-trading-day funded survival: 100.0%
  - Mean payout count over the horizon: 0.03
  - Median trading days to first The5ers payout: 236.0

### Challenge candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $10 | $10 | 0.0% | 0.0% | 0.0% | 0.0% | nan% | — | $0.00 | — | — | — | — |
| $25 | $25 | 18.3% | 0.1% | 3.0% | 0.0% | 100.0% | 236 | $5.45 | $125 | $-6 | $94 | $215 |
| $50 | $50 | 92.8% | 2.5% | 82.6% | 0.0% | 100.0% | 182 | $173.96 | — | — | — | — |
| $100 | $100 | 83.5% | 16.5% | 83.1% | 1.9% | 99.0% | 100 | $231.86 | — | — | — | — |

## Expected account attempts before first payout
- Challenge pass probability: 18.3%.
- First-payout probability after funding with the selected funded book: 16.4%.
- Approximate payout probability per challenge start when switching to the selected funded book: 3.0%.
- Expected challenge accounts started per first payout: 33.33.
- Expected failed evaluation accounts before first payout: 27.23.
- Expected funded accounts entered per first payout: 6.10.
- Expected failed funded accounts before first payout: 5.10.
- Approximate combined hard-breach probability per challenge start: 0.1%.
These are geometric-repeat estimates. They assume each new account repeats the same probabilities; they are not a guarantee and do not include account fees.

## Near-floor recovery
Gold X9 (Low) + GotobiFix EURJPY at USD 12.50 risk per book trade: recovery probability 95.1%, breach probability 1.8%.

The5ers recovery is balance-only and targets return to the funded $20,000 initial balance above the static 4% loss floor; the 3% daily pause is modeled as a closed-PnL clip, and payout eligibility is not modeled in recovery paths.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.