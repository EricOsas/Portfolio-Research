# Moneta Funded $10k 2-Step Standard — book ranking

Base comparison risk: USD 50 requested total risk per book trade.

Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.
The funded-stage book is the highest training-funded-score book among the ten best training challenge books, so it is a book that can realistically reach funding.

## Challenge candidate
- **funded_book_1** (Flash ORB + Gold X9 (Low) + GotobiFix USDJPY + Tokyo Coil)
  - Challenge-to-payout: 95.3%
  - Pass rate: 98.3%
  - Evaluation hard-breach rate: 0.0%
  - Funded hard-breach rate (conditional on funding): 0.0%
  - Median trading days to Step 1 pass: 41.0
  - Median trading days to first payout: 155.0

## Holdout validation leader (diagnostic only)
- **FVG Duo + Gold ORB (RBE) + Gold X9 (Low) + GotobiFix EURJPY** (FVG Duo + Gold ORB (RBE) + Gold X9 (Low) + GotobiFix EURJPY)
  - Challenge-to-payout: 99.8%
  - Pass rate: 100.0%
  - Evaluation hard-breach rate: 0.0%

## Funded candidate
- **funded_book_1** (Flash ORB + Gold X9 (Low) + GotobiFix USDJPY + Tokyo Coil)
  - Conditional first-payout rate: 96.9%
  - Funded hard-breach rate (conditional on funding): 0.0%
  - Approximate 90-trading-day funded survival: 100.0%
  - Mean payout count over the horizon: 3.71
  - Median trading days to first payout: 155.0

### Challenge candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $12 | $12 | 0.0% | 0.0% | 0.0% | 0.0% | nan% | — | — | — | — | — | — |
| $25 | $25 | 45.2% | 0.0% | 10.2% | 0.0% | 100.0% | — | — | — | — | — | — |
| $50 | $50 | 98.3% | 0.0% | 95.3% | 0.0% | 100.0% | — | — | $249 | $-12 | $188 | $429 |
| $75 | $75 | 99.7% | 0.2% | 99.3% | 0.2% | 99.9% | — | — | — | — | — | — |
| $100 | $100 | 99.4% | 0.6% | 98.9% | 2.4% | 98.8% | — | — | — | — | — | — |

## Expected account attempts before first payout
- Challenge pass probability: 98.3%.
- First-payout probability after funding with the selected funded book: 96.9%.
- Approximate payout probability per challenge start when switching to the selected funded book: 95.3%.
- Expected challenge accounts started per first payout: 1.05.
- Expected failed evaluation accounts before first payout: 0.02.
- Expected funded accounts entered per first payout: 1.03.
- Expected failed funded accounts before first payout: 0.03.
- Approximate combined hard-breach probability per challenge start: 0.0%.
These are geometric-repeat estimates. They assume each new account repeats the same probabilities; they are not a guarantee and do not include account fees.

## Near-floor recovery
No active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $100 cushion. No-trade preserves the account but cannot recover it to initial balance. No active candidate passed the eligibility screen.

The5ers recovery is balance-only and targets return to the funded $20,000 initial balance above the static 4% loss floor; the 3% daily pause is modeled as a closed-PnL clip, and payout eligibility is not modeled in recovery paths.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.