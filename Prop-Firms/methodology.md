# Prop-firm model methodology

## Common simulation design

- 5,000 Monte Carlo paths per scenario.
- 252 trading-day horizon.
- 5-trading-day block bootstrap aligned to complete Monday-Friday weeks, sampled with replacement from the later 40% chronological validation sample.
- Book candidates are selected using the earlier 60% training sample. This is one chronological holdout, not a multi-fold rolling walk-forward test.
- Each sleeve's realized-loss R unit is calibrated on that training sample, then held fixed for the validation sample and all prop position sizing. MT5 cash flows are divided by traded volume first, so balance-compounding exports (Gold X9, Tokyo Coil) enter at per-lot risk rather than balance-scaled dollars.
- The5ers book PnL uses the average constituent-sleeve R multiplied by total book risk; Tradeify uses sleeve-specific training R units and whole-micro weights.
- Every one-to-four-sleeve combination is evaluated by firm-specific Monte Carlo across the full risk ladder: all 1,940 MT5 books for The5ers and all 385 NT8 books for Tradeify, each with 5,000 paths over 252 trading days. Identical strategy sets are deduplicated.
- Primary challenge and funded recommendations are selected using training-only challenge/funded scores, then evaluated on the later validation sample. The best validation-only row is reported as a diagnostic and is not used to choose the winner; this reduces holdout selection bias.
- RBE-excluded The5ers candidates are included in the full combination universe and separately surfaced as a sensitivity because the MT5 Gold ORB (RBE) export lacks position IDs and requires fallback trade pairing.
- Challenge pass, evaluation hard breach, funded hard breach conditional on funding, funded survival, payout eligibility, payout amounts and recovery scenarios are reported separately.
- Near-floor recovery scenarios test all positive-training single-sleeve and pair candidates with at least 30 active training days. Tradeify recovery candidates are further screened for weekly activity and microscalping eligibility.
- The model is based on completed-trade exports, not an intraday account-equity replay. Tradeify reports both raw evaluation target-hit rate and eligible evaluation pass rate; the latter also requires minimum weekly activity and position-limit compliance.
- The 252-day rates are probabilities within a one-trading-year horizon from challenge start, not lifetime pass/payout probabilities. Paths still in evaluation/verification or awaiting a payout at day 252 count as non-passes/no payout, not necessarily hard breaches.
- Conditional funded breach and payout rates use only the remaining horizon after funding, not a full 252 days after funding. Tradeify's separate 90-trading-day survival estimate uses only paths funded early enough to observe a full 90 further trading days.
- The 5,000 paths quantify variability under resampled historical daily returns; they do not prove the future distribution will match history. At a 50% event rate, the Monte Carlo-only 95% sampling margin is about ±1.4 percentage points; at 95%, about ±0.6 points. A 0/5,000 observed event rate is not zero true risk (rough one-sided 95% upper bound 0.06%). Model/data uncertainty is larger than these simulation errors. Full calendar-week blocks preserve the weekly activity structure.
- Common bootstrap block samples are used across each firm's risk ladder for a given book, making position-size comparisons less noisy.
- Tradeify weekly activity is checked on complete Monday-Friday validation weeks and applies during both evaluation and funded trading. Bootstrap blocks are aligned to those weeks, so simulated weeks preserve the observed activity pattern. The model applies weekly activity as a strict eligibility screen; the official guide says an idle-time warning is issued before action, and that warning/grace process is not simulated. Books that fail weekly activity or breach the four-mini position cap are not counted as eligible evaluation passes. Microscalping is a funded payout-eligibility rule; it is checked on validation trades, and missing durations count as not qualifying for the over-10-second rule.

## The5ers — USD 20,000 Bootcamp

Modeled account structure (The5ers Bootcamp, checked 2026-11-22):

- Three sequential evaluation steps, each on its own fixed demo balance:
  - Step 1: $5,000, 6% target ($300), 5% static max loss ($250 floor at $4,750).
  - Step 2: $10,000, 6% target ($600), 5% static max loss ($500 floor at $9,500).
  - Step 3: $15,000, 6% target ($900), 5% static max loss ($750 floor at $14,250).
