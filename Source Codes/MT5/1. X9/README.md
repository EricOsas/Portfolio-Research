# Gold X9 v6.3 — Project Architecture & Mechanical Reference

Welcome to the central reference manual for the **Gold X9 v6.3 (Strategy 9)** Expert Advisor. This document covers the entire system from high-level trade architecture down to order execution, management rules, lot sizing, and prop risk controls.

---

## 1. High-Level Strategy Overview

Gold X9 Strategy 9 is a pre-breakout momentum trap engine engineered for Spot Gold (`XAUUSD`). The EA operates across three concurrent time scales:

```
[H1: Fractal Detection]  ===>  [M15: Pending Stop Bursts]  ===>  [M1: Continuous Position Engine]
   (5L/5R Structural Swings)       (-0.08% Pre-Breakout Orders)       (BE, Trailing, Salvage, Hard SL)
```

1. **Fractal Signal Generation (H1)**: Locates key market inflection points using a 5-bar left / 5-bar right swing model.
2. **Order Placement (M15 Rescan)**: Evaluates pending orders strictly on M15 bar closes to enter momentum flows ahead of standard retail breakouts.
3. **Continuous Lifecycle Management (M1)**: Monitored on every tick, executing breakeven locks, trailing stops, salvage take-profit contractions, and emergency stop-losses.

---

## 2. Market Structure & Order Placement Engine

### A. Swing Point Identification (`FindSwingPoint`)
- **Fractal Timeframe**: `PERIOD_H1` (`fractalTf`).
- **Structure**: 5 bars to the left and 5 bars to the right (`fractalLeft = 5`, `fractalRight = 5`).
  - **Swing High**: The candidate bar high must be $\ge$ the highs of the 5 preceding bars and 5 succeeding bars.
  - **Swing Low**: The candidate bar low must be $\le$ the lows of the 5 preceding bars and 5 succeeding bars.
- **Search Depth**: Scans backwards up to 200 bars (`fractalMaxSearch = 200`).
- **Clearance Filter**: The detected swing point must be at least `0.02%` (`fractalMinDistPct`) away from current market Bid/Ask. This prevents placing orders inside chop or consolidation.

### B. Negative Entry Offsets ("Pre-Breakout Traps")
Standard retail strategies place Buy Stops *above* swing highs and Sell Stops *below* swing lows. Gold X9 does the opposite:
- **Inputs**: `buyEntryPct = -0.08` and `sellEntryPct = -0.08`.
- **Order Placement**:
  - $\text{Buy Stop Price} = \text{Swing High} - (0.08\% \times \text{Price})$
  - $\text{Sell Stop Price} = \text{Swing Low} + (0.08\% \times \text{Price})$
- **The Logic**: By placing the pending stop 0.08% *inside* the swing boundary, the order fills as momentum charges into the level—securing execution before breakout slippage occurs.

### C. Pending Order Deduplication & Limits
- **Pending Cap**: Maximum 3 pending orders per side (`maxPending = 3`).
- **Deduplication**: If an existing pending order is already within 5.0 points (`pendDedupDist = 5.0`) of the proposed price, the new order is ignored.
- **Pruning**: If total pending orders exceed `maxPending`, the EA automatically deletes the order with the worst entry price.
- **Expiry**: Unfilled pending orders expire automatically after 15 hours (`pendExpiryHrs = 15`).

### D. Day-Switch Rollover Guard
- **Window**: 23:30 to 00:30 server time (`DayswitchBufferMin = 30`).
- **Function**: Blocks order placement during the midnight bank rollover when spreads widen, preventing artificial fills.

---

## 3. Position Management Lifecycle

Once a pending order fills, the M1 management engine supervises the trade through four distinct stages:

```
[Favorable Move: +0.10% Price] ----> Breakeven SL locks +0.025% Profit
[Favorable Move: +0.20% Price] ----> Adaptive Trailing SL activates (0.20% dist, 1.0% cap)
[Adverse Move:   -1.00% Price] ----> Salvage Exit pulls TP down to Bid + 0.15% (Scratch / Minor Loss)
[Adverse Move:   -2.00% Price] ----> Hard Broker Stop Loss executes (Catastrophe Barrier)
```

### 1. Breakeven Lock (`beTriggerPct = 0.10%`, `beLockPct = 0.025%`)
- **Trigger**: Price moves **+0.10% of price** in profit (~$2.70 on $2,700 Gold).
- **Action**: Stop Loss moves to **+0.025% of price** past the open price (~$0.68 profit lock).

### 2. Adaptive Trailing Stop (`trailPct = 0.20%`, `trailMinProfitPct = 0.20%`, `trailMaxSLPct = 1.0%`)
- **Trigger**: Profit reaches **+0.20% of price** (~$5.40 move).
- **Action**: Trails market price at a distance of **0.20% of price**, ratcheting in increments of 0.1 points.
- **Ceiling**: Trailing stop advances up to a maximum distance of **1.00% of price** from the open price.

