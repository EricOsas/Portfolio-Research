# Portfolio Research

Platform-separated performance research for the NT8 and MT5 strategy exports in this repository.

## Deliverables

- NT8 research pack: NT8/README.md
- MT5 research pack: MT5/README.md
- Latest build summary: reports/run_summary.json
- Analysis engine: analysis/build_equity_reports.py

Each platform directory contains individual strategy equity curves, a strategy dashboard, an all-strategy curve, a provisional recommended-portfolio curve, strategy and portfolio metrics, daily PnL, correlations, a normalized event ledger and data-quality diagnostics.

## Current export inventory

### NT8

Nine trade exports are present: Gold ORB (RBE), Vault Break, VWAP Pullback, Overnight Bias ORB, Open Drive, NQ Precision Bot, Opening-Shock Continuation, Sigma ORB and Flash ORB.

### MT5

Nine trade exports are present: Tokyo Coil, Vault Break, Overnight Bias ORB, Open Drive, NQ Precision Bot, Opening-Shock Continuation, Sigma ORB, Flash ORB and Noise Band Momentum. Gold X9 and Gold ORB (RBE) remain pending exports. VWAP Pullback is NT8-specific; Tokyo Coil, Gold X9 and Noise Band Momentum are MT5-specific.

## Methodology and limits

- NT8 uses the Strategy Analyzer Profit field as exported. It is already net of Commission; commission is not subtracted a second time.
- MT5 uses each deal's Profit + Commission + Swap, preserving the deal timestamp for cash-flow recognition.
- Equity curves begin at USD 0 and show cumulative exported net PnL using original quantities/lots. They are not normalized to a common risk unit or account balance.
- The all-strategy curve is the unscaled sum of source strategy PnL. It does not model margin, simultaneous exposure, execution conflicts, prop-firm drawdown rules or capital allocation.
- NT8 completed-trade PnL is timestamped at exit. MT5 deal cash flows can include entry commissions on entry dates. Event timing follows each platform's exported accounting.
- Timestamps are kept as exported. No timezone conversion is assumed.
- The recommended subset is a transparent screening shortlist, not parameter optimization, a guarantee or a final position-sizing plan.
- Original source exports in NT8 Trades/ and MT5 Trades/ are not modified.

## Rebuild

The GitHub Actions workflow rebuilds reports when source exports or analysis code change. To run locally:

    python -m pip install -r analysis/requirements.txt
    python analysis/build_equity_reports.py