- No daily loss limit and no time limit during evaluation. Minimum trading days are not listed.
- Funded account: $20,000, 4% static max loss ($800 floor at $19,200), 3% daily pause (trading stops for the rest of the day; the triggering loss stands), 5% target per scale-up, 50% starting profit split.
- Payouts every 14 calendar days, modeled as 10 trading days. A payout requires **USD 300 gross profit** above the $20,000 funded balance (USD 150 to the trader at the 50% split); a smaller gain is not paid and carries forward to the next cycle. The model pays 50% of the profit and resets the balance to $20,000 after each withdrawal.
- No consistency rule for Bootcamp.
- News trading is allowed except bracketing around releases; overnight and weekend holding are allowed.
- Accounts with no activity for 30 consecutive days are closed; the model does not simulate inactivity.

Risk ladder: USD 10, 25, 50 and 100 total book risk per trade, divided equally across sleeves; the base comparison risk is USD 25. The fixed dollar risk is held constant across the three steps, so a USD 100 risk is a large fraction of the $250 Step-1 loss limit and the ladder shows that trade-off directly.

**Minimum lot sizes matter more than the ladder.** The ladder is continuous sizing and does not enforce the broker minimum. Gold X9 (Low) at 0.01 lot already risks USD 9.90 per trade at the model's frozen 1R, which is 0.20% of the $5k Step 1 and about 24% of a USD 42 four-sleeve book. The FX and index sleeves cost USD 0.38-1.67 at 0.01 lot, so the split is set by the floor, not by the percentage. [Stage sizing with real lot floors](The5ers-20K-Bootcamp/reports/stage_sizing.md) re-runs the simulation with per-sleeve `max(pct x balance, 0.01-lot risk)`, whole-lot sizing to a dollar target, and the mid-account switch to the funded book. Sized to a USD 50 target, the four-sleeve phase book risks USD 46.83 (0.94% of the $5k step) and reaches funding in **89.6%** of paths with a **5.9%** evaluation hard-breach rate; keeping Gold X9 in the balance-scaled funded book breaches the 4% floor in 26% of funded paths at 0.25%/sleeve (0.6% at 0.125%). Switching the funded stage to Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB at a USD 100 target (0.49% of $20k), simulated on the same paths, gives a **90.4%** conditional first payout and a **0.5%** funded breach ([plan_switch.csv](The5ers-20K-Bootcamp/reports/plan_switch.csv)). The continuous-sizing numbers remain useful for comparing books; the lot-floor numbers are the execution estimate.

The model does not reconstruct intratrade floating losses, exact daily-pause trigger timing, the funded 5% scale-up ladder, account fees, or symbol-specific execution conditions.

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

Risk ladder: USD 100, 250, 500 and 750 requested total book risk per trade. Overall training-score challenge and funded leaders are four-sleeve books; at a USD 100 request their minimum-micro effective risks are approximately USD 511.97 and USD 475.65. A separate two-sleeve alternative, Flash ORB + Overnight Bias ORB, is the top training-funded-score candidate within the eligible two-sleeve subset; its effective risk is approximately USD 237.63 at the USD 100 request because each sleeve is already at one micro (the model deduplicates identical effective-risk ladder points). It is not the overall training-score winner. Actual risk can exceed or differ from the requested amount. The reports show effective risk after micro sizing and maximum concurrent mini-equivalent exposure. Compare the full risk ladders in the Monte Carlo CSV and the selected-book summaries.

The NT8 MAE report measures one-micro-per-sleeve adverse-excursion stress. Same-entry-day MAEs are stacked conservatively; this is not a synchronized intraday replay. It is intended to flag possible daily-loss pauses, not predict exact breach timing.

## Moneta Funded — USD 10,000 2-Step Standard

Rules are taken from the Moneta Funded support clarification of 2026-11-21 and the
published programme rules, which the firm names as authoritative (website, client
dashboard, Help Center/FAQ, Terms & Conditions).

