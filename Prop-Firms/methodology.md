# Prop-firm model methodology

## Common simulation design

- 5,000 Monte Carlo paths per scenario.
- 252 trading-day horizon.
- 5-trading-day circular block bootstrap using the later 40% chronological validation sample.
- Book candidates are selected using the earlier 60% training sample.
- Each sleeve's realized-loss R unit is calibrated on that training sample, then held fixed for the validation sample and all prop position sizing.
- FTMO book PnL uses the average constituent-sleeve R multiplied by total book risk; Tradeify uses sleeve-specific training R units and whole-micro weights.
- All one-to-four-sleeve combinations are screened on training/validation metrics. Firm-specific Monte Carlo covers every single sleeve, the three selected category finalists per category, and the leading two-/three-sleeve candidates; identical books are deduplicated.
- Challenge pass, drawdown breach, funded survival, payout eligibility, payout amounts and recovery scenarios are reported separately.
- The model is based on completed-trade exports, not an intraday account-equity replay.
- The 252-day rates are probabilities within a one-trading-year simulation horizon, not lifetime pass/payout probabilities.

## FTMO — USD 10,000 Standard 2-Step CFD

Modeled account objectives:

- Phase 1 profit target: USD 1,000.
- Phase 2 profit target: USD 500.
- Maximum daily loss: USD 500, equity-based and reset at 00:00 CE(S)T from the day's starting balance.
- Maximum loss: USD 1,000 static floor, 10% of initial capital.
- Minimum four trading days in each phase.
- Default reward split: 80%.
- First reward request: day 14 or later after the first funded trade; the simulation approximates this as 10 trading days.
- Minimum closed profit: USD 20 for bank transfer. A four-business-day review/processing delay is applied.

Risk ladder: USD 25, 50, 75 and 100 total book risk per trade, divided equally across sleeves. Sizing is continuous; instrument-specific minimum lot sizes are not enforced and must be checked against FTMO symbol specifications.

The model does not reconstruct intratrade floating losses, news restrictions, overnight/weekend restrictions, margin, or symbol-specific execution conditions.

## Tradeify — USD 50,000 Growth futures

Modeled account rules:

- Evaluation target: USD 3,000.
- Daily loss limit: USD 1,250, modeled as a soft pause. Closed daily PnL losses are clipped at -$1,250; this is not an intraday replay.
- End-of-day trailing maximum loss: USD 2,000.
- Maximum concurrent exposure: four minis / 40 micros; full size is available from day one.
- At least one micro per active strategy sleeve; sizes are rounded to whole micros.
- Funded trailing floor locks at USD 50,100.
- First payout balance threshold: USD 53,000.
- No evaluation consistency rule for Growth.
- Funded payout consistency: 35%.
- Five winning days with more than USD 150 profit, plus at least one trade per week.
- 90% reward split.
- Minimum payout request: USD 500.
- Payout caps are modeled by request number; two trading days are used as the processing approximation.

The current dedicated Growth evaluation guide explicitly states no evaluation consistency rule. The 35% consistency rule applies to Growth Sim Funded payout eligibility, not evaluation.

Risk ladder: USD 100, 250, 500 and 750 requested total book risk per trade. Because each active sleeve must use at least one micro, actual risk can exceed or differ from the requested amount. The report shows effective risk after micro sizing and maximum concurrent mini-equivalent exposure.

The NT8 MAE report measures one-micro-per-sleeve adverse-excursion stress. Same-entry-day MAEs are stacked conservatively; this is not a synchronized intraday replay. It is intended to flag possible daily-loss pauses, not predict exact breach timing.

## Recovery scenarios

Recovery simulations include no-trade controls.

- FTMO: starting cushions of USD 100, 250, 500 and 750 above the static loss floor; target is return to initial account equity.
- Tradeify: starting cushions of USD 200, 500, 1,000 and 1,500 above the locked floor; targets are a USD 500 buffer above the floor and the USD 53,000 first-payout balance.
- Tradeify recovery uses one micro per sleeve.
- If no active book meets both the selected recovery-probability and breach-probability thresholds near the floor, no-trade is the safest modeled control.

## Time interpretation

- Monte Carlo horizon is 252 simulated trading days (approximately one trading year).
- Time-to-phase, time-to-reward and time-to-recovery fields count trading days, not calendar days.
- Tradeify's `survival_90d_conditional_approx` field means 90 trading days after funding. Its observed sample count excludes paths funded too late in the 252-day horizon to observe a full 90 trading days.

## Official rule references

Rules checked on 2026-11-01. These official pages define the modeled account versions:

- [FTMO 2-Step Challenge objectives](https://ftmo.com/en/2-step-challenge/)
- [FTMO Trading Objectives](https://ftmo.com/en/trading-objectives/)
- [FTMO reward withdrawal process](https://ftmo.com/en/faq/how-do-i-withdraw-my-profits/)
- [Tradeify Growth Evaluation rules](https://help.tradeify.co/en/articles/10495915-growth-evaluation-accounts)
- [Tradeify Essential Trading Rules](https://help.tradeify.co/en/articles/12268167-essential-trading-rules-overview)
- [Tradeify Growth funded payout policy](https://help.tradeify.co/en/articles/11083796-growth-funded-account-payout-policy)
- [Tradeify consistency rule](https://help.tradeify.co/en/articles/10468320-rules-consistency-rule)
- [Tradeify trailing drawdown rules](https://help.tradeify.co/en/articles/10495897-rules-trailing-max-drawdowns)

## Important limitations

- Daily PnL is based on completed-trade exits. Intraday floating equity and exact daily-loss pause sequencing are not reconstructed.
- FTMO 2-Step has a $500 equity-based daily loss and a static $1,000 maximum-loss floor. The model uses closed PnL, so floating-loss breaches remain unobservable.
- Tradeify's EOD trailing drawdown is modeled from daily closes. The $1,250 soft DLL is approximated by clipping closed daily losses; intraday trigger timing and overshoot are not reconstructed.
- News, hedging/correlated-product restrictions, overnight/session restrictions, broker slippage, margin and exact timezone conversion are not fully tested.
- MT5 RBE pairing uncertainty is documented in its data-quality report.
- The risk unit is a training-period realized-loss proxy, not verified initial stop risk. MT5 microscalping eligibility is also checked on the validation sample.
- These estimates are conditional on historical behavior and current modeled rules. They are not guarantees or live-deployment approval.
