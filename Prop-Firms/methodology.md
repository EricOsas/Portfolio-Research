# Prop-firm model methodology

## Common simulation design

- 5,000 Monte Carlo paths per scenario.
- 252 trading-day horizon.
- 5-trading-day block bootstrap aligned to complete Monday-Friday weeks, sampled with replacement from the later 40% chronological validation sample.
- Book candidates are selected using the earlier 60% training sample. This is one chronological holdout, not a multi-fold rolling walk-forward test.
- Each sleeve's realized-loss R unit is calibrated on that training sample, then held fixed for the validation sample and all prop position sizing.
- FTMO book PnL uses the average constituent-sleeve R multiplied by total book risk; Tradeify uses sleeve-specific training R units and whole-micro weights.
- All one-to-four-sleeve combinations are screened on training/validation metrics. Firm-specific Monte Carlo covers every single sleeve, the three selected category finalists per category, and the leading two-/three-sleeve candidates; identical books are deduplicated.
- FTMO also receives leading RBE-excluded pair/triple candidates as a sensitivity because the MT5 Gold ORB (RBE) export lacks position IDs and requires fallback trade pairing.
- Challenge pass, evaluation hard breach, funded hard breach conditional on funding, funded survival, payout eligibility, payout amounts and recovery scenarios are reported separately.
- The model is based on completed-trade exports, not an intraday account-equity replay. Tradeify reports both raw evaluation target-hit rate and eligible evaluation pass rate; the latter also requires minimum weekly activity and position-limit compliance.
- The 252-day rates are probabilities within a one-trading-year horizon from challenge start, not lifetime pass/payout probabilities. Paths still in evaluation/verification or awaiting a payout at day 252 count as non-passes/no payout, not necessarily hard breaches.
- Conditional funded breach and payout rates use only the remaining horizon after funding, not a full 252 days after funding. Tradeify's separate 90-trading-day survival estimate uses only paths funded early enough to observe a full 90 further trading days.
- The 5,000 paths quantify variability under resampled historical daily returns; they do not prove the future distribution will match history. Monte Carlo sampling error is smaller than this model/data uncertainty. Full calendar-week blocks preserve the weekly activity structure.
- Common bootstrap block samples are used across each firm's risk ladder for a given book, making position-size comparisons less noisy.
- Tradeify weekly activity is checked on complete Monday-Friday validation weeks and applies during both evaluation and funded trading. Bootstrap blocks are aligned to those weeks, so simulated weeks preserve the observed activity pattern. Books that fail weekly activity or breach the four-mini position cap are not counted as eligible evaluation passes. Microscalping is a funded payout-eligibility rule; it is checked on validation trades, and missing durations count as not qualifying for the over-10-second rule.

## FTMO — USD 10,000 Standard 2-Step CFD

Modeled account objectives:

- Phase 1 profit target: USD 1,000.
- Phase 2 profit target: USD 500.
- Maximum daily loss: USD 500, equity-based and reset at 00:00 CE(S)T from the day's starting balance.
- Maximum loss: USD 1,000 static floor, 10% of initial capital.
- Minimum four trading days in each phase.
- Default reward split: 80%.
- The modeled cash-withdrawal case pays 80% of the requested profit and leaves 20% in the funded account. FTMO's rollover option is not simulated.
- First reward request: day 14 or later after the first funded trade; the simulation allows 10 elapsed trading days (the 11th sampled business day counting the first-trade day) as an approximation.
- The model advances from one evaluation phase to the next on the following simulated trading day; FTMO's review and KYC/activation delays are not included.
- Minimum closed profit: USD 20 for bank transfer. A four-business-day review/processing delay is applied.

Risk ladder: USD 25, 50, 75 and 100 total book risk per trade, divided equally across sleeves. Sizing is continuous; instrument-specific minimum lot sizes are not enforced and must be checked against FTMO symbol specifications.

The model does not reconstruct intratrade floating losses, news restrictions, overnight/weekend restrictions, margin, or symbol-specific execution conditions.

## Tradeify — USD 50,000 Growth futures

The model assumes the current non-legacy Growth rules for accounts purchased on or after September 12, 2025. Older legacy accounts have different DLL and payout thresholds and need a separate model.

