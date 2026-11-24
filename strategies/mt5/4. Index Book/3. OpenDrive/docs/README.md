# OpenDrive — MT5 Expert Advisor

## Overview

**OpenDrive** is an institutional opening momentum Expert Advisor designed specifically for the Nasdaq-100 (`USTEC` / `NAS100` / `NQ`). It trades the 09:30 AM New York Cash Equity Market Open (NYSE / Nasdaq opening bell) using a directional 12 EMA breakout, 4.0 ATR initial hard stop, 3.0 ATR Chandelier trailing stop, 16:00 NY flat session exit, and institutional **News Guard** protection.

---

## Strategy Rules

- **Timeframe**: 5-Minute (M5).
- **Execution Bar**: Evaluates the 09:30 AM New York candle at its 09:35 AM close.
- **Direction**:
  - **BUY**: 09:30 Candle Close > EMA(12)
  - **SELL**: 09:30 Candle Close < EMA(12)
- **Hard Stop**: $4.0 \times \text{ATR}(14)$ (Wilder RMA).
- **Chandelier Trail**: Triggers after $+0.25 \times \text{ATR}$ profit on closed bar. Trails at $3.0 \times \text{ATR}$ behind extreme.
- **Session Close**: Closed flat at 16:00 NY. Eliminates overnight gap risk.

---

## Two Risk Sizing Modes

1. **Dynamic Volatility (`RISK_DYNAMIC_VOLATILITY`) — Prop Firms**:
   - Scales risk based on conviction distance:
     $$\text{Conviction} = \frac{|\text{Close}_{09:30} - \text{EMA}_{12}|}{\text{ATR}_{14}}$$
     - Weak ($< 0.75 \text{ ATR}$): Risk $0.33\%$
     - Moderate ($0.75 - 1.50 \text{ ATR}$): Risk $0.50\%$
     - Strong ($\ge 1.50 \text{ ATR}$): Risk $1.00\%$
   - Caps max drawdown to $\sim 11.2\%$ with Profit Factor $1.36$.
2. **Static Fixed Risk (`RISK_STATIC_FIXED`) — Live Accounts**:
   - Fixed risk percentage (default: $1.0\%$) or fixed lots on every single session.
   - Tested 2019–2026: $+\$52,811$ net profit on $\$10\text{k}$ deposit ($+528\%$), PF $1.26$, MaxDD $12.08\%$ across 2,006 trades.

---

## News Guard & Prop Firm Protection

OpenDrive embeds an institutional live economic calendar engine powered by ForexFactory (`https://nfs.faireconomy.media`):

1. **Cost-Covered Break-Even Before News (`News_Cost_Covered_BE`)**:
   - When high-impact USD news is approaching (e.g. 10:00 AM ISM, Consumer Confidence, or Fed speak), if the trade is in profit but has **not yet reached the +0.25 ATR trailing milestone**, OpenDrive automatically moves the stop loss to **entry + round-trip commissions & slippage buffer**.
   - If an adverse news spike hits, the trade is stopped out at pure break-even with zero loss. If momentum continues, the trade rides the move into the close.
2. **Trade Modification Blackout Guard (`News_Block_Modification`)**:
   - Prop firms frequently prohibit order modifications during the news window (e.g., 5 min before to 5 min after).
   - During the blackout window, trailing stop modifications are safely paused to prevent broker rejections and firm rule violations.
3. **Pre-News Flat Liquidation (`News_Flatten_Before`)**:
   - For prop firms that strictly prohibit holding open positions through red folder events, open positions are automatically liquidated flat before the release minute.
4. **Setup Requirement**:
   - Add `https://nfs.faireconomy.media` to MT5 under **Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL**.

---

## Deployable Files & Self-Sufficiency

This folder is **100% self-sufficient**. It has zero external library includes, zero external resource dependencies, and zero DLL dependencies. You can copy this folder directly to any MT5 VPS and compile:

- `OpenDrive.mq5` — Primary EA entry point (< 15 lines)
- `StrategyEngine.mqh` — Core strategy lifecycle, NY clock detection, and News Guard scheduling
- `ExecutionRuntime.mqh` — Native self-contained execution, sizing, ForexFactory JSON calendar parser, and trailing stop engine
- `ChartVisuals.mqh` — Sleek HUD floating panel (Segoe UI), vertical lines, and markers

---

## Recovery

The executor checkpoints original risk, verified position identifier, entry intent/order, tightest stop, extreme, trailing activation, news cost protection, consumed signal/day counters and pending close before broker actions. Account/server/symbol/magic scope and an exclusive lease prevent chart copies from managing the same ownership record. Two checksummed alternating files retain a preceding valid generation during an interrupted write.

MT5 restricts native file access to its file sandbox: flat `OpenDrive_<account>_<scope>.0`, `.1` and `.lock` files live in terminal **Common/Files**. This is platform runtime storage, not a compilation dependency. The EX5 still runs alone; rebuilding uses only the four source files in this folder. Tester runs use isolated in-memory execution state.

Restart attaches only the exact persisted position after opening-order and deal-volume verification. A manual/broker exit may have magic zero; complete matched entry/exit history is required before retiring ownership. Missing or partially hydrated history waits automatically through tick/timer callbacks, including with the panel disabled. An uncertain entry/close is not resubmitted blindly. Confirmed partial closes retain the desired-close intent and may submit the remaining quantity only after terminal order and position/history agreement. A missing/weaker stop is repaired from the saved ratchet; a tighter broker stop is preserved.

New entries require a hedging account for independently owned exposure. The default opposing-exposure filter blocks opposite same-symbol/equity-index positions and pending entries without treating metals/FX as index exposure. Same-direction foreign hedged positions do not become owned.

Legacy positions created before this checkpoint format are not adopted using the old magic/symbol globals: those globals lack account and position identity and cannot prove original risk/MFE. Existing protection is retained and the panel reports the hold. A pre-acknowledgement crash or contradictory/corrupt evidence also holds instead of inventing a fill. Broker permission restrictions are persisted; restarting does not bypass them. There is no unrestricted reset input.

The daily equity guard retains its existing account-equity/day-start-balance semantics; its close request affects only verified OpenDrive ownership. Model signal, ATR activation and trailing formulas are unchanged. Focused production-method fixtures and native compilation are separate from VPS restart/broker acceptance.