### 3. Salvage Exit (`salvageTriggerPct = 1.00%`, `salvageExitPct = 0.15%`)
- **Trigger**: Price drops **-1.00% of price** into drawdown (~$27.00 against trade on $2,700 Gold).
- **Action**: The EA does **not** take a full loss. It contracts the Take Profit target to:
  $$\text{New TP} = \text{Current Bid} + (0.15\% \times \text{Price})$$
- **Objective**: If Gold makes even a slight counter-trend bounce of 0.15% ($4.00), the trade exits at market. This turns what would have been a catastrophic loss into an early scratch or modest loss.

### 4. Hard Stop Loss & Virtual SL Execution
- **Hard Broker SL**: Set at **2.00% of price** ($54.00/oz on $2,700 Gold). Acts as a catastrophic backstop if price gaps across news.
- **Virtual SL**: Maintained in memory. If Bid/Ask breaches the level, `trade.PositionClose(ticket, (ulong)CurrSpread)` sends an immediate market order.

---

## 4. Dissecting Risk: Percent of Price vs. Percent of Account

To eliminate confusion between price movements and account-level risk:

### All Strategy Thresholds are **Percentages of Price**, NOT Percentages of Account:
- **`slPct = 2.0%`**: Stop distance is $2.0\% \times \text{Price}$ ($54.00/oz on $2,700 Gold).
- **`salvageTriggerPct = 1.0%`**: Salvage activates when Gold drops $1.0\% \times \text{Price}$ ($27.00/oz).
- **`tpPct = 0.7%`**: Take Profit target is $0.7\% \times \text{Price}$ ($18.90/oz).
- **`beTriggerPct = 0.1%`**: Breakeven activates when Gold advances $0.1\% \times \text{Price}$ ($2.70/oz).

### How Price Percentages Translate to Dollars & Account Risk:

| Parameter | % of Price | Gold Move ($2,700) | Dollar Impact on 0.31 Lots ($100k Account) | Dollar Impact on 0.01 Lot ($5k Account) |
| :--- | :--- | :--- | :--- | :--- |
| **Breakeven Trigger** | +0.10% | +$2.70 | +$83.70 | +$2.70 |
| **Take Profit Target**| +0.70% | +$18.90 | +$585.90 | +$18.90 |
| **Salvage Trigger** | -1.00% | -$27.00 | -$837.00 | -$27.00 |
| **Average Realized Loss** | ~-1.18% | ~-$32.00 | **-$993.64 (~0.99% of acct)** | **-$32.00 (~0.64% of acct)** |
| **Worst-Case Hard Stop** | **-2.00%** | **-$54.00** | **-$1,643.00 (1.64% of acct)** | **-$54.00 (1.08% of acct)** |

> **Key Takeaway**: The **Hard SL is -2.00% of price**, which risks **~1.64% of the account** in a worst-case gap. However, the **Salvage Exit** regularly cuts losing trades around -1.00% of price, resulting in an **average realized loss of only ~0.99% of the account** ($993.64 on $100k).

---

## 5. Lot Sizing & Non-Compounding Fixed Balance

### Sizing Modes (`Lotsizing_Method`)
```mql5
enum enum_lotsizing {
   Manual_Lotsize   = 0,  // Fixed Lots (FixedLots input)
   Tiered_Lotsizing = 1,  // Tiered Risk Meter (TieredLot 1-100)
   RiskScaleFactor  = 2   // Risk Scaling Factor (%)
};
```

### The Sizing Formula
$$\text{Lots} = \frac{\text{RiskDivisor} \times \text{EffectiveBalance} \times 0.0001 \times \text{riskWeight}}{\text{SLDollars}}$$

- $\text{EffectiveBalance}$:
  - If `InpFixedBalance = 0.0`: Uses live `AccountInfoDouble(ACCOUNT_BALANCE)` (compounding mode).
  - If `InpFixedBalance > 0.0` (e.g. `10000`): Fixes the calculation base to that exact dollar amount, preventing risk compounding.
- $\text{EffectiveBalance} \times 0.0001 = \frac{\text{Balance}}{10,000}$: Scales balance into 10k units.
- $\text{RiskDivisor}$: Set by `TieredLot` in Mode 1 (default `30.0`), or `RiskScaling` in Mode 2 (default `1.0`).
- $\text{riskWeight}$: Portfolio weighting fraction (default `0.055` = 5.5% strategy allocation).
- $\text{SLDollars} = \text{slPct} \times \text{Price} = 0.02 \times \text{Price}$ ($54/oz).

### Sizing Examples:

#### 1. Fixed $10,000 Balance Mode (`InpFixedBalance = 10000`, `TieredLot = 30`)
$$\text{Lots} = \frac{30 \times (10,000 \times 0.0001) \times 0.055}{54.00} = \frac{30 \times 1.0 \times 0.055}{54.00} = \frac{1.65}{54.00} = 0.0305 \xrightarrow{\text{step 0.01}} \mathbf{0.03\text{ lots}}$$
* Every single trade will trade exactly **0.03 lots**, regardless of account growth or drawdown.
* Worst-case 2.0% SL loss: $0.03 \times \$54.00 = \mathbf{\$16.20}$ (0.16% of $10,000).

