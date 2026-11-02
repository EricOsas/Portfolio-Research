# OpenDrive NT8

## Overview

**OpenDriveNT8** is the native NinjaTrader 8 port of the **OpenDrive** institutional cash open momentum strategy. It is engineered to trade the **09:30 AM New York Cash Equity Market Open** on the Nasdaq-100 futures (`NQ` / `MNQ`).

---

## Strategy Rules

- **Execution Chart**: 5-Minute (M5) bars on `NQ` or `MNQ` (CME Index Futures ETH / RTH).
- **Signal Candle**: The 5-minute candle opening at 09:30 AM Eastern (NY) and closing at 09:35 AM Eastern.
- **Direction**:
  - **LONG**: 09:30 candle close strictly greater than 12 EMA.
  - **SHORT**: 09:30 candle close strictly less than 12 EMA.
- **Entry**: Market order at the open of 09:35 AM Eastern.
- **Hard Stop**: $4.0 \times \text{ATR}(14)$ from entry price.
- **Chandelier Trailing Stop**: Activates once a 5-minute bar closes $\ge +0.25 \times \text{ATR}$ in profit. Trails at $3.0 \times \text{ATR}$ behind session extreme.
- **Session Liquidation**: Flat at **16:00 Eastern** (US market close). Eliminates overnight margin and gap risk.

---

## Sizing Modes

1. **Dynamic Volatility (Prop Firms)**:
   - Sizing dynamically scales based on breakout conviction:
     $$\text{Conviction Distance} = \frac{|\text{Close}_{09:30} - \text{EMA}_{12}|}{\text{ATR}_{14}}$$
     - Weak ($< 0.75 \text{ ATR}$): Risk $33\%$ of dollar budget.
     - Moderate ($0.75 - 1.50 \text{ ATR}$): Risk $50\%$ of dollar budget.
     - Strong ($\ge 1.50 \text{ ATR}$): Risk $100\%$ of dollar budget.
   - Smooths drawdowns and protects evaluation / funded accounts.

2. **Static Fixed Risk (Live Accounts)**:
   - Fixed dollar risk budget per trade or fixed contract quantity (`UseFixedContracts`).

---

## News Guard & Prop Firm Protection

OpenDriveNT8 embeds a native ForexFactory economic calendar client:
1. **Cost-Covered BE Before News (`NewsCostCoveredBE`)**:
   - If high-impact USD news is approaching and the position is in profit, the stop is proactively ratcheted to entry + round-trip commissions and slippage before the release, even if the +0.25 ATR trailing milestone has not yet been achieved.
2. **Trade Modification Blackout Guard (`NewsBlockModifications`)**:
   - Freezes stop order modification during the blackout window to strictly abide by prop firm rules prohibiting order edits during high-impact news releases.
3. **Pre-News Flat Liquidation (`NewsFlattenBefore`)**:
   - Closes position flat before the release minute for prop firms with strict no-news-holding policies.

---

## Deployable Files

- Source file: `Strategies/7. OpenDrive_NT/OpenDriveNT8.cs`
- Compiled into: `NinjaTrader.Custom.dll`

---

## Recovery

Live entries retain native managed execution. Before submission the strategy commits a unique owned intent to an exclusive, checksummed account/provider/exact-contract journal in `Documents/NinjaTrader 8/OpenDrive/recovery`; atomic replacement retains `.previous`. Original risk, entry fills, consumed signal day, extreme, trailing/cost-covered stage, stop and broker restriction survive restart. Historical and Analyzer calculations do not write or adopt this live state.

A replacement instance binds exact saved broker orders without submitting, changing or cancelling during handoff. It then manages that position through the account API because assigning a local ledger cannot restore NinjaTrader's native `Strategy.Position`. Recovered new trades use the same transport. One-second retries continue without market ticks. Unknown acknowledgements, missing snapshots, delayed executions or account/owned quantity disagreement pause new and quantity-dependent requests, retaining broker protection. Pending closes prevent new protection or trailing requests; closure settles only through exact owned executions.

Broker permission/liquidation-only rejections persist a restriction before faulting; restarting does not silently clear it or trigger a guessed corrective close. The shared-contract guard blocks opposing or uncovered foreign exposure while allowing independently owned same-direction exposure.

If a saved limit entry has no fills, re-enabling during the same New York session rebuilds it from the original signal bar and stop with the current risk amount. The original conviction multiplier still applies. A surviving order with a changed price or quantity is cancelled first; the replacement waits for exact cancellation and execution reconciliation. The replacement remains a passive limit, preserves the consumed trade count and does not alter a filled position. Missing signal history, missing quotes, news restrictions or unresolved broker state keep replacement pending; no replacement occurs after the configured flattening cutoff or on a later date. Check this path with `python validation/test_pending_limit_resume.py`; it exercises extracted production methods with broker calls stubbed, not a broker connection.

**Migration limit:** positions opened by an older generic `OD_Long`/`OD_Short`/`OD_SL` build have no durable owner/risk/trailing checkpoint. This build does not adopt or reset them. Existing generic working orders cause a recovery hold; their protection remains untouched. Missing external-close ownership evidence also remains pending rather than inventing a fill or realized PnL. Do not delete an unsettled journal to bypass this hold.

Validation: `tests/test_owned_recovery.py` executes the production fill/identity/state methods and checks read-only handoff boundaries. Installed-assembly compilation is a separate gate from VPS restart, disconnect and broker acceptance; no live acceptance is implied.
