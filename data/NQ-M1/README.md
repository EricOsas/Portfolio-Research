# NQ M1 data and rebuild instructions

**Dataset ID:** NQ_M1_LAST_CONTINUOUS_2021_2026_V1  
**Scope:** NQ quarterly contracts NQ 03-21 through NQ 12-26, 1-minute Last-trade bars  
**Status:** machine-readable audit metadata, NCD decoder and dataset builder are committed. The 26 MB continuous bars, per-file quality CSV and original NQminute.7z archive are not committed.

## Repository contents

- audit/NQ_1min_data_audit_2021plus.json — machine-readable archive, coverage, roll and quality summary; includes the continuous-file SHA-256 and size.
- scripts/ncd_minute.py — decoder for daily NinjaTrader NCD minute files.
- scripts/build_nq_m1.py — rebuilds the continuous Last series, per-file quality CSV and audit JSON.

## Rebuild from the original archive

The raw NQminute.7z archive is not stored in this repository. Obtain it through the authorized local data source, then extract it while preserving the quarterly contract folders. The builder expects this layout:

~~~text
NQminute_raw/
  NQ 03-21/
    YYYYMMDD.Last.ncd
    YYYYMMDD.Bid.ncd
    YYYYMMDD.Ask.ncd
  NQ 06-21/
    ...
~~~

The builder filters the contract range to NQ 03-21 through NQ 12-26 by default, so the full archive can be extracted into the input root. It reads only *.Last.ncd; Bid and Ask files are ignored.

Use Python 3.9 or newer and install the two runtime dependencies:

~~~bash
python -m pip install numpy pandas
~~~

From the repository root, run:

~~~bash
python data/NQ-M1/scripts/build_nq_m1.py \
  --input-root /path/to/NQminute_raw \
  --output-dir /path/to/NQ_M1_output \
  --start-contract "NQ 03-21" \
  --end-contract "NQ 12-26" \
  --timezone America/New_York \
  --label 2021plus
~~~

The output directory receives:

- NQ_1min_Last_continuous_2021plus.csv.gz
- NQ_1min_file_quality_2021plus.csv
- NQ_1min_data_audit_2021plus.json

Use --workers N to control parallel decoding. Use a different --label when building another contract/date scope; update the start/end contract arguments at the same time. The builder does not extract the .7z archive itself.

A single NCD file can be inspected directly:

~~~bash
python data/NQ-M1/scripts/ncd_minute.py \
  "/path/to/NQ 03-21/YYYYMMDD.Last.ncd" America/New_York
~~~

## Audited 2021+ result

| Measure | Audited result |
|---|---:|
| Quarterly contracts | 24 |
| Last files decoded | 1,967 |
| Decode errors | 0 |
| Raw Last rows before stitching | 2,119,895 |
| Continuous rows | 2,054,636 |
| Continuous Last volume | 854,760,237 |
| Duplicate/non-monotonic timestamps | 0 |
| First bar | 2021-01-03 23:01 UTC |
| Last bar | 2026-10-27 04:00 UTC |

The continuous output uses columns utc_us,open,high,low,close,volume,contract. utc_us is Unix epoch microseconds in UTC. The contract column preserves the originating quarterly contract.

The original continuous file is 27,023,646 bytes with SHA-256:

~~~text
dc98a25c4787a2a14342a9d53a5e103ab9649ae836f191538af75596a3c27e23
~~~

The file is intentionally not in GitHub; it can be regenerated from the raw archive with the scripts above. Gzip container metadata can vary between builds, so compare decompressed CSV content if a regenerated gzip checksum differs.

## Data and backtest cautions

- Timestamps are converted using America/New_York by default. Confirm the NinjaTrader installation timezone and trading-hours template before strategy replay.
- Contract rolls use the first date on which the next contract's daily Last volume exceeds the current contract's volume, with the switch at 18:00 in the configured timezone. This roll schedule has not been cross-checked against the user's NinjaTrader instrument database/template.
- The series is not back-adjusted. Preserve the contract identifier and do not treat roll gaps as ordinary price movement.
- No missing minutes are forward-filled or interpolated. Gaps include maintenance breaks, weekends/holidays, possible no-trade intervals and possible missing data.
- Bid and Ask files are inventoried but have not been decoded or aligned. Last OHLCV does not provide spread, quote-side fills, queue position or market depth.
- The latest contract in the audited subset (NQ 12-26) has no Ask files and incomplete Bid coverage.
- No strategy has yet been independently replayed from these bars. Results from this feed are research/prototyping results until timestamp conventions, session rules, roll behavior, fills, slippage, fees and exported trades are validated.
- The refreshed NT8 RBE export is GC DEC26, not NQ. This NQ dataset cannot validate that Gold strategy. MT5 USTEC CFD results are not directly equivalent to NQ futures without an explicit mapping.

## Provenance

The decoder is adapted from MIT-licensed NinjaTrader NCD format references; see source attribution in scripts/ncd_minute.py. Preserve that attribution if the decoder is modified or redistributed.