#### 2. Default $100,000 Account (Author's Parity Setup)
$$\text{Lots} = \frac{30 \times (100,000 \times 0.0001) \times 0.055}{53.00} = \frac{16.5}{53.00} = \mathbf{0.31\text{ lots}}$$

---

## 6. Parity Benchmark Results

Validated on live broker real tick stream (`Model = 0`) against the creator's YouTube backtest:
- **Symbol**: `XAUUSD` | **Timeframe**: H1 | **Period**: 2025.01.01 – 2026.06.30 (18 Months)
- **Deposit**: $100,000 | **Leverage**: 1:500 | **Delay**: 10ms execution delay

| Metric | Creator Published Video | Parity Build (`Gold_X9_Part2_Harness`) | Parity Status |
| :--- | :--- | :--- | :--- |
| **Total Trades** | 1,440 | **1,433** | **99.51%** (-7 trades over 18 mos) |
| **Winning Trades** | 1,284 | **1,284** | **100.00% (Exact Match)** |
| **Losing Trades** | 156 | **149** | 95.51% |
| **Win Rate** | 89.17% | **89.60%** | **+0.43%** |
| **Net Profit** | $82,279.95 | **$85,375.86** | +3.7% (broker feed variance) |
| **Profit Factor** | 1.53 | **1.58** | Validated |
| **Average Win** | $184.65 | **$181.80** | Validated |
| **Average Loss** | -$992.36 | **-$993.64** | **99.87% (Exact Match)** |
| **Initial Lots** | 0.27 – 0.31 | **0.31** | Validated |

---

## 7. Input Parameters Dictionary

| Parameter | Default | Function |
| :--- | :--- | :--- |
| `InpMagic` | `647873` | Magic number identifying orders placed by Strategy 9. |
| `TradeComment` | `"Gold X9 by MrCapFree"` | Broker order comment. |
| `Lotsizing_Method`| `1 (Tiered)` | `0` = Fixed Lots, `1` = Tiered Risk Meter, `2` = Risk Scaling %. |
| `TieredLot` | `30.0` | Risk dial meter (clamped 1 to 100). |
| `FixedLots` | `0.01` | Fixed lot size used when `Lotsizing_Method = 0`. |
| `RiskScaling` | `1.0` | Sizing multiplier used when `Lotsizing_Method = 2`. |
| `InpFixedBalance`| `0.0` | Balance override for sizing (`0.0` = Live Balance, `>0` = Fixed Balance). |
| `riskWeight` | `0.055` | Portfolio weighting allocation (5.5%). |
| `fractalTf` | `PERIOD_H1` | Timeframe for swing fractal structure detection. |
| `rescanTf` | `PERIOD_M15` | Order placement evaluation cadence. |
| `exitScanTf` | `PERIOD_M1` | Position management cadence (every tick). |
| `maxPending` | `3` | Maximum pending orders kept per direction. |
| `pendExpiryHrs` | `15` | Expiration lifetime in hours for pending orders. |
| `maxPositions` | `10` | Maximum concurrent open positions. |
| `buyEntryPct` | `-0.08` | Buy Stop entry offset relative to swing high (% of price). |
| `sellEntryPct` | `-0.08` | Sell Stop entry offset relative to swing low (% of price). |
| `slPct` | `2.0` | Hard broker Stop Loss (% of price). |
| `tpPct` | `0.7` | Take Profit target (% of price). |
| `beTriggerPct` | `0.1` | Profit threshold to activate Breakeven (% of price). |
| `beLockPct` | `0.025` | Distance beyond entry locked by Breakeven (% of price). |
| `trailPct` | `0.2` | Trailing Stop distance (% of price). |
| `trailMinProfitPct`| `0.2` | Minimum profit required before trailing begins (% of price). |
| `trailMaxSLPct` | `1.0` | Maximum trailing distance ceiling (% of price). |
| `salvageTriggerPct`| `1.0` | Drawdown threshold triggering Salvage TP (% of price). |
| `salvageExitPct` | `0.15` | Take profit contraction distance above Bid (% of price). |
| `DayswitchBufferMin`| `30` | Midnight rollover buffer in minutes (23:30 to 00:30). |
| `InpEnableAuditLog`| `true` | Outputs `[AUDIT]` logs for all modifications and triggers. |

---

## 8. Build Files & Locations

- Primary EA Source: [`Part 2/Gold_X9_Part2_Harness.mq5`](file:///c:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Experts/1.%20X9R/Part%202/Gold_X9_Part2_Harness.mq5)
- Compiled Binary: [`Part 2/Gold_X9_Part2_Harness.ex5`](file:///c:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Experts/1.%20X9R/Part%202/Gold_X9_Part2_Harness.ex5)
- Tester Configuration: [`MQL5/Profiles/Tester/Gold_X9_Harness_RealTicks.ini`](file:///c:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Profiles/Tester/Gold_X9_Harness_RealTicks.ini)
