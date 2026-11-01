# NQ 1-minute data audit

**Updated:** 2026-11-01  
**Source:** user-supplied `NQminute.7z` archive  
**Purpose:** inventory and decode NQ NinjaTrader NCD minute files for a later independent strategy-validation phase.

## Archive inventory

- 16,622 daily NCD files across 68 quarterly NQ contract folders.
- Archive coverage: 2009-12-28 through 2026-10-26.
- The 2021+ subset contains 24 quarterly contracts and:
  - 1,967 Last files
  - 1,911 Bid files
  - 1,907 Ask files
- 1,892 contract-days have all three streams; 76 contract-days are missing one or more streams. The latest NQ 12-26 folder has 38 Last files, 11 Bid files and no Ask files.

## Decoded Last series

All 1,967 Last files in the 2021+ subset decoded successfully using the extended NCD minute encoding. The decoder supports the time, open-price, OHLC and volume code variants present in the archive. No decode errors were observed.

| Measure | Result |
|---|---:|
| Raw Last rows before contract stitching | 2,119,895 |
| Continuous Last rows after stitching | 2,054,636 |
| Continuous volume | 854,760,237 |
| Contracts used | 24 |
| Contract transitions | 23 |
| Duplicate timestamps | 0 |
| Non-monotonic timestamps | 0 |
| First continuous bar | 2021-01-03 18:01 ET |
| Last continuous bar | 2026-10-27 00:00 ET |

The continuous series uses the first calendar date on which the next contract's daily Last volume exceeds the current contract's volume. The contract switch is applied at the 18:00 ET session boundary. The output is **not back-adjusted** and retains the contract identifier on every bar.

## Timestamp and gap handling

- NCD timestamps do not carry an explicit timezone in the supplied archive. Conversion currently assumes `America/New_York`, consistent with the ET session definitions used in the strategy research. Confirm the NinjaTrader installation timezone before using these bars for rule-level replication.
- The continuous Last series contains 2,893 intervals longer than one minute. This includes 1,133 61-minute daily maintenance breaks and longer weekend/holiday closures. Other short gaps may represent minutes with no recorded trade or missing data.
- No missing bars were forward-filled or interpolated. The per-file quality CSV records row counts, gaps, volumes and timestamp bounds.
- Daily file row counts range from 1 to 1,381, with a median of 1,379. Very short files occur on low-activity weekend/holiday dates and should not be treated as full sessions.

## Local outputs

The decoded continuous series and detailed audit files were generated in the working session:

- `NQ_1min_Last_continuous_2021-2026.csv.gz` — 2,054,636 unadjusted Last bars with UTC-microsecond timestamp, OHLC, volume and contract.
- `NQ_1min_file_quality_2021plus.csv` — per-file Last stream quality.
- `NQ_1min_data_audit_2021plus.json` — machine-readable coverage, roll dates and quality summary.

The raw market data and decoded bars are **not committed to this public repository**. The chat provides the processed file separately.

## Scope and limitations

- Bid and Ask files are inventoried but have not yet been decoded and stitched into continuous quote series. Do not treat the Last series as a bid/ask execution replay.
- The volume-based roll schedule has not been cross-checked against the user's NinjaTrader instrument database or roll template.
- This is a data-ingestion and quality-audit step only. No strategy was reimplemented, optimized or backtested from these minute bars in this update.
- The current normalized-live and prop-firm reports remain based on exported completed trades. The NQ M1 series has not yet been used to independently reproduce or validate those trade exports.

The NCD decoder format reference is the MIT-licensed [NinjaTraderNCDFiles](https://github.com/jrstokka/NinjaTraderNCDFiles) implementation. The separate [ninjatrader-to-parquet](https://github.com/tbraman-dev/ninjatrader-to-parquet) project documents the daily NCD file layout and a Python decoding approach.
