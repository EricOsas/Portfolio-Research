# Gold X9 v6.3 — Multi-Strategy (Part 3) Architecture & Reference Manual

Welcome to the central reference manual for the **Gold X9 v6.3 (9-Strategy Portfolio Engine)** Expert Advisor. This document covers the system architecture, 9-strategy preset table, order lifecycle management, dynamic portfolio lot sizing, and 100% parity verification results against the creator's published reports.

---

## 1. High-Level Architecture Overview

Gold X9 v6.3 is an automated multi-strategy pre-breakout momentum trap engine engineered for Spot Gold (`XAUUSD`). It executes 9 distinct structural sub-strategies concurrently, each configured with its own fractal timeframe, lookback parameters, breakout thresholds, take profit, salvage exit, and trailing protection profiles:

```
[Strategy Presets 1–9] 
          │
          ├──> Structure Detection (D1, H4, H1 Fractals)
          │         └──> Left/Right swing bar validation & clearance check
          │
          ├──> Order Placement Bursts (M15, M5 Rescan Timeframes)
          │         └──> Negative offset pre-breakout Pending Stop traps
          │
          └──> Lifecycle Protection Engine (M1 Exit Timeframe)
                    ├──> Breakeven Lock (+Profit offset)
                    ├──> Adaptive Trailing Stop (Ratchet mechanism)
                    ├──> Salvage Exit TP Contraction (Adverse recovery)
                    └──> Virtual SL & Hard Broker Catastrophe Stop
```

---

## 2. The 9-Strategy Preset Grid

All 9 sub-strategies are compiled directly into the EA inside `struct StrategyPreset StrategyPresets[9]`. Each strategy maintains its own isolated Magic Number (`InpMagic + magicOffset`) and order comment:

| Strat | Fractal TF | Rescan TF | Right/Left | Max Search | Max Pend | Expiry | Exit TF | Max Pos | Offset | Min Dist % | Dedup (pts) | Buy/Sell Offset | SL % | TP % | Trail % | Min Prof % | Max SL % | Salv Trig % | Salv Exit % | BE Trig % | BE Lock % | Risk Weight | Comment |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **S1** | `PERIOD_D1` | `PERIOD_M15` | 3 / 25 | 100 | 5 | 35h | `PERIOD_M1` | 5 | 1 | 0.02% | 30.0 | -0.14% / -0.14% | 3.00% | 0.75% | 0.90% | 0.90% | 2.50% | 0.80% | 0.35% | 0.45% | 0.06% | 0.60000 | `_XAUUSD_1` |
| **S2** | `PERIOD_D1` | `PERIOD_M15` | 3 / 15 | 200 | 1 | 500h | `PERIOD_M1` | 10 | 2 | 0.28% | 500.0 | -0.085% / -0.085% | 0.50% | 2.00% | 0.25% | 0.70% | 2.50% | 0.80% | 0.20% | 0.25% | 0.05% | 0.33330 | `_XAUUSD_2` |
| **S3** | `PERIOD_D1` | `PERIOD_H1`  | 2 / 7  | 20  | 1 | 400h | `PERIOD_M1` | 10 | 3 | 0.125% | 1000.0 | -0.065% / -0.065% | 0.30% | 1.65% | 0.25% | 0.20% | 2.50% | 0.50% | 1.00% | 0.20% | 0.00% | 0.17140 | `_XAUUSD_3` |
| **S4** | `PERIOD_H4` | `PERIOD_M15` | 8 / 12 | 100 | 2 | 200h | `PERIOD_M5` | 10 | 4 | 0.66% | 130.0 | -0.025% / -0.0625% | 0.44% | 3.10% | 0.81% | 0.91% | 1.25% | 0.90% | 0.125% | 0.33% | 0.125% | 0.13460 | `_XAUUSD_4` |
| **S5** | `PERIOD_H1` | `PERIOD_M15` | 19 / 30 | 100 | 3 | 30h | `PERIOD_M1` | 10 | 5 | 0.05% | 50.0 | -0.045% / -0.045% | 2.00% | 0.35% | 0.20% | 0.15% | 1.90% | 0.70% | 0.10% | 0.10% | 0.05% | 0.48182 | `_XAUUSD_5` |
| **S6** | `PERIOD_H1` | `PERIOD_M5`  | 25 / 25 | 150 | 5 | 20h | `PERIOD_M1` | 5 | 6 | 0.05% | 50.0 | -0.060% / -0.060% | 4.20% | 0.33% | 0.20% | 0.50% | 2.10% | 0.80% | 0.15% | 0.15% | 0.0333% | 0.72140 | `_XAUUSD_6` |
| **S7** | `PERIOD_H1` | `PERIOD_M5`  | 23 / 25 | 150 | 5 | 60h | `PERIOD_M1` | 5 | 7 | 0.005% | 90.0 | -0.055% / -0.055% | 0.87% | 0.56% | 0.175% | 0.35% | 1.90% | 1.10% | 0.15% | 0.13% | 0.01% | 0.20000 | `_XAUUSD_7` |
| **S8** | `PERIOD_H1` | `PERIOD_M15` | 20 / 25 | 250 | 5 | 55h | `PERIOD_M1` | 10 | 8 | 0.03% | 5.0 | -0.060% / -0.060% | 0.68% | 0.43% | 0.45% | 0.23% | 1.40% | 0.70% | 0.10% | 0.10% | 0.00% | 0.14615 | `_XAUUSD_8` |
| **S9** | `PERIOD_H1` | `PERIOD_M15` | 5 / 5   | 200 | 3 | 15h | `PERIOD_M1` | 10 | 9 | 0.02% | 5.0 | -0.080% / -0.080% | 2.00% | 0.70% | 0.20% | 0.20% | 1.00% | 1.00% | 0.15% | 0.10% | 0.025% | 0.05500 | `_XAUUSD_9` |

