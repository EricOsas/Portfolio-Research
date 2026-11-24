# NT8 transfer validation

Use the instrument's ETH template and a primary chart covering the same dates as the Python ledger. The strategy itself adds native Daily and 1-minute series.

Daily callbacks queue entries and timed exits; the next 1-minute execution event submits them. This prevents market orders during the daily-session break. Live-chart historical processing draws and audits setups but cannot create orders or virtual positions; only Strategy Analyzer trades historical bars. `ImmediatelySubmit` therefore starts TuesdayTurnaround flat and waits for a fresh realtime Monday signal. `WaitUntilFlatSynchronizeAccount` can flatten aggregate account exposure and is unsuitable when another strategy owns that position.

Run 16 Strategy Analyzer cases: ES, NQ, MES, MNQ crossed with T1-T4. Use `FixedOneContract` for parity. Do not include 2024-2026 until the frozen gate is explicitly opened. Save a unique CSV path per case.

Build `2026-10-09p` defaults to `StartBehavior.ImmediatelySubmit`. Live-chart historical processing remains order-suppressed; transition clears pending signals and remaps owned realtime order references. It is standalone from ORB_NT and uses completed native Daily bars for signals and T3/T4 session counting. The minute-built Monday preview cannot submit an order. Native Exit on session close remains disabled. Optional Tradeify self-close uses `EnableFixedSelfClose = true` and `FixedSelfCloseTime = 164455`.

Baseline parity runs must set `News folders = Off`. News-filter Analyzer runs must supply the UTC historical CSV (`yyyy-MM-dd,HH:mm,CUR,impact,title`); enabled news without covered data fails closed for entries. Defaults: USD red-only; total 10 minutes (5 before/5 after); cancel pending on; ordinary trailing freeze on; cost-covered news BE on; flatten off. News BE/flatten require a selected event in its pre-event window. Total 5 minutes means exactly 2m30s on each side.

Use fresh CSV paths under `C:\Users\Administrator\Documents\Strategies\results\tuesday_turnaround_nt8_native_parity`:

- Base: `ASSET_T1_BASE.csv` through `ASSET_T4_BASE.csv`, fixed self-close disabled.
- Tradeify: `ASSET_T1_FIXED.csv` and `ASSET_T2_FIXED.csv`, fixed self-close enabled.
- Assets: ES, NQ, MES, MNQ.

Use identical date windows within each asset, `FixedOneContract`, High fill resolution on the strategy's internal 1-minute series, and the instrument's ETH template. Do not reuse old CSVs because build J has a new OHLC audit schema.

With the toggle disabled, T1/T2 use the strategy-owned first-session close. T3/T4 use strategy-owned exits: T3 on trading session four; T4 after a completed close-rule signal at the next tradable session open, or at the fourth-session deadline. Holiday weeks count available trading sessions rather than calendar weekdays. T3/T4 remain unsuitable for Tradeify because they hold across sessions.

Expected rule-qualified signal counts in the current executable OOS ledger:

| Asset | T1 | T2 | T3 | T4 |
|---|---:|---:|---:|---:|
| ES | 36 | 44 | 93 | 93 |
| NQ | 55 | 43 | 100 | 100 |
| MES | 12 | 12 | 32 | 32 |
| MNQ | 17 | 16 | 38 | 38 |

The final ledger row is excluded from parity because the Python run cannot prove a future exit session. Date coverage must match before comparing counts.

First chart checks:

| Asset | Monday | Monday close | Python entry | Python timed exit |
|---|---|---:|---|---|
| ES | 2018-02-05 | 2620.50 | 2018-02-05 18:01 @ 2624.00 | 2018-02-06 17:00 @ 2684.50 |
| ES | 2018-03-19 | 2722.75 | 2018-03-19 18:01 @ 2721.50 | 2018-03-20 17:00 @ 2723.75 |
| NQ | 2018-02-05 | 6467.25 | 2018-02-05 18:01 @ 6473.00 | 2018-02-06 17:00 @ 6635.75 |
| NQ | 2018-03-19 | 6915.75 | 2018-03-19 18:01 @ 6911.75 | 2018-03-20 17:00 @ 6917.75 |
| MES | 2022-02-21 | 4290.00 | 2022-02-22 00:01 @ 4276.50 | 2022-02-22 17:00 @ 4312.00 |
| MES | 2022-03-07 | 4186.25 | 2022-03-07 18:01 @ 4186.75 | 2022-03-08 17:00 @ 4153.00 |
| MNQ | 2022-02-21 | 13734.25 | 2022-02-22 00:01 @ 13690.50 | 2022-02-22 17:00 @ 13921.00 |
| MNQ | 2022-03-07 | 13270.50 | 2022-03-07 18:01 @ 13282.50 | 2022-03-08 17:00 @ 13199.75 |

The MES/MNQ midnight entries reflect missing evening data; NT8 must also use its first available minute. Compare signal/source-close rows first. Native market-order fills may differ from Python's close benchmark because a completed close cannot be traded retroactively. The CSV records both values so this difference is visible.