- Phase 1 target: **5%** (USD 500). Phase 2 target: **10%** (USD 1,000).
- Daily loss: **4%** (USD 400), or 5% with the wider drawdown option. A breach
  fails the account; Moneta does not treat the daily limit as a pause.
- Maximum loss: **8% static** (USD 800), or 10% with the wider option, measured
  from the starting balance. Not trailing.
- **Three profitable days of at least 0.5% net** (USD 50) in each phase and in
  each funded payout cycle. No consistency rule anywhere.
- Funded split **88%**, payout cycle **14 calendar days** (modeled as 10 trading
  days), balance resets to the account size after each withdrawal. No minimum
  payout amount is published.
- News: no new or held exposure from **5 minutes before to 5 minutes after**
  high-impact releases, in evaluation and funded. A position opened at least two
  hours before the event may be closed inside the window.
- Own self-developed EAs are allowed. Cross-account hedging is prohibited;
  incidental opposing positions from independent EAs on the same account are
  permitted (the earlier blanket prohibition was withdrawn).
- Overnight and weekend holding allowed. No consistency rule, no time limit.

The model runs the 4%/8% variant, so every result is the conservative case. Phase 2
is the binding constraint: 10% of profit against an 8% static budget, with Phase 1
profit reset away, so it needs 27R at a 0.37% per-trade book and only 12.5R at 0.8%.

[Stage sizing with real lot floors](Moneta-2Step-10K/reports/stage_sizing.md) sizes
each sleeve in whole 0.01 lots and models the funded-book switch. The selected plan
is Gold X9 (Low) + Overnight Bias ORB at a USD 50 target through both phases
(**USD 44.26** actual, 0.44% of the account; gold 0.02 lot), then Flash ORB +
GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB at a USD 100 target when funded
(**USD 97.68**, 0.98%), with no gold. That plan reaches funding in **99.7%** of
paths, breaches evaluation in **0.0%**, and produces a first payout in **98.8%** of
challenge starts (**99.1%** conditional on funding, **0.4%** funded breach, median
116 trading days, expected first payout **USD 249**).

Pre-built EA presets: [Set-Files/Moneta-2Step-10K](../Set-Files/Moneta-2Step-10K/README.md).

## Preset families

Gold X9 ships one EA at five `TradeFrequency` settings (strategies 1-3, 1-5, 1-7,
1-8, 1-9). The five exports are the same trade stream at different frequencies, so
they are treated as one mutually exclusive family: `strategy_family()` in the
builders keeps two presets out of the same book, and the screening applies the same
rule. `Low` is the standard preset because the frequency ladder buys R/day with
tail risk — the worst validation day runs from -9.6R (Extremely low) to -30.1R
(High) — and a prop account is bought once. Every book in this repository names the
preset it uses.

## Contract floors on the NT8 side

NT8 sizing is whole contracts. One contract on MNQ/MGC is one micro, and a micro's mean losing trade in the exports is USD 127-182, so a single micro per sleeve is about 1% of the USD 50k account and only 3.9-4.2R from the USD 2,000 trailing drawdown. The four-mini concurrent cap is therefore not the binding constraint; the drawdown is. Whole-micro rounding is already in `tradeify_position_weights` (headroom is rounded down, never below one micro), but the requested-risk ladder hides the fact that every rung lands on the same one-micro book. [Stage sizing in whole contracts](Tradeify-50K-Growth-Futures/reports/stage_sizing.md) enumerates one to ten micros per sleeve, reports the R buffer to the trail, and flags where the simulator's USD 1,250 daily-loss clip binds (0.6% of days at one micro, 3-21% above two micros). Above one micro those rows are scale illustrations, not odds.

## Recovery scenarios

Recovery simulations include no-trade controls and selected low-complexity books plus the leading challenge/funded pairs.

