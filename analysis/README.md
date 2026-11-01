# Analysis engines

## 1. Raw export analysis

`build_equity_reports.py` reads NT8 and MT5 source exports, normalizes realized PnL events, writes platform-separated metrics and charts, and produces a transparent export-level screening shortlist.

- NT8 Profit is used as exported; it is already net of Commission.
- MT5 standard Strategy Tester reports use deal Profit + Commission + Swap.
- NQ Precision Bot uses its custom completed-trade ledger.

## 2. Normalized live and prop-firm analysis

`build_live_and_prop_reports.py` creates:

- `Normalized-Live/NT8`: one exported contract equivalent per strategy, no starting balance.
- `Normalized-Live/MT5`: fixed USD 100 risk proxy per completed trade, no starting balance.
- `Prop-Firms/FTMO-10K-2Step-CFD`: FTMO $10k 2-Step CFD account simulation.
- `Prop-Firms/Tradeify-50K-Growth-Futures`: Tradeify $50k Growth futures account simulation.

Methodology:
- Chronological 60/40 train/validation split. Each sleeve's realized-loss R unit is calibrated on training data and held fixed in validation; book selection uses training data and Monte Carlo uses validation data.
- All one-to-four-sleeve combinations are screened on the normalized daily series.
- 5,000 Monte Carlo paths, five-day blocks aligned to Monday-Friday validation weeks, 252-trading-day horizon.
- Tradeify futures sizing uses whole-micro increments, at least one micro per active sleeve, and a four-mini concurrent exposure cap.
- Tradeify minimum activity is checked on complete validation weeks; Monte Carlo resamples complete calendar-week blocks. Evaluation pass rates exclude books that fail minimum activity or position-limit eligibility. Tradeify includes a separate NT8 MAE / soft-DLL stress report. It is not an intraday equity replay.
- Recovery scenarios include no-trade controls and model the probability of reaching a buffer or payout target before breaching the account floor.

## Scope controls

The engines intentionally do not re-optimize strategy parameters, redesign strategy logic, change native stops/targets/entries/exits, add protective stops, or add assumed costs on top of source costs. They do not convert timestamps between platform timezones. Prop-firm rule models are separate from native strategy execution.

## Important limitations

- Trade exports are not a tick-level replay or an independent NQ minute-bar backtest.
- MT5 RBE has no position ID; entry/exit legs use exact-volume matching where possible and FIFO fallback.
- Realized-loss risk units are training-sample proxies, not verified initial stop risk.
- Intraday floating losses, broker margin, news restrictions, correlated-product hedging, and instrument-specific lot minima are not fully reconstructed.
- Read the README and account_rules.json inside each output directory before using its estimates.