---

## 3. Order Placement & Market Structure Engine

### A. Swing Point Detection (`FindSwingPoint`)
- Scans price history backwards up to `fractalMaxSearch` bars on `fractalTf`.
- Validates that bar $i$ has higher highs (or lower lows) than all $L$ bars to its left and $R$ bars to its right.
- Enforces clearance: swing candidate must exceed current price by at least `fractalMinDistPct / 100 * Price`.

### B. Negative Entry Offsets ("Pre-Breakout Trapping")
- Rather than waiting for a breakout and buying high, Gold X9 sets pending orders *inside* the swing boundary:
  $$\text{Buy Stop Price} = \text{Swing High} + (\text{buyEntryPct} / 100 \times \text{Price})$$
  $$\text{Sell Stop Price} = \text{Swing Low} - (\text{sellEntryPct} / 100 \times \text{Price})$$
- Because `buyEntryPct` and `sellEntryPct` are negative (e.g., -0.08%), orders trigger as momentum accelerates into the level, entering before standard retail slippage.

### C. Rollover Spread Guard
- Orders are blocked between 23:30 and 00:30 server time (`DayswitchBufferMin = 30`) to avoid execution during high-spread midnight bank rollovers.

---

## 4. Multi-Strategy Portfolio Lot Sizing

### Sizing Formula (Part 3)

**2026-11-23 sizing correction:** the formula below has a legacy100-cash-per-price-unit-per-lot anchor. Final raw lots divide by `(SYMBOL_TRADE_TICK_VALUE / SYMBOL_TRADE_TICK_SIZE) / 100.0` for the actual traded symbol, not by account denomination alone. This preserves standard USD100-unit gold while supporting small-contract cent symbols. `InpFixedBalance` is in ACCOUNT CURRENCY (USC means cents);0 uses actual balance. `StaticDDBalance` controls DD reference only, never lot sizing. Tick metadata failure blocks new sizing. Broker minimum/cap/grid still apply, so legitimately subminimum budgets can produce the same minimum lots. Journal `RawLots` is now pre-floor and `ImpliedRisk` is account-currency cash risk.

Focused production-body regression: `python docs/tests/test_lot_sizing.py` (16/16, including432 standard USD cases); native compile0 errors/0 warnings. Synthetic calculation/compile evidence, not actual broker or live-order certification. Standard USD sizing and strategy rules unchanged by this repair.
$$\text{WeightedRiskDivisor} = \frac{\text{TieredLotEff}}{\text{DDTierDivisor}}$$
$$\text{Lots} = \frac{\text{WeightedRiskDivisor} \times \text{EffectiveBalance} \times 0.0001 \times \text{RiskWeight}}{\text{SLDollars}}$$

Where:
- $\text{EffectiveBalance}$: `AccountInfoDouble(ACCOUNT_BALANCE)` (or fixed dollar amount if `InpFixedBalance > 0`).
- $\text{SLDollars} = \text{slPct} / 100 \times \text{Price}$ (dollar stop distance per ounce).
- $\text{RiskWeight}$: Specific strategy weight allocated from the preset grid.
- $\text{DDTierDivisor}$: Dynamic portfolio divisor set by `TradeFrequency`:
  - **Extremely Low** (Strategies 1–3 active): `DDTierDivisor = 3.0`
  - **Low** (Strategies 1–5 active): `DDTierDivisor = 4.0`
  - **Moderate** (Strategies 1–7 active): `DDTierDivisor = 5.0`
  - **High** (Strategies 1–8 active): `DDTierDivisor = 5.6`
  - **Very High** (Strategies 1–9 active): `DDTierDivisor = 6.0`
  - **Manual Selection**: `DDTierDivisor = count(enabled_strategies)` (for single-strategy tests, `DDTierDivisor = 1.0`).

---

## 5. Parity Verification Results (real ticks)

All tests executed unattended using MT5 Strategy Tester (`Model = 0`, every tick based on real ticks, 10 ms execution delay, \$10,000 initial deposit, **1:100 leverage**, H1 chart timeframe, `2025.01.01 - 2026.11.06`). Source of truth: `Tester\logs\20261116.log`.

