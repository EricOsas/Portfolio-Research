# Tradeify $50k Growth futures — book ranking

Base comparison risk: USD 100 requested total risk per book trade.

Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.

## Challenge candidate
- **challenge_book_1** (FVG Duo + Flash ORB + Gold ORB (RBE) + Sigma ORB)
  - Challenge-to-payout: 46.1%
  - Pass rate: 66.8%
  - Evaluation hard-breach rate: 33.2%
  - Funded hard-breach rate (conditional on funding): 38.4%
  - Effective risk after minimum-micro sizing: USD 511.97
  - Median trading days to eligible evaluation pass: 20.0
  - Median trading days to first payout: 57.0

## Holdout validation leader (diagnostic only)
- **Flash ORB + NQ Precision Bot + Overnight Bias ORB + VWAP Pullback** (Flash ORB + NQ Precision Bot + Overnight Bias ORB + VWAP Pullback)
  - Challenge-to-payout: 71.7%
  - Pass rate: 87.3%
  - Evaluation hard-breach rate: 12.5%

## Funded candidate
- **funded_book_2** (Flash ORB + Gold ORB (RBE) + Opening-Shock Continuation + Sigma ORB)
  - Conditional first-payout rate: 77.4%
  - Funded hard-breach rate (conditional on funding): 34.8%
  - Effective risk after minimum-micro sizing: USD 475.65
  - Approximate 90-trading-day funded survival: 72.2%
  - Median first net payout on successful paths: USD 1,350.00
  - Expected first net payout across all paths: USD 784.35
  - Expected total net payout cash across all paths: USD 4,585.71
  - Mean payout count over the horizon: 2.23
  - Median trading days to first payout: 73.0

### Challenge candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $100 | $511.97 | 66.8% | 33.2% | 46.1% | 38.4% | 64.6% | 57 | $622.62 | $1,995 | $-1,111 | $2,558 | $7,003 |
| $250 | $511.97 | 66.8% | 33.2% | 46.1% | 38.4% | 64.6% | 57 | $622.62 | — | — | — | — |
| $500 | $511.97 | 66.8% | 33.2% | 46.1% | 38.4% | 64.6% | 57 | $622.62 | — | — | — | — |
| $750 | $593.28 | 62.5% | 37.5% | 39.3% | 44.1% | 57.9% | 45 | $531.09 | — | — | — | — |

### Funded candidate risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $100 | $475.65 | 75.0% | 25.0% | 58.1% | 34.8% | 72.2% | 73 | $784.35 | $1,527 | $-822 | $2,028 | $5,395 |
| $250 | $475.65 | 75.0% | 25.0% | 58.1% | 34.8% | 72.2% | 73 | $784.35 | — | — | — | — |
| $500 | $475.65 | 75.0% | 25.0% | 58.1% | 34.8% | 72.2% | 73 | $784.35 | — | — | — | — |
| $750 | $556.96 | 65.7% | 34.3% | 42.0% | 43.9% | 58.7% | 53 | $567.00 | — | — | — | — |

## Expected account attempts before first payout
- Challenge pass probability: 66.8%.
- First-payout probability after funding with the selected funded book: 77.4%.
- Approximate payout probability per challenge start when switching to the selected funded book: 51.7%.
- Expected challenge accounts started per first payout: 1.93.
- Expected failed evaluation accounts before first payout: 0.64.
- Expected funded accounts entered per first payout: 1.29.
- Expected failed funded accounts before first payout: 0.29.
- Approximate combined hard-breach probability per challenge start: 56.4%.
These are geometric-repeat estimates. They assume each new account repeats the same probabilities; they are not a guarantee and do not include account fees.

## Lower-risk two-sleeve alternative
- **Flash ORB + Overnight Bias ORB** (top training-funded-score candidate among eligible two-sleeve books)
  - Requested risk: USD 100.00
  - Effective risk after minimum-micro sizing: USD 237.63
  - Evaluation pass rate: 86.6%
  - Evaluation hard-breach rate: 12.8%
  - Challenge-to-first-payout rate: 64.7%
  - Funded first-payout rate conditional on funding: 74.7%
  - Funded hard-breach rate (conditional on funding): 18.5%
  - Expected challenge starts per payout at this same book: 1.55
  - Expected failed evaluation accounts before payout: 0.21
  - Expected funded accounts per payout: 1.34
  - Expected failed funded accounts before payout: 0.34
  - Approximate 90-trading-day funded survival: 91.2%
  - Median trading days to evaluation pass: 79.0
  - Median trading days to first payout: 164.0
  - Expected first net payout across all paths: USD 873.18
  - Expected total net payout cash across all paths: USD 2,168.67
  - Mean monthly strategy PnL before account rules: USD 634
  - P10 monthly strategy PnL before account rules: USD -522
  - P90 monthly peak-to-trough drawdown: USD 1,119
Monthly PnL and drawdown are strategy-stream estimates before account failures, DLL clipping, payout rules or withdrawal resets.
This is not the overall training-score winner. It is the top funded-score candidate within the eligible two-sleeve subset; its validation results are holdout estimates, not a basis for promoting it over the overall training-selected books.

### Two-sleeve alternative risk ladder
Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.
| Requested risk | Effective risk | Pass | Evaluation breach | Challenge-to-payout | Funded breach | 90-day survival | Median payout days | Expected first payout | Mean monthly PnL | P10 monthly PnL | P90 monthly DD | P95 252d max DD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| $100 | $237.63 | 86.6% | 12.8% | 64.7% | 18.5% | 91.2% | 164 | $873.18 | $634 | $-522 | $1,119 | $3,034 |
| $250 | $237.63 | 86.6% | 12.8% | 64.7% | 18.5% | 91.2% | 164 | $873.18 | — | — | — | — |
| $500 | $475.27 | 66.9% | 33.1% | 44.0% | 44.8% | 61.2% | 76 | $594.54 | — | — | — | — |
| $750 | $712.90 | 59.9% | 40.1% | 33.0% | 52.4% | 49.8% | 51 | $445.23 | — | — | — | — |

## Near-floor recovery
No weekly-eligible active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $200 cushion. No-trade preserves the floor but is not a compliant long-term mode because weekly activity is required. Best recovery chance: Gold ORB (RBE) + Sigma ORB at USD 251.75 risk (61.4% recovery; 38.6% breach). Lowest-breach active choice: Gold ORB (RBE) + Sigma ORB at USD 251.75 risk (61.4% recovery; 38.6% breach). Lowest-exposure active choice: Open Drive at USD 100.78 risk (55.5% recovery; 44.5% breach).

Recovery outputs are balance-only. The $53,000 target is a balance threshold, not an approved payout; 35% consistency, five $150 winning days and payout processing are not enforced in the recovery path.

These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports.