# Portfolio Research

Platform-separated performance research for the NT8 and MT5 strategy exports in this repository.

## Deliverables

- [NT8 research pack](NT8/README.md)
- [MT5 research pack](MT5/README.md)
- [Latest build summary](reports/run_summary.json)
- [Analysis engine](analysis/build_equity_reports.py)

Each platform directory contains individual strategy curves, a strategy dashboard, an all-strategy curve, an evidence-screened recommended curve, metrics, daily PnL, correlations, a normalized event ledger and data-quality diagnostics.

## Export inventory

- NT8: 9/9 exports parsed — Gold ORB (RBE), Vault Break, VWAP Pullback, Overnight Bias ORB, Open Drive, NQ Precision Bot, Opening-Shock Continuation, Sigma ORB and Flash ORB.
- MT5: 9/9 available exports parsed — Tokyo Coil, Vault Break, Overnight Bias ORB, Open Drive, NQ Precision Bot, Opening-Shock Continuation, Sigma ORB, Flash ORB and Noise Band Momentum. Gold X9 and Gold ORB (RBE) remain pending exports.
- VWAP Pullback is NT8-specific. Tokyo Coil, Gold X9 and Noise Band Momentum are MT5-specific.

## Core strategy shortlist

- **NT8:** Overnight Bias ORB, Sigma ORB, Gold ORB (RBE), Vault Break.
- **MT5:** Overnight Bias ORB, Tokyo Coil, Open Drive, Flash ORB.

These are first-pass research candidates, not live-deployment approval. Other positive strategies remain secondary candidates.

## Portfolio summary

| Platform | Portfolio | Net PnL | Max drawdown | Daily PF | Daily Sharpe |
|---|---|---:|---:|---:|---:|
| NT8 | All 9 exports | $1,461,906.64 | $52,279.64 | 1.69 | 2.69 |
| NT8 | Core 4 shortlist | $851,931.96 | $32,485.88 | 1.64 | 2.46 |
| MT5 | All 9 available exports | $1,470,380.01 | $94,936.84 | 1.57 | 2.23 |
| MT5 | Core 4 shortlist | $1,069,692.84 | $65,338.78 | 1.57 | 2.01 |

Daily PF and daily Sharpe are calculated from daily aggregated net PnL, not individual-trade PF/Sharpe. Max drawdown is in USD from the cumulative PnL curve.

## Validation

- All 9 NT8 exports parsed. The sum of each file's Profit column matches its final exported Cum. net profit.
- All 8 standard MT5 Strategy Tester reports reconcile deal Profit + Commission + Swap to final balance minus initial deposit.
- MT5 NQ Precision Bot uses its custom completed-trade ledger; the sum of Adj. Net P&L matches the report's Total Net Profit.
- Export history spans 2020 to 30 October 2026, with per-strategy start/end dates shown in the reports. These are trade-export analyses, not a new 2021-onward NQ minute-bar backtest.

## Methodology and limits

- NT8 uses the Strategy Analyzer Profit field as exported. It is already net of Commission; commission is not subtracted a second time.
- Standard MT5 reports use each deal's Profit + Commission + Swap. The NQ Precision Bot custom ledger uses Adj. Net P&L as its final net value.
- Curves begin at USD 0 and show cumulative exported net PnL using original quantities/lots. They are not normalized to a common risk unit or account balance.
- The all-strategy curve is the unscaled sum of source strategy PnL. It does not model margin, simultaneous exposure, execution conflicts, prop-firm drawdown rules or capital allocation.
- NT8 completed-trade PnL is timestamped at exit. MT5 deal cash flows can include entry commissions on entry dates. Event timing follows each platform's exported accounting.
- Timestamps are kept as exported. No timezone conversion is assumed.
- NT8 RBE trades use MGC while the other NT8 strategies use NQ. MT5 Tokyo Coil uses USDJPY; the other MT5 exports use USTEC. Dollar PnL is therefore not a risk-normalized cross-strategy comparison.
- The recommended subset is a transparent screening shortlist, not parameter optimization, a guarantee or a final position-sizing plan.
- Original source exports in NT8 Trades/ and MT5 Trades/ are not modified.

## Rebuild

GitHub Actions rebuilds reports when source exports or analysis code change. To run locally:

    python -m pip install -r analysis/requirements.txt
    python analysis/build_equity_reports.py

## Equity curves

### NT8

![NT8 individual strategy dashboard](NT8/charts/individual/strategy_dashboard.png)

- [All 9 NT8 strategies combined](NT8/charts/portfolios/all_strategies.png)
- [NT8 core shortlist](NT8/charts/portfolios/recommended_strategies.png)
- [All individual NT8 curves](NT8/charts/individual/)

### MT5

![MT5 individual strategy dashboard](MT5/charts/individual/strategy_dashboard.png)

- [All 9 available MT5 strategies combined](MT5/charts/portfolios/all_strategies.png)
- [MT5 core shortlist](MT5/charts/portfolios/recommended_strategies.png)
- [All individual MT5 curves](MT5/charts/individual/)
