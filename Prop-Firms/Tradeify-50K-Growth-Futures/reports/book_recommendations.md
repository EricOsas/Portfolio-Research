# Tradeify $50k Growth futures — book ranking

Base comparison risk: USD 100 requested total risk per book trade.

Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.

## Challenge candidate
- **challenge_book_1** (Flash ORB + Gold ORB (RBE) + Sigma ORB + Vault Break)
  - Challenge-to-payout: 51.9%
  - Pass rate: 71.1%
  - Evaluation hard-breach rate: 28.9%
  - Funded hard-breach rate (conditional on funding): 39.8%
  - Effective risk after minimum-micro sizing: USD 457.35
  - Median trading days to eligible evaluation pass: 24.0
  - Median trading days to first payout: 62.0

## Holdout validation leader (diagnostic only)
- **Flash ORB + NQ Precision Bot + Overnight Bias ORB + VWAP Pullback** (Flash ORB + NQ Precision Bot + Overnight Bias ORB + VWAP Pullback)
  - Challenge-to-payout: 68.2%
  - Pass rate: 85.5%
  - Evaluation hard-breach rate: 14.4%

## Funded candidate
- **funded_book_1** (Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB)
  - Conditional first-payout rate: 74.1%
  - Funded hard-breach rate (conditional on funding): 37.9%
  - Effective risk after minimum-micro sizing: USD 472.83
  - Approximate 90-trading-day funded survival: 68.1%
  - Median first net payout on successful paths: USD 1,350.00
  - Expected first net payout across all paths: USD 705.51
  - Expected total net payout cash across all paths: USD 4,272.30
  - Mean payout count over the horizon: 2.07
  - Median trading days to first payout: 68.0

### Challenge candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $100 | $457.35 | 71.1% | 28.9% | 51.9% | 39.8% | 66.4% | 62 | $701.19 | $1,646 | $-996 | $2,275 | $6,189 |
| $250 | $457.35 | 71.1% | 28.9% | 51.9% | 39.8% | 66.4% | 62 | $701.19 | — | — | — | — |
| $500 | $457.35 | 71.1% | 28.9% | 51.9% | 39.8% | 66.4% | 62 | $701.19 | — | — | — | — |
| $750 | $538.02 | 62.5% | 37.5% | 39.4% | 45.6% | 56.7% | 45 | $531.63 | — | — | — | — |

### Funded candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $100 | $472.83 | 70.5% | 29.5% | 52.3% | 37.9% | 68.1% | 68 | $705.51 | $1,574 | $-937 | $2,153 | $5,912 |
| $250 | $472.83 | 70.5% | 29.5% | 52.3% | 37.9% | 68.1% | 68 | $705.51 | — | — | — | — |
| $500 | $472.83 | 70.5% | 29.5% | 52.3% | 37.9% | 68.1% | 68 | $705.51 | — | — | — | — |
| $750 | $553.51 | 62.1% | 37.9% | 37.5% | 47.7% | 54.7% | 48 | $505.98 | — | — | — | — |

## Expected account attempts before first payout
- Challenge pass probability: 71.1%.
- First-payout probability after funding with the selected funded book: 74.1%.
- Approximate payout probability per challenge start when switching to the selected funded book: 52.7%.
- Expected challenge accounts started per first payout: 1.90.
- Expected failed evaluation accounts before first payout: 0.55.
- Expected funded accounts entered per first payout: 1.35.
- Expected failed funded accounts before first payout: 0.35.
- Approximate combined hard-breach probability per challenge start: 55.9%.
These are geometric-repeat estimates. They assume each new account repeats the same probabilities; they are not a guarantee and do not include account fees.

## Lower-risk two-sleeve alternative
- **Flash ORB + Overnight Bias ORB** (top training-funded-score candidate among eligible two-sleeve books)
  - Requested risk: USD 100.00
  - Effective risk after minimum-micro sizing: USD 237.23
  - Evaluation pass rate: 84.3%
  - Evaluation hard-breach rate: 15.1%
  - Challenge-to-first-payout rate: 61.6%
  - Funded first-payout rate conditional on funding: 73.0%
  - Funded hard-breach rate (conditional on funding): 21.3%
  - Expected challenge starts per payout at this same book: 1.62
  - Expected failed evaluation accounts before payout: 0.26
  - Expected funded accounts per payout: 1.37
  - Expected failed funded accounts before payout: 0.37
  - Approximate 90-trading-day funded survival: 89.3%
  - Median trading days to evaluation pass: 76.0
  - Median trading days to first payout: 163.0
  - Expected first net payout across all paths: USD 831.06
  - Expected total net payout cash across all paths: USD 2,009.39
  - Mean monthly strategy PnL before account rules: USD 614
  - P10 monthly strategy PnL before account rules: USD -571
  - P90 monthly peak-to-trough drawdown: USD 1,155
Monthly PnL and drawdown are strategy-stream estimates before account failures, DLL clipping, payout rules or withdrawal resets.
This is not the overall training-score winner. It is the top funded-score candidate within the eligible two-sleeve subset; its validation results are holdout estimates, not a basis for promoting it over the overall training-selected books.

### Two-sleeve alternative risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $100 | $237.23 | 84.3% | 15.1% | 61.6% | 21.3% | 89.3% | 163 | $831.06 | $614 | $-571 | $1,155 | $3,237 |
| $250 | $237.23 | 84.3% | 15.1% | 61.6% | 21.3% | 89.3% | 163 | $831.06 | — | — | — | — |
| $500 | $474.45 | 64.2% | 35.8% | 40.5% | 46.2% | 59.8% | 75 | $547.29 | — | — | — | — |
| $750 | $711.68 | 58.7% | 41.3% | 31.6% | 53.8% | 48.8% | 51 | $426.33 | — | — | — | — |

## Near-floor recovery
No weekly-eligible active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $200 cushion. No-trade preserves the floor but is not a compliant long-term mode because weekly activity is required. Best recovery chance: Open Drive + VWAP Pullback at USD 158.36 risk (59.3% recovery; 40.7% breach). Lowest-breach active choice: Open Drive + VWAP Pullback at USD 158.36 risk (59.3% recovery; 40.7% breach). Lowest-exposure active choice: Open Drive at USD 98.82 risk (58.2% recovery; 41.8% breach).

Recovery outputs are balance-only. The $53,000 target is a balance threshold, not an approved payout; 35% consistency, five $150 winning days and payout processing are not enforced in the recovery path.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.