These are balance-recovery simulations, not payout-eligibility simulations. Tradeify weekly-activity and microscalping eligibility are reported beside each recovery book, but the recovery path does not enforce funded 35% consistency, five $150 winning days, or payout request processing. The $53,000 target therefore means the account balance reaches the payout threshold; it does not mean a payout is approved.

- The5ers: starting cushions of USD 100, 250, 500 and 750 above the static 4% funded floor; target is return to the $20,000 funded initial balance.
- Tradeify: starting cushions of USD 200, 500, 1,000 and 1,500 above the locked floor; targets are a USD 500 buffer above the floor and the USD 53,000 first-payout balance.
- Tradeify recovery uses one micro per sleeve.
- If no active book meets both the selected recovery-probability and breach-probability thresholds near the floor, no-trade is the safest modeled control.

## Time interpretation

- Monte Carlo horizon is 252 simulated trading days (approximately one trading year).
- Time-to-phase, time-to-reward and time-to-recovery fields count trading days, not calendar days.
- Tradeify's `survival_90d_conditional_approx` field means 90 trading days after funding. Its observed sample count excludes paths funded too late in the 252-day horizon to observe a full 90 trading days.

## Official rule references

Rules checked on 2026-11-22. These official pages define the modeled account versions:

- [The5ers Bootcamp program](https://the5ers.com/bootcamp/)
- [The5ers challenge program structures](https://the5ers.com/challenge-programs-bootcamp-high-stakes-hyper-growth-explained/)
- [The5ers Bootcamp $20K rules summary](https://propfirmly.com/prop-firm-challenges/the5ers-bootcamp-20k)
- [The5ers rules register](https://www.pipster.io/research/firms/the5ers)
- [Tradeify Growth Evaluation rules](https://help.tradeify.co/en/articles/10495915-growth-evaluation-accounts)
- [Tradeify Essential Trading Rules](https://help.tradeify.co/en/articles/12268167-essential-trading-rules-overview)
- [Tradeify Daily Loss Limit](https://help.tradeify.co/en/articles/10468321-rules-daily-loss-limit)
- [Tradeify Growth funded payout policy](https://help.tradeify.co/en/articles/11083796-growth-funded-account-payout-policy)
- [Tradeify consistency rule](https://help.tradeify.co/en/articles/10468320-rules-consistency-rule)
- [Tradeify trailing drawdown rules](https://help.tradeify.co/en/articles/10495897-rules-trailing-max-drawdowns)

## Important limitations

- Daily PnL is based on completed-trade exits. Intraday floating equity and exact daily-loss pause sequencing are not reconstructed.
- The5ers evaluation has no daily loss limit and fails only on each step's 5% static max loss. The funded 3% daily pause is modeled by clipping closed daily PnL at -3% of the start-of-day balance; floating-loss breaches and intraday trigger timing remain unobservable.
- Tradeify's EOD trailing drawdown is modeled from daily closes. The soft DLL is approximated by clipping closed daily losses at $1,250 initially and $2,000 after the funded balance reaches $53,000; intraday trigger timing and overshoot are not reconstructed.
- Tradeify's five $150 winning-day test uses net closed daily PnL; the 35% consistency test uses gross daily PnL before commissions, matching the published rule. Both use exit-date calendar buckets; export timestamps are not converted to the firm's 6 PM–5 PM ET trading-day boundary, so eligibility can differ from the live platform.
- Tradeify recovery candidates are restricted to weekly-activity-eligible books. The $53,000 recovery chart also requires microscalping eligibility, but it still does not enforce 35% consistency, five winning days above $150 or payout processing.
- The5ers phase transitions occur on the next simulated trading day; account activation delays and the 5% funded scale-up ladder are not simulated.
- News, hedging/correlated-product restrictions, overnight/session restrictions, broker slippage, margin and exact timezone conversion are not fully tested.
- MT5 RBE pairing uncertainty is documented in its data-quality report.
- The risk unit is a training-period realized-loss proxy, not verified initial stop risk. MT5 microscalping eligibility is also checked on the validation sample.
- These estimates are conditional on historical behavior and current modeled rules. They are not guarantees or live-deployment approval.