Modeled account rules:

- Evaluation target: USD 3,000.
- Daily loss limit: USD 1,250 initially. Once the funded account reaches USD 53,000 (+6%), the official DLL rises to USD 2,000 from the next trading session.
- The model clips closed daily PnL at -$1,250 initially and -$2,000 after the threshold, and assumes the higher DLL remains unlocked after payout withdrawals. This is not an intraday replay and cannot reconstruct trigger timing or overshoot.
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

Risk ladder: USD 100, 250, 500 and 750 requested total book risk per trade. The recommendation ranking uses USD 100 as its minimum requested-risk baseline. Because each active sleeve must use at least one micro, the leading eligible pair's effective risk is approximately USD 237 per book trade even at the USD 100 request; the USD 250 request produces the same minimum micro sizing. Actual risk can exceed or differ from the requested amount. The report shows effective risk after micro sizing and maximum concurrent mini-equivalent exposure. Compare the full risk ladder in the Monte Carlo CSV.

The NT8 MAE report measures one-micro-per-sleeve adverse-excursion stress. Same-entry-day MAEs are stacked conservatively; this is not a synchronized intraday replay. It is intended to flag possible daily-loss pauses, not predict exact breach timing.

## Recovery scenarios

Recovery simulations include no-trade controls and selected low-complexity books plus the leading challenge/funded pairs.

These are balance-recovery simulations, not payout-eligibility simulations. Tradeify weekly-activity and microscalping eligibility are reported beside each recovery book, but the recovery path does not enforce funded 35% consistency, five $150 winning days, or payout request processing. The $53,000 target therefore means the account balance reaches the payout threshold; it does not mean a payout is approved.

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
- [FTMO phase review process](https://ftmo.com/faq/i-have-successfully-passed-what-to-do-now/)
- [Tradeify Growth Evaluation rules](https://help.tradeify.co/en/articles/10495915-growth-evaluation-accounts)
- [Tradeify Essential Trading Rules](https://help.tradeify.co/en/articles/12268167-essential-trading-rules-overview)
- [Tradeify Daily Loss Limit](https://help.tradeify.co/en/articles/10468321-rules-daily-loss-limit)
- [Tradeify Growth funded payout policy](https://help.tradeify.co/en/articles/11083796-growth-funded-account-payout-policy)
- [Tradeify consistency rule](https://help.tradeify.co/en/articles/10468320-rules-consistency-rule)
- [Tradeify trailing drawdown rules](https://help.tradeify.co/en/articles/10495897-rules-trailing-max-drawdowns)

## Important limitations

- Daily PnL is based on completed-trade exits. Intraday floating equity and exact daily-loss pause sequencing are not reconstructed.
- FTMO 2-Step has a $500 equity-based daily loss and a static $1,000 maximum-loss floor. The model uses closed PnL, so floating-loss breaches remain unobservable.
- Tradeify's EOD trailing drawdown is modeled from daily closes. The soft DLL is approximated by clipping closed daily losses at $1,250 initially and $2,000 after the funded balance reaches $53,000; intraday trigger timing and overshoot are not reconstructed.
- Tradeify payout profitable days and consistency use exit-date daily buckets; export timestamps are not converted to the firm's 6 PM–5 PM ET trading-day boundary, so eligibility can differ from the live platform.
- Tradeify recovery candidates are restricted to weekly-activity-eligible books. The $53,000 recovery chart also requires microscalping eligibility, but it still does not enforce 35% consistency, five winning days above $150 or payout processing.
- FTMO phase review, verification and KYC/activation delays are not simulated; phase transitions occur on the next simulated trading day, so time-to-funded estimates are optimistic.
- News, hedging/correlated-product restrictions, overnight/session restrictions, broker slippage, margin and exact timezone conversion are not fully tested.
- MT5 RBE pairing uncertainty is documented in its data-quality report.
- The risk unit is a training-period realized-loss proxy, not verified initial stop risk. MT5 microscalping eligibility is also checked on the validation sample.
- These estimates are conditional on historical behavior and current modeled rules. They are not guarantees or live-deployment approval.
