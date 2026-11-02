# OpenDrive — Nasdaq 09:30 AM Cash Open Drive

## System Overview & Executive Summary

**OpenDrive** is an institutional opening-drive momentum strategy engineered specifically for the Nasdaq-100 index (`NQ` / `MNQ` futures, and `USTEC` / `NAS100` CFDs). 

The strategy exploits the structural institutional order imbalance and liquidity expansion that occurs at the **09:30 AM New York Cash Equity Market Open (NYSE / Nasdaq opening bell)**. 

Unlike currency or metal markets where the 09:30 NY open exhibits chop or mean-reversion (leading to negative expectancy on Gold), the Nasdaq-100 exhibits persistent trend continuation during the first 5 minutes of cash equity trading.

---

## Strategy Specification

| Component | Rule |
| :--- | :--- |
| **Asset** | Nasdaq-100 (`USTEC`, `NAS100`, `NQ`, `MNQ`) |
| **Signal Timeframe** | 5-Minute (M5) |
| **Evaluation Candle** | The 5-minute candle opening at **09:30 AM New York** and closing at **09:35 AM New York**. |
| **Direction Logic** | - **BUY**: 09:30 Candle Close > EMA(12)<br>- **SELL**: 09:30 Candle Close < EMA(12) |
| **Entry Timing** | Market order executed at the open of the next bar (**09:35 AM New York**). |
| **Trade Frequency** | Every single trading day (~250 trades/year). Zero cherry-picking filters. |
| **Initial Hard Stop** | Entry $\pm 4.0 \times \text{ATR}(14)$ (Wilder RMA). Absorbs opening whip. |
| **Trailing Stop** | **Chandelier Trail**: Activates once a closed candle registers $+0.25 \times \text{ATR}$ in profit. Trails at $3.0 \times \text{ATR}$ behind session extreme. |
| **Session Liquidation** | **Flat at 16:00 NY**: Liquidates open position at the cash close (4:00 PM Eastern). Never holds overnight. |
| **News Guard** | Institutional ForexFactory live calendar filter with pre-news cost-covered BE, modification freezing, and pre-news flattening. |

---

## Two Distinct Risk Modes

### 1. Dynamic Strength Scaling (`RISK_DYNAMIC_VOLATILITY`) — Prop Firm Profile
Designed for funded evaluation accounts (Apex, Topstep, FTMO, FundingPips) where drawdown protection and equity smoothing are paramount. 
Sizing dynamically scales by breakout conviction:
$$\text{Conviction Distance} = \frac{|\text{Close}_{09:30} - \text{EMA}_{12}|}{\text{ATR}_{14}}$$

- **Weak Conviction** ($< 0.75 \text{ ATR}$): Risk **0.33%** (low exposure when the open is indecisive).
- **Moderate Conviction** ($0.75 - 1.50 \text{ ATR}$): Risk **0.50%**.
- **Strong Conviction** ($\ge 1.50 \text{ ATR}$): Risk **1.00%** (full risk on clear institutional open-drives).

**Key Performance Impact**: Drops maximum drawdown to **11.2%**, boosts Profit Factor to **1.36**, and preserves funding rules.

### 2. Static Fixed Risk (`RISK_STATIC_FIXED`) — Live Account Profile
Designed for private live compounding accounts where consistent capital utilization across all market cycles is preferred.
- Risks a fixed user-defined percentage (default: **1.0%** of account balance) on every single trade.
- **Verified MT5 Backtest (2019–2026 on ICMarkets USTEC)**:
  - Total Net Profit: **+\$52,811** on \$10,000 initial balance (+528%)
  - Profit Factor: **1.26**
  - Max Equity Drawdown: **12.08%**
  - Total Trades: **2,006** (every single year positive)

---

## News Guard & Economic Calendar Engine

OpenDrive features a native ForexFactory economic calendar engine running in real time:

1. **Pre-News Cost-Covered BE**: If a high-impact USD economic release occurs while a trade is open, OpenDrive automatically ratchets the stop to cost-covered break-even (entry $\pm$ commissions and slippage) if the trade is in profit, even if the +0.25 ATR trailing milestone has not yet triggered.
2. **Trade Modification Blackout**: Freezes all trailing stop modifications during the news blackout window to comply with prop firm regulations against trade modifications during high-impact news.
3. **Pre-News Flat Liquidation**: For firms strictly forbidding open positions during news, positions are liquidated before the release minute.

---

## File Architecture

Both MT5 and NT8 implementations follow the Index Book standard:

### MetaTrader 5 (`Experts/4. Index Book/4. SessionOpenMomentum/`)
- `OpenDrive.mq5` — Thin EA wrapper
- `StrategyEngine.mqh` — Core engine lifecycle, inputs, and timer
- `ExecutionRuntime.mqh` — Self-contained native execution, sizing, news engine, and trailing stop
- `ChartVisuals.mqh` — Dark glass floating HUD panel (Segoe UI) and chart session lines

### NinjaTrader 8 (`bin/Custom/Strategies/7. OpenDrive_NT/`)
- `OpenDriveNT8.cs` — Consolidated standalone NinjaScript strategy with Direct2D ModelDashboard HUD
