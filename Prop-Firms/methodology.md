# Prop-firm model methodology

## Common simulation design

- 5,000 Monte Carlo paths per scenario.
- 252 trading-day horizon.
- 5-trading-day circular block bootstrap using the later 40% chronological validation sample.
- Book candidates are selected using the earlier 60% training sample.
- PnL is normalized to realized-loss R units before firm-specific position sizing.
- Challenge pass, drawdown breach, funded survival, payout eligibility, payout amounts and recovery scenarios are reported separately.
- The model is based on completed-trade exports, not an intraday account-equity replay.

## FTMO — USD 10,000 Standard 2-Step CFD

Modeled account objectives:

- Phase 1 profit target: USD 1,000.
- Phase 2 profit target: USD 500.
- Maximum daily loss: USD 500.
- Maximum loss: USD 1,000.
- Minimum four trading days in each phase.
- Default reward split: 80%.
- First reward request: day 14 or later after the first funded trade; the simulation approximates this as 10 trading days.
- Minimum closed profit: USD 20 for bank transfer. A four-business-day review/processing delay is applied.

Risk ladder: USD 25, 50, 75 and 100 total book risk per trade, divided equally across sleeves. Sizing is continuous; instrument-specific minimum lot sizes are not enforced and must be checked against FTMO symbol specifications.

The model does not reconstruct intratrade floating losses, news restrictions, overnight/weekend restrictions, margin, or symbol-specific execution conditions.

## Tradeify — USD 50,000 Growth futures

Modeled account rules:

- Evaluation target: USD 3,000.
- Daily loss limit: USD 1,250, modeled as a soft pause threshold.
- End-of-day trailing maximum loss: USD 2,000.
- Maximum concurrent exposure: four minis / 40 micros.
- At least one micro per active strategy sleeve; sizes are rounded to whole micros.
- Funded trailing floor locks at USD 50,100.
- First payout balance threshold: USD 53,000.
- Funded consistency: 35%.
- Five winning days with more than USD 150 profit, plus at least one trade per week.
- 90% reward split.
- Minimum payout request: USD 500.
- Payout caps are modeled by request number; two trading days are used as the processing approximation.

The Growth evaluation account page and public pricing material have presented inconsistent evaluation-consistency wording. Both cases are reported: the published Growth base case with no evaluation consistency rule, and a 35% evaluation-consistency stress case. Funded consistency is applied in both.

Risk ladder: USD 100, 250, 500 and 750 requested total book risk per trade. Because each active sleeve must use at least one micro, actual risk can exceed or differ from the requested amount. The report shows effective risk after micro sizing and maximum concurrent mini-equivalent exposure.

The NT8 MAE report measures one-micro-per-sleeve adverse-excursion stress. Same-entry-day MAEs are stacked conservatively; this is not a synchronized intraday replay. It is intended to flag possible daily-loss pauses, not predict exact breach timing.

## Recovery scenarios

Recovery simulations include no-trade controls.

- FTMO: starting cushions of USD 100, 250, 500 and 750 above the static loss floor; target is return to initial account equity.
- Tradeify: starting cushions of USD 200, 500, 1,000 and 1,500 above the locked floor; targets are a USD 500 buffer above the floor and the USD 53,000 first-payout balance.
- Tradeify recovery uses one micro per sleeve.
- If no active book meets both the selected recovery-probability and breach-probability thresholds near the floor, no-trade is the safest modeled control.

## Important limitations

- Daily PnL is based on completed-trade exits. Intraday floating equity and exact daily-loss pause sequencing are not reconstructed.
- FTMO exports do not provide intratrade MAE; its equity-based loss rules are therefore modeled from closed PnL.
- Tradeify's EOD trailing drawdown is modeled from daily closes; its real-time daily-loss pause is not fully reconstructed.
- News, hedging/correlated-product restrictions, overnight/session restrictions, broker slippage, margin and exact timezone conversion are not fully tested.
- MT5 RBE pairing uncertainty is documented in its data-quality report.
- The risk unit is a realized-loss proxy, not verified initial stop risk.
- These estimates are conditional on historical behavior and current modeled rules. They are not guarantees or live-deployment approval.
