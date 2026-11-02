# Opening Shock Continuation — v7 audit and source corrections

Research only. Existing MT5 and NT8 template structures retained. Native compilation, native historical fill parity, and live broker recovery have **not** been verified. Both new strategy versions default to `EnableTrading=false`.

## Clock (Central US with automatic DST)
- NQ regular cash opening: 08:30 CT = 09:30 ET.
- Signal: **09:00 CT = 10:00 ET**, after all 30 opening M1 bars 08:30–08:59 CT are completed.
- Entry: first executable quote/tick on or after 09:00 CT; historical next minute opening price in the Python simulator.
- Bracket: stop `0.30 × lagged 20-complete-session average RTH range` and target `0.20 × range`, both in the signal's direction and rounded to exchange ticks in the audited simulation.
- Exit: 60 minutes maximum after entry (usually 10:00 CT = 11:00 ET); contingency emergency flatten at **14:55 CT = 15:55 ET**.
- Only one signal / one trade per cash date. No stop/target widening. No overnight futures positions.

Tradeify regular mandatory liquidation is 16:45 ET, and holiday shortened-day deadline is 12:59 ET, as indicated by the official Tradeify permitted-hours rules. The strategy's 15:55 ET contingency is earlier than Tradeify's normal rule. Check holiday conditions, trading bans, and broker state before use.

## Source corrections
### NinjaTrader 8 (`NT8/OpeningShockContinuationNT8.cs`)
- Signal at completion of 08:59 CT M1 (`m==539`), not at completion of 09:00 M1 (`m==540`).
- Require exactly 30 contiguous opening M1 bars and 390 for a completed standard RTH daily range. Reject source gaps rather than re-marking incomplete history as ready.
- Entry only from the immediately completed 09:00 CT / 10:00 ET signal; reject stale triggers.
- Preserve historical source/execution split, dynamic stop and target, time-based flatten, original owned-execution, broker restart journal, dashboard, and execution visual structure.
- Default `EnableTrading=false`, risk-budget sizing, and stop-inclusive risk cap **even when `UseFixedSize=true`**. Fixed-size cap may be intentionally disabled in manual research, but should not be disabled on prop accounts.

### MT5 (`MT5/OpeningShock.mq5` + its three `.mqh` files)
- Preserve existing exact 08:30–09:00 CT M1 window and market entry at 09:00 CT.
- Lagged RTH daily range now rejects any missing M1 bars, incomplete RTH sessions, or noncontiguous minute timestamps. On brokers with sparse M1 ticks, this may skip more days.
- Preserve chart objects, original execution and recovery helpers, logging and existing time exits.
- Default new trades disabled. Add fixed-lot stop-inclusive risk-budget cap.

**Replacing existing code:** These files contain the same NinjaScript class and MQL helper names as the old version. Replace the old model in its own folder. Do not run old and new copies of the same class together. Do not overwrite journals or swap source files while positions are open. Always review owned broker positions and recovery state before migration.

## NQ historical audit
Input `NQminute.7z` (user data) converted with archived `nq_decode.py`/`nq_fix_roll.py`, prior-session-volume front-contract assignment. Historical dates January 2018–October 23, 2026. NQ price value $20/point per contract. Costs $20 or $60 per NQ round trip. Minute OHLC bar stop-first fill when stop/target both hit, stop-gap fill at adverse open. No tick quote/spread. Only full 390-minute cash days eligible as reference samples; first 15 prior full sessions needed. No lookahead in daily reference.

| Cost | Trades | Net profit | Avg/trade | Win rate | PF | Daily Sharpe | Closed DD |
|---|---:|---:|---:|---:|---:|---:|---:|
| $20 | 608 | $52,115 | $85.72 | 63.65% | 1.21 | 0.67 | -$24,565 |
| $60 | 608 | $27,795 | $45.72 | 63.16% | 1.11 | 0.36 | -$25,685 |

Earlier $66,666/620-trade version is **superseded as a research estimate**: it used a different RTH boundary and entry/reference construction. The clean, tick-rounded audit is the more defensible historical approximation. The 2023–2026 interval has been analyzed repeatedly, so it is *not* untouched OOS.

At $60 cost the 2018–2020 block is essentially flat (+$140 across 178 trades), and 2025–Oct 2026 is +$1,105 across 144. Year 2026 alone loses $5,355 at $20 per NQ; $60 cost makes that year still worse.

Predeclared nearby threshold test (same stop/target/60m exit, $60 cost): threshold 0.25: -$60; 0.30: +$27,795; 0.35: -$11,045. The edge has **high threshold sensitivity**. Simple end-near-extreme, last-ten-minute trend, volume acceleration and range-capping filters did not improve all blocks; none is included as a new production filter.

MNQ stop-inclusive sizing at $250 per trade and $10 per MNQ total cost: 565 trades, **-$713 overall, -$2,659 maximum closed drawdown**. This fails a $1,000 trailing-drawdown account risk threshold. 1 NQ is plainly not eligible for such an account under these stops. Slippage gaps and open-equity drawdown can be worse.

## Installation & validation sequence
1. MT5: copy the `MT5/` files together to a separate Experts folder, open `OpeningShock.mq5` in MetaEditor, compile and run M1/real-tick tester on the actual broker CFD symbol. Change only that instance's `EnableTrading` after the source compiles and is test-verified.
2. NT8: copy `NT8/OpeningShockContinuationNT8.cs` under `NinjaTrader 8/bin/Custom/Strategies/`, replacing older copy only when flat. Compile NinjaScript. Ensure correct NQ contract and ETH M1 source; chart and Strategy Analyzer must use the intended matching contract roll policy. Disable other same-class copies.
3. Export native historical trade list and compare **date, CT signal minute, side, entry, quantity, initial SL/TP, and exit time** with `opening_shock_Clean_tick-rounded_20.csv`. Historical native fills need not match simulated OHLC perfectly, but any signal discrepancy must be explained.
4. Test DST transitions, early-close and zero-quote days, disconnect while holding, restart with owned stops, partial fills, OCO linkage, rejected closes, and broker trading restrictions. Only then consider paper trading. Test in the destination prop-firm environment before risking account capital.

## Included artifacts
- `opening_shock_audit_summary.csv`: cost/stability period metrics.
- `opening_shock_features.csv`, `opening_shock_Clean_tick-rounded_20.csv`, `opening_shock_Clean_tick-rounded_60.csv`: reference and trade logs.
- `opening_shock_sensitivity_cost60.csv`, `opening_shock_mechanism_filters.csv`, `opening_shock_mnq_risk_sizing.csv`: prespecified robustness screens.
- `audit_shock.py`, `risk_and_filters.py`, `test_v7.py`: reproducible analysis/checks given `nq_rollsafe_rth.pkl` rebuilt from user-supplied archive (large archive not included).
- `test_results.txt`: static check results, **not a native compile certificate**.

**Decision:** Corrected execution structure is more defensible. The model's historical edge is weak at stressed costs and below the user's $60/trade stress screening threshold. **Not approved for real-money or prop deployment.**
