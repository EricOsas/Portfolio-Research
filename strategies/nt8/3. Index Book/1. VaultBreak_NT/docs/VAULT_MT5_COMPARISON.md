# Vault existing-report comparison — 2026-10-08

The supplied NT8 report and preserved MT5 frozen export show substantial session-day overlap, but do not establish trade or engine parity. No new backtest, performance rerun, or parameter tuning was performed for this comparison.

| Existing evidence | Trades | Actual entry dates | Product / quantity | Net result |
|---|---:|---|---|---:|
| NinjaTrader Vault 2026.csv | 149 | Feb 13–Oct 6, 2026 | MNQ DEC26 / 1 | $1,161.50; reported commission $0 |
| MT5 vault_nq_native_trades.csv, FINAL_2026_FROZEN | 151 | Jan 5–Sep 3, 2026 | GT_NQ_NT8_v4 / 3 NQ | $45,730.20 broker; $38,391.60 after modeled costs |
| MT5 vault_ustec_native_trades.csv, FINAL_2026_FROZEN | 149 | Jan 5–Sep 3, 2026 | USTEC / 0.7 lot | $430.52 broker; $326.22 after modeled costs |

The NQ export is the closest saved feed comparison. Its frozen tester configuration covers Jan 1–Sep 10, M1 Every Tick, $1M deposit and $5,000 planned risk. Settings include a 70-point stop, 40-point target, synthetic first attempt and four-attempt cap, $6.20 round-trip commission per lot and 0.25-price slippage. Its $7,338.60 modeled costs are separate from the HTML report's broker net. The USTEC row is a separate CFD comparison; its matching 149 count does not establish parity.

## Conditional overlapping cohort

These date-only results assume the NT8 entry dates represent the same US trading sessions as MT5 `central_date`. NT8 CSV does not identify its platform timezone. Assuming New York timestamps is plausible but unverified; no exact timestamp normalization or match is claimed. MT5 records contain both server and UTC timestamps. Both compared ledgers contain only long trades.

Filter both ledgers inclusively to Feb 13–Sep 3, 2026; select only MT5 `stage=FINAL_2026_FROZEN`; group NT8 by the calendar date of `Entry time` and MT5 by `central_date`:

| Date-only measure | Result |
|---|---:|
| NT8 trades / active days | 126 / 50 |
| MT5 NQ trades / active days | 128 / 51 |
| Common active days | 50 |
| MT5-only / NT8-only active days | 1 / 0 |
| NT8 / MT5 trades on common days | 126 / 125 |
| Common days with equal trade counts | 47 of 50 |
| Common days with exactly one trade each | 6 |
| NT8 gross directional price points | 616.50 |
| MT5 gross directional price points | 869.55 |

Price points sum `exit_price - entry_price`, once per trade, without quantity or point value. They remove cash-size differences but retain feed, execution and model differences; they are not cost-adjusted returns or risk-normalized performance.

On the six common days with exactly one trade in each ledger, the date-only pairing is unambiguous in count but does not verify that both trades came from the same signal. NT8-minus-MT5 entry price differences have min -1.50, median -0.375, max +0.25 points; five of six are within one point. Exit differences have min -4.50, median -0.88, max +0.09 points; three of six are within one point. Multiple-attempt days were not paired by ordinal because matching counts do not establish matching attempts.

## Limits and current change

The NT8 CSV lacks the actual Analyzer settings, configured date window, timezone, session template, merge policy, warmup coverage and loaded source/binary identity. Current defaults cannot prove the settings used to generate it. The frozen MT5 results belong to the older Demo binary and cannot validate later production repairs.

The explicit 60,000-M1-bar request cap has now been removed from the native ports in the parent task. That change can affect available historical coverage and warmup, but has not been performance-tested here and does not alter either saved report. The supplied Overnight report's Sep 11–Oct 6 coverage is a separate coverage concern; this Vault comparison does not establish its cause.

Preserve user reports, frozen configs/inputs, native release CSVs, HTML reports and their images, workbooks, and binary/source lineage. Historical fixtures and compile clutter are planned for a manifest-backed archive outside NinjaTrader `bin/Custom`; this comparison itself moves nothing.

## Reproduction sources

- NT8: `C:/Users/Administrator/Documents/NinjaTrader 8/bin/Custom/Strategies/VaultBreak_NT/validation/NinjaTrader Vault 2026.csv`; SHA-256 `240737790247eba10e47a7ba6b7446250c615824fe7c993401f3ea6a37154329`.
- MT5 NQ: `C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/D0E8209F77C8CF37AD8BF550E51FF075/MQL5/Experts/4. VaultBreak/validation/release/vault_nq_native_trades.csv`; SHA-256 `be9b61f8204401709bd4f9852c06333aea0ad32a1da2acde366fdac99add9b69`.
- Matching MT5 frozen settings: `4. VaultBreak/validation/configs/vault_nq_final2026_frozen_v1.ini` and `inputs/vault_nq_final2026_frozen_v1.set`; preserved report `reports/GoldenTrio_vault_nq_final2026_frozen_v1.htm`.

Read CSVs with UTF-8 BOM handling. Parse NT8 times with `%m/%d/%Y %I:%M:%S %p`; parse MT5 dates with `%Y.%m.%d`. Apply the inclusive cohort above before counts or price-point sums. Compute price-difference distributions only where both date groups contain exactly one row. All statistics derive from existing reports.