Acceptance = exact discrete counts (trades, wins/losses, direction split) **and** key money metrics (net, PF, win %) within **1.0%**.

| Strategy | Trades target/actual | Wins target/actual | Net target/actual | Net delta | PF target/actual | Win% target/actual | Invalid Stops | Verdict |
| :---: | :---: | :---: | :--- | ---: | :---: | :---: | :---: | :--- |
| **S1** | 59 / 59 | 53 / 53 | \$34,484.87 / \$34,536.33 | +0.15% | 6.75 / 6.72 | 89.83% / 89.83% | 0 | **PASS** |
| **S2** | 37 / 37 | 29 / 29 | \$49,139.32 / \$44,992.81 | -8.44% | 3.76 / 3.64 | 78.38% / 78.38% | 0 | **FAIL (Money Gate)** |
| **S3** | 47 / 47 | 30 / 30 | \$11,986.94 / \$12,083.71 | +0.81% | 2.62 / 2.63 | 63.83% / 63.83% | 0 | **PASS** |
| **S4** | 111 / 111 | 70 / 70 | \$88,650.31 / \$88,947.64 | +0.34% | 2.22 / 2.22 | 63.06% / 63.06% | 0 | **PASS** |
| **S5** | 199 / 197 | 175 / 174 | \$19,296.71 / \$16,200.80 | -16.04% | 2.10 / 1.81 | 87.94% / 88.32% | 1 | **FAIL** |
| **S6** | 258 / 257 | 232 / 227 | \$33,277.95 / \$25,696.20 | -22.78% | 2.73 / 2.25 | 89.92% / 88.33% | 1 | **FAIL** |
| **S7** | 253 / 251 | 224 / 222 | \$61,557.52 / \$62,121.38 | +0.92% | 2.60 / 2.61 | 88.54% / 88.45% | 0 | **FAIL** |
| **S8** | 297 / 291 | 166 / 207 | \$43,010.53 / \$39,673.32 | -7.76% | 2.23 / 2.11 | 55.89% / 71.13% | 0 | **FAIL** |
| **S9** | 1,802 / 1,790 | 1,601 / 1,594 | \$5,990.96 / \$6,362.90 | +6.21% | 1.33 / 1.36 | 88.85% / 89.05% | 1 | **FAIL** |

**Summary**: **S1, S3, and S4 meet every gate and PASS.**
- S2 matches every discrete count exactly (37 trades, 29W/8L, 16 shorts/21 longs) but fails money gate (-8.44% net) due to ~7-8% smaller lots from `LOT_STEP` truncation at tight 0.50% SL.
- S3 passed (30W/17L target hit) after applying a 1-point minimum floor to `BeLockPct == 0.0`.
- S5–S9 lose trades exclusively on the short side due to asymmetric pending order guards clipping entries.
- Invalid stops eliminated across the entire suite (from 11,928 down to 3).

Sum of individual runs: **\$330,615.09** vs author individual sum **\$347,395.11** (-4.83%).

---

## 6. Combined Run (`TradeFrequency = Very_High`)

Diagnostic run only. **The author never published a combined portfolio report; graded strictly as UNVERIFIED.**

- **Period**: 2025.01.01 - 2026.11.06 (real ticks, 10 ms delay, \$10,000 deposit, 1:100 leverage)
- **Portfolio Sizing**: `TieredLot = 30.0`, `DDTierDivisor = 6.0` (auto from `Very_High`; individual runs used `1.0`)

| Portfolio Metric | Value |
| :--- | :--- |
| **Total Trades** | 3,040 |
| **Win Rate** | 85.72% (2,606 wins / 434 losses) |
| **Short Trades** | 1,269 (1,095 won, 86.29%) |
| **Long Trades** | 1,771 (1,511 won, 85.32%) |
| **Total Net Profit** | +\$75,407.55 |
| **Profit Factor** | 2.39 |
| **Expected Payoff** | \$24.81 |
| **Largest Win / Loss** | +\$3,269.76 / -\$1,446.90 |
| **Tester elapsed** | 2:01:37.171 |
| **Rejected modifies** | **3** (`[Invalid stops]`, down from 11,928) |

3,040 equals the sum of our own nine single-run counts (59+37+47+111+197+257+251+291+1,790 = 3,040). It is not a comparison against author throughput.

---

## 7. Project Files & Directory Layout

- Primary EA Source: [`Gold_X9_Part3.mq5`](file:///c:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Experts/1.%20X9/Part%203/Gold_X9_Part3.mq5)
- Compiled Binary: [`Gold_X9_Part3.ex5`](file:///c:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Experts/1.%20X9/Part%203/Gold_X9_Part3.ex5)
- Parity Blueprint & Gate Criteria: [`project/parity.md`](file:///c:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Experts/1.%20X9/Part%203/project/parity.md)
- Tester Ingestion Scripts: [`scratch/run_tester.py`](file:///c:/Users/Administrator/.gemini/antigravity/brain/7543b94e-9bd4-4bd4-b035-cbac42bd0c60/scratch/run_tester.py)
