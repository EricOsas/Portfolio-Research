# Moneta Funded $10k 2-Step Standard — book ranking

Base comparison risk: USD 50 requested total risk per book trade.

Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.
The funded-stage book is the highest training-funded-score book among the ten best training challenge books, so it is a book that can realistically reach funding.

## Challenge candidate
- **challenge_book_1** (Flash ORB + Gold X9 (Very high) + GotobiFix USDJPY + Tokyo Coil)
  - Challenge-to-payout: 96.4%
  - Pass rate: 97.3%
  - Evaluation hard-breach rate: 2.5%
  - Funded hard-breach rate (conditional on funding): 7.5%
  - Median trading days to Step 1 pass: 21.0
  - Median trading days to first payout: 88.0

## Holdout validation leader (diagnostic only)
- **Gold ORB (RBE) + Gold X9 (Low) + GotobiFix EURJPY + Tokyo Coil** (Gold ORB (RBE) + Gold X9 (Low) + GotobiFix EURJPY + Tokyo Coil)
  - Challenge-to-payout: 99.8%
  - Pass rate: 99.9%
  - Evaluation hard-breach rate: 0.0%

## Funded candidate
- **Gold X9 (Very high) + GotobiFix EURJPY + GotobiFix USDJPY + Sigma ORB** (Gold X9 (Very high) + GotobiFix EURJPY + GotobiFix USDJPY + Sigma ORB)
  - Conditional first-payout rate: 99.2%
  - Funded hard-breach rate (conditional on funding): 8.4%
  - Approximate 90-trading-day funded survival: 96.3%
  - Mean payout count over the horizon: 9.30
  - Median trading days to first payout: 85.0

### Challenge candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $12 | $12 | 18.1% | 0.0% | 1.6% | 0.0% | 100.0% | — | — | — | — | — | — |
| $25 | $25 | 95.6% | 0.0% | 90.3% | 0.1% | 99.9% | — | — | — | — | — | — |
| $50 | $50 | 97.3% | 2.5% | 96.4% | 7.5% | 96.3% | — | — | $439 | $-65 | $448 | $1,111 |
| $75 | $75 | 78.1% | 21.9% | 73.1% | 65.2% | 62.7% | — | — | — | — | — | — |
| $100 | $100 | 59.5% | 40.5% | 50.3% | 95.8% | 26.1% | — | — | — | — | — | — |

### Funded candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $12 | $12 | 29.5% | 0.0% | 5.0% | 0.0% | 100.0% | — | — | — | — | — | — |
| $25 | $25 | 96.7% | 0.0% | 92.3% | 0.0% | 99.9% | — | — | — | — | — | — |
| $50 | $50 | 97.7% | 2.2% | 96.9% | 8.4% | 96.3% | — | — | — | — | — | — |
| $75 | $75 | 67.1% | 32.9% | 57.8% | 88.5% | 37.9% | — | — | — | — | — | — |
| $100 | $100 | 59.3% | 40.7% | 47.8% | 97.3% | 22.0% | — | — | — | — | — | — |

## Expected account attempts before first payout
- Challenge pass probability: 97.3%.
- First-payout probability after funding with the selected funded book: 99.2%.
- Approximate payout probability per challenge start when switching to the selected funded book: 96.5%.
- Expected challenge accounts started per first payout: 1.04.
- Expected failed evaluation accounts before first payout: 0.03.
- Expected funded accounts entered per first payout: 1.01.
- Expected failed funded accounts before first payout: 0.01.
- Approximate combined hard-breach probability per challenge start: 10.7%.
These are geometric-repeat estimates. They assume each new account repeats the same probabilities; they are not a guarantee and do not include account fees.

## Near-floor recovery
No active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $100 cushion. No-trade preserves the account but cannot recover it to initial balance. No active candidate passed the eligibility screen.

The5ers recovery is balance-only and targets return to the funded $20,000 initial balance above the static 4% loss floor; the 3% daily pause is modeled as a closed-PnL clip, and payout eligibility is not modeled in recovery paths.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.