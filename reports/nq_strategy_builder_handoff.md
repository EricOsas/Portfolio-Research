# NQ minute data: strategy-builder handoff

**Status date:** 2026-11-01  
**Dataset ID:** `NQ_M1_LAST_CONTINUOUS_2021_2026_V1`  
**Purpose:** provide the website/strategy-builder agent with the current data scope, safe integration rules, and the remaining validation work.

## Executive conclusion

The decoded NQ minute data is suitable now for historical charting, NQ strategy prototyping, and research replays. It is **not yet an execution-validated backtest feed**: only Last-trade bars have been stitched into the continuous series; Bid/Ask streams are not yet decoded and aligned; the NinjaTrader timezone/session template and roll schedule still need confirmation; and no strategy has yet been independently replayed from these bars.

Do not present a strategy's results from this dataset as validated until the replay, fill assumptions, costs, and out-of-sample checks are explicit.

## What is available

The supplied archive contains 16,622 daily NCD files across 68 quarterly NQ contract folders, spanning 2009-12-28 through 2026-10-26. The decoded continuous dataset currently covers **2021 onward only**:

- 24 quarterly contracts used.
- 1,967 Last files decoded successfully; zero decode errors.
- 1,911 Bid files and 1,907 Ask files are inventoried but not yet decoded.
- 1,892 contract-days have all three streams; 76 contract-days are incomplete.
- Latest NQ 12-26 folder: 38 Last files, 11 Bid files, zero Ask files.

### Continuous Last dataset

| Measure | Result |
|---|---:|
| Rows before contract stitching | 2,119,895 |
| Continuous rows | 2,054,636 |
| Continuous Last volume | 854,760,237 |
| Contracts | 24 |
| Contract transitions | 23 |
| Duplicate timestamps | 0 |
| Non-monotonic timestamps | 0 |
| First bar | 2021-01-03 18:01 ET |
| Last bar | 2026-10-27 00:00 ET |

The series is **not back-adjusted**. Each bar retains its originating contract. The roll method selects the first calendar date on which the next contract's daily Last volume exceeds the current contract's volume, then applies the switch at the 18:00 ET session boundary.

There are 2,893 intervals longer than one minute, including 1,133 61-minute daily maintenance breaks and longer weekend/holiday closures. Other gaps may be no-trade minutes or missing data. No bars were forward-filled or interpolated.

## Data file contract

The processed file is:

`NQ_1min_Last_continuous_2021-2026.csv.gz`

CSV columns:

| Column | Meaning |
|---|---|
| `utc_us` | Unix epoch timestamp in microseconds, UTC |
| `open` | Minute-bar open price |
| `high` | Minute-bar high price |
| `low` | Minute-bar low price |
| `close` | Minute-bar close price |
| `volume` | Last-trade volume |
| `contract` | Source quarterly contract, e.g. `NQ 03-21` |

Prices are decoded from the NCD price increments. Confirm the exact NinjaTrader bar timestamp convention (bar start/end labeling) before applying session filters or comparing timestamps with exported trades.

The current gzip file is approximately 26 MB. SHA-256:

`dc98a25c4787a2a14342a9d53a5e103ab9649ae836f191538af75596a3c27e23`

## Important instrument distinction

The refreshed NT8 RBE export is **GC DEC26 (Gold)**, not NQ. This NQ dataset cannot validate that GC trade history.

The other NT8 exports are NQ, making them the natural candidates for independent NQ minute-bar replay. MT5 USTEC exports are CFD results and should not be treated as directly equivalent to NQ futures without an explicit instrument, session, price, and cost mapping.

## Recommended website integration

### 1. Treat the data as a versioned dataset

Use the dataset ID above and retain its manifest alongside the data. Record:

- source archive and extraction date;
- covered date range and contracts;
- timezone assumption;
- roll method and non-back-adjusted status;
- file checksum and schema version;
- data-quality warnings and known quote-stream gaps.

Keep the compressed market-data file outside the Git repository unless there is a deliberate storage/licensing decision. The repository currently contains the audit report, not the 26 MB bar file. The website agent must receive the file separately or read it from an explicitly configured local data path.

### 2. Keep bulk history out of the browser

For a prototype, the browser can request bounded date ranges. For the full dataset, prefer a server-side reader or worker that returns only the requested window. Consider converting the source CSV into partitioned Parquet or another indexed columnar format for faster range scans; retain the gzip CSV as the immutable source artifact.

Do not load all 2.05 million rows into the page at once. Chart downsampling is acceptable for display only; strategy calculations must use the full-resolution bars.

### 3. Make time and roll behavior explicit

- Store and query timestamps in UTC; convert to the selected exchange/session timezone only for display and session rules.
- Keep the timezone configurable. The current decode assumes `America/New_York`; the user's NinjaTrader installation timezone has not been confirmed.
- Make the session template configurable and version it with each backtest.
- Preserve the `contract` field. Do not silently treat the non-back-adjusted continuous series as one seamless price history: roll transitions can create price discontinuities.
- Offer an explicit roll policy for research: per-contract processing, current volume-roll series, or a separately validated adjusted series. Never silently back-adjust this dataset.

### 4. Separate signal bars from execution assumptions

This dataset contains Last OHLCV only. It does not currently support quote-based spread, bid/ask fill, queue-position, or market-depth simulation.

The strategy builder should require or clearly display an execution model, including:
- order type and when an order becomes eligible;
- fill-price rule;
- slippage;
- commissions and exchange fees;
- contract multiplier and tick size;
- session and rollover handling.

Do not imply that a fill at the Last close is guaranteed. Keep execution assumptions separate from the strategy's signal logic and include them in every result record.

### 5. Make every result reproducible

Each backtest result should save at least:

- dataset ID and checksum;
- symbol and contract scope;
- date range and bar interval;
- timezone and session template;
- roll policy;
- strategy code/version and parameters;
- warm-up period and missing-bar policy;
- fill model, slippage, commission, tick size and contract multiplier;
- training/validation/test windows.

Show warnings when a run uses Last-only bars, unconfirmed timezone/session settings, incomplete quote coverage, or an unvalidated roll schedule.

## What is not complete

1. Bid/Ask files have not been decoded, stitched, or timestamp-aligned with Last.
2. The latest contract has no Ask files and incomplete Bid coverage.
3. The assumed New York timezone and session template have not been confirmed against the NinjaTrader installation.
4. The volume-based roll schedule has not been cross-checked against the user's NinjaTrader instrument database or roll template.
5. No NT8 strategy has yet been independently replayed from these minute bars.
6. No bar-level comparison against exported NQ trades, or execution-model validation, has been completed.
7. The archive's pre-2021 data has not been decoded into the continuous series.

## Recommended next work, in order

1. Transfer the gzip dataset to the website agent's local data directory and verify its SHA-256 against the value above.
2. Confirm NinjaTrader timezone, trading-hours template, and bar timestamp convention.
3. Decode and align Bid/Ask where coverage permits; report uncovered dates instead of filling them.
4. Validate the roll schedule against the NinjaTrader instrument/roll settings.
5. Select one NQ NT8 strategy and reproduce its trades from M1 bars without changing its rules or parameters. Compare entries, exits, timestamps, and PnL trade by trade.
6. Diagnose mismatches before expanding to the other NQ strategies.
7. Only after replication is credible, add walk-forward tests, parameter robustness checks, and portfolio simulations.

## Existing audit

See [NQ 1-minute data audit](nq_minute_data_audit.md) for the archive inventory, decoding details, and original scope limitations. The processed bars and per-file audit artifacts are separate local downloads; they are not committed to this repository.
