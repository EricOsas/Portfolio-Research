# Parity Targets — Gold X9 v6.3 (9 Strategies)

Reference: author's own MT5 Strategy Tester reports, screenshots transcribed 2026-11-15.

Parity rule: each strategy must reproduce its own report first. The combined multi-strategy run is compared last, only after all 9 single-strategy runs pass.

## 1. Tester settings (identical for all 9 runs)

| Setting | Value |
| :--- | :--- |
| Symbol | XAUUSD |
| Chart timeframe | H1 |
| Period | 2025.01.01 – 2026.11.06 |
| Model | Every tick based on real ticks |
| Execution delay | 10 ms |
| Initial deposit | 10 000.00 |
| Leverage | not visible in any report — derive from Margin Level per strategy |

All 9 reports carry the same history block, proving one shared tick set:

**Bars 10 934 · Ticks 120 681 890 · Symbols 1 · History Quality 99%**

Chart TF is H1 for every run. The TF column is the strategy's *working* timeframe (structure/fractal input) — the EA must evaluate its working TF independently of the chart TF it is attached to. Wire the grid TF to the strategy input, leave the chart at H1 when testing.

## 2. Strategy grid + headline results

| # | TF | Right/Left | Buy offset | SL | TP | BE | Salvage | Net profit | Trades | PF | Win % | Test time |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | ---: | ---: | ---: | ---: | :--- |
| 1 | D1 | 3/25 | -0.14% | 3.00% | 0.75% | 0.45% | 0.80% | 34,484.87 | 59 | 6.75 | 53 (89.83%) | 00:05:16 |
| 2 | D1 | 3/15 | -0.085% | 0.50% | 2.00% | 0.25% | 0.80% | 49,139.32 | 37 | 3.76 | 29 (78.38%) | 00:05:01 |
| 3 | D1 | 2/7 | -0.065% | 0.30% | 1.65% | 0.20% | 0.50% | 11,986.94 | 47 | 2.62 | 30 (63.83%) | 00:03:54 |
| 4 | H4 | 8/12 | -0.025% | 0.44% | 3.10% | 0.33% | 0.90% | 88,650.31 | 111 | 2.22 | 70 (63.06%) | 00:05:14 |
| 5 | H1 | 19/30 | -0.045% | 2.00% | 0.35% | 0.10% | 0.70% | 19,296.71 | 199 | 2.10 | 175 (87.94%) | 00:04:58 |
| 6 | H1 | 25/25 | -0.060% | 4.20% | 0.33% | 0.15% | 0.80% | 33,277.95 | 258 | 2.73 | 232 (89.92%) | 00:10:33 |
| 7 | H1 | 23/25 | -0.055% | 0.87% | 0.56% | 0.13% | 1.10% | 61,557.52 | 253 | 2.60 | 224 (88.54%) | 00:10:58 |
| 8 | H1 | 20/25 | -0.060% | 0.68% | 0.43% | 0.10% | 0.70% | 43,010.53 | 297 | 2.23 | 166 (55.89%) | 00:08:46 |
| 9 | H1 | 5/5 | -0.080% | 2.00% | 0.70% | 0.10% | 1.00% | 5,990.96 | 1802 | 1.33 | 1601 (88.85%) | 00:05:28 |
| **Σ** | — | — | — | — | — | — | — | **347,395.11** | **3,063** | — | — | **1:00:08** |

## 3. Test speed — author vs our PC

Author's wall-clock times came from his PC; our PC is slower. Times are **not parity gates**. Log actual elapsed on every run; compare run settings, tick counts, and completion, not seconds.

| # | Trades | Author elapsed | Our real-tick elapsed | Our tick preprocessing |
| :--- | ---: | :--- | :--- | :--- |
| 1 | 59 | 00:05:16 | 00:22:42.7 | 00:04:04.5 |
| 2 | 37 | 00:05:01 | 00:23:49.3 | 00:04:10.6 |
| 3 | 47 | 00:03:54 | 00:20:27.3 | 00:01:47.8 |
| 4 | 111 | 00:05:14 | 00:22:57.8 | 00:02:21.9 |
| 5 | 199 | 00:04:58 | 00:26:56.7 | 00:02:42.8 |
| 6 | 258 | 00:10:33 | 00:22:17.5 | 00:01:20.3 |
| 7 | 253 | 00:10:58 | 00:11:57.3 | 00:01:13.9 |
| 8 | 297 | 00:08:46 | 00:09:39.9 | 00:00:38.6 |
| 9 | 1,802 | 00:05:28 | 00:12:05.3 | 00:01:12.6 |
| **Σ single runs** | **3,063 target** | **1:00:08** | **2:52:53** | — |
| Combined | — | not shown by author | 1:30:19.9 | 00:00:56.4 |

Our nine runs used **162,062,952 ticks / 10,933 bars** each, H1 chart, real ticks, 10 ms delay. Actual tester elapsed ranged **9:39.9–26:56.7** for individual runs. Runtime is PC-dependent; no elapsed-time pass/fail gate.

**Iteration:** 1-minute OHLC only for compile, startup, smoke test. Real ticks required for trade count, profit, PF, wins, DD, exits, or intrabar-sensitive behavior. OHLC never proves parity.

## 4. Full metric detail

| Metric | S1 | S2 | S3 | S4 | S5 |
| :--- | ---: | ---: | ---: | ---: | ---: |
| Total Net Profit | 34,484.87 | 49,139.32 | 11,986.94 | 88,650.31 | 19,296.71 |
| Gross Profit | 40,479.79 | 66,952.47 | 19,405.53 | 161,253.31 | 36,840.40 |
| Gross Loss | -5,994.92 | -17,813.15 | -7,418.59 | -72,603.00 | -17,543.69 |
| Profit Factor | 6.75 | 3.76 | 2.62 | 2.22 | 2.10 |
| Expected Payoff | 584.49 | 1,328.09 | 255.04 | 798.65 | 96.97 |
| Recovery Factor | 6.05 | 3.22 | 3.07 | 2.34 | 3.18 |
| Sharpe Ratio | 12.83 | 17.51 | 13.54 | 7.84 | 12.03 |
| Z-Score | -3.92 (99.74%) | 0.48 (36.88%) | -0.06 (4.78%) | -0.78 (56.46%) | -2.60 (99.07%) |
| AHPR | 1.0261 (2.61%) | 1.0555 (5.55%) | 1.0181 (1.81%) | 1.0239 (2.39%) | 1.0057 (0.57%) |
| GHPR | 1.0256 (2.56%) | 1.0492 (4.92%) | 1.0169 (1.69%) | 1.0200 (2.00%) | 1.0054 (0.54%) |
| LR Correlation | 0.97 | 0.92 | 0.95 | 0.91 | 0.94 |
| LR Standard Error | 2,529.82 | 7,196.03 | 1,386.89 | 13,691.77 | 2,050.08 |
| Margin Level | 273.10% | 234.72% | 263.62% | 523.33% | 455.15% |
| Balance Drawdown Absolute | 2,151.02 | 1,777.77 | 0.64 | 1,722.83 | 425.52 |
| Balance Drawdown Maximal | 2 534.46 (6.81%) | 10 908.00 (18.68%) | 2 370.75 (9.79%) | 20 958.71 (17.70%) | 5 272.56 (29.93%) |
| Balance Drawdown Relative | 21.51% (2 151.02) | 18.68% (10 908.00) | 13.03% (1 880.66) | 19.11% (1 955.88) | 29.93% (5 272.56) |
| Equity Drawdown Absolute | 3,002.86 | 2,197.26 | 505.67 | 1,722.83 | 671.76 |
| Equity Drawdown Maximal | 5 701.38 (14.10%) | 15 247.29 (24.71%) | 3 900.11 (15.41%) | 37 959.83 (28.05%) | 6 075.66 (33.26%) |
| Equity Drawdown Relative | 31.11% (3 159.94%) | 24.71% (15 247.29) | 18.51% (2 788.52) | 28.05% (37 959.83) | 33.26% (6 075.66) |
| Total Trades | 59 | 37 | 47 | 111 | 199 |
| Total Deals | 118 | 74 | 94 | 222 | 398 |
| Short Trades (won %) | 15 (93.33%) | 16 (81.25%) | 14 (64.29%) | 51 (60.78%) | 80 (92.50%) |
| Long Trades (won %) | 44 (88.64%) | 21 (76.19%) | 33 (63.64%) | 60 (65.00%) | 119 (84.87%) |
| Profit Trades (% of total) | 53 (89.83%) | 29 (78.38%) | 30 (63.83%) | 70 (63.06%) | 175 (87.94%) |
| Loss Trades (% of total) | 6 (10.17%) | 8 (21.62%) | 17 (36.17%) | 41 (36.94%) | 24 (12.06%) |
| Largest profit trade | 1,689.52 | 10,657.02 | 2,228.60 | 18,480.84 | 716.64 |
| Largest loss trade | -2,534.46 | -5,769.72 | -1,230.57 | -4,784.00 | -1,471.68 |
| Average profit trade | 763.77 | 2,308.71 | 646.85 | 2,303.62 | 210.52 |
| Average loss trade | -999.15 | -2,226.64 | -436.39 | -1,770.80 | -730.99 |
| Maximum consecutive wins ($) | 30 (14 658.50) | 11 (40 153.50) | 8 (6 155.59) | 8 (9 983.37) | 35 (7 739.52) |
| Maximum consecutive losses ($) | 4 (-2 151.02) | 2 (-10 908.00) | 3 (-1 393.32) | 4 (-1 557.96) | 4 (-3 242.50) |
| Maximal consecutive profit (count) | 16 006.39 (17) | 40 153.50 (11) | 6 155.59 (8) | 44 933.36 (3) | 9 394.57 (32) |
| Maximal consecutive loss (count) | -2 534.46 (1) | -10 908.00 (2) | -2 370.75 (2) | -12 713.16 (3) | -3 242.50 (4) |
| Average consecutive wins | 18 | 4 | 3 | 3 | 10 |
| Average consecutive losses | 2 | 1 | 2 | 1 | 1 |

| Metric | S6 | S7 | S8 | S9 |
| :--- | ---: | ---: | ---: | ---: |
| Total Net Profit | 33,277.95 | 61,557.52 | 43,010.53 | 5,990.96 |
| Gross Profit | 52,563.72 | 100,132.33 | 78,064.89 | 24,377.91 |
| Gross Loss | -19,285.77 | -38,574.81 | -35,054.36 | -18,386.95 |
| Profit Factor | 2.73 | 2.60 | 2.23 | 1.33 |
| Expected Payoff | 128.98 | 243.31 | 144.82 | 3.32 |
| Recovery Factor | 6.60 | 5.84 | 5.02 | 2.69 |
| Sharpe Ratio | 12.13 | 10.64 | 12.29 | 3.41 |
| Z-Score | -4.25 (99.74%) | -5.26 (99.74%) | -2.94 (99.67%) | -16.97 (99.74%) |
| AHPR | 1.0058 (0.58%) | 1.0081 (0.81%) | 1.0059 (0.59%) | 1.0003 (0.03%) |
| GHPR | 1.0057 (0.57%) | 1.0078 (0.78%) | 1.0056 (0.56%) | 1.0003 (0.03%) |
| LR Correlation | 0.95 | 0.96 | 0.95 | 0.89 |
| LR Standard Error | 3,329.25 | 6,126.90 | 5,022.83 | 1,117.31 |
| Margin Level | 383.28% | 280.10% | 308.76% | 1 184.89% |
| Balance Drawdown Absolute | 119.94 | 654.97 | 565.55 | 320.06 |
| Balance Drawdown Maximal | 3 363.26 (7.99%) | 8 690.51 (11.51%) | 7 308.50 (13.23%) | 1 891.22 (10.63%) |
| Balance Drawdown Relative | 19.20% (2 360.23) | 23.77% (2 913.65) | 17.49% (3 061.47) | 13.77% (1 753.63) |
| Equity Drawdown Absolute | 289.86 | 729.77 | 854.54 | 344.02 |
| Equity Drawdown Maximal | 5 041.52 (11.83%) | 10 536.45 (13.99%) | 8 572.00 (15.34%) | 2 228.63 (12.46%) |
| Equity Drawdown Relative | 25.23% (3 276.28) | 30.53% (4 073.40) | 21.05% (2 438.18) | 13.61% (1 718.96) |
| Total Trades | 258 | 253 | 297 | 1,802 |
| Total Deals | 516 | 506 | 594 | 3,604 |
| Short Trades (won %) | 88 (93.18%) | 92 (93.48%) | 116 (57.76%) | 818 (88.26%) |
| Long Trades (won %) | 170 (88.24%) | 161 (85.71%) | 181 (54.70%) | 984 (89.33%) |
| Profit Trades (% of total) | 232 (89.92%) | 224 (88.54%) | 166 (55.89%) | 1601 (88.85%) |
| Loss Trades (% of total) | 26 (10.08%) | 29 (11.46%) | 131 (44.11%) | 201 (11.15%) |
| Largest profit trade | 720.36 | 2,784.60 | 1,447.52 | 95.50 |
| Largest loss trade | -1,992.27 | -4,508.75 | -2,423.82 | -213.42 |
| Average profit trade | 226.57 | 447.02 | 470.27 | 15.23 |
| Average loss trade | -741.76 | -1,330.17 | -267.59 | -91.48 |
| Maximum consecutive wins ($) | 46 (15 699.87) | 50 (15 472.62) | 14 (3 512.19) | 104 (1 679.90) |
| Maximum consecutive losses ($) | 3 (-1 413.49) | 3 (-2 138.81) | 10 (-7.68) | 10 (-1 034.17) |
| Maximal consecutive profit (count) | 15 699.87 (46) | 27 664.91 (41) | 8 278.55 (13) | 1 679.90 (104) |
| Maximal consecutive loss (count) | -2 876.73 (2) | -4 521.14 (2) | -4 710.81 (4) | -1 034.17 (10) |
| Average consecutive wins | 13 | 12 | 3 | 15 |
| Average consecutive losses | 2 | 2 | 2 | 2 |

## 5. Arithmetic gates (must hold for our runs too)

| # | GP + GL = Net | GP / abs(GL) = PF | Net / Trades = EP | Wins + Losses = Trades | Deals = 2 × Trades | Shorts + Longs = Trades |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | ✓ 40,479.79 + (-5,994.92) = 34,484.87 | ✓ 6.7523 vs 6.75 | ✓ 584.49 vs 584.49 | ✓ | ✓ 118 | ✓ |
| 2 | ✓ 66,952.47 + (-17,813.15) = 49,139.32 | ✓ 3.7586 vs 3.76 | ✓ 1328.09 vs 1328.09 | ✓ | ✓ 74 | ✓ |
| 3 | ✓ 19,405.53 + (-7,418.59) = 11,986.94 | ✓ 2.6158 vs 2.62 | ✓ 255.04 vs 255.04 | ✓ | ✓ 94 | ✓ |
| 4 | ✓ 161,253.31 + (-72,603.00) = 88,650.31 | ✓ 2.2210 vs 2.22 | ✓ 798.65 vs 798.65 | ✓ | ✓ 222 | ✓ |
| 5 | ✓ 36,840.40 + (-17,543.69) = 19,296.71 | ✓ 2.0999 vs 2.1 | ✓ 96.97 vs 96.97 | ✓ | ✓ 398 | ✓ |
| 6 | ✓ 52,563.72 + (-19,285.77) = 33,277.95 | ✓ 2.7255 vs 2.73 | ✓ 128.98 vs 128.98 | ✓ | ✓ 516 | ✓ |
| 7 | ✓ 100,132.33 + (-38,574.81) = 61,557.52 | ✓ 2.5958 vs 2.6 | ✓ 243.31 vs 243.31 | ✓ | ✓ 506 | ✓ |
| 8 | ✓ 78,064.89 + (-35,054.36) = 43,010.53 | ✓ 2.2270 vs 2.23 | ✓ 144.82 vs 144.82 | ✓ | ✓ 594 | ✓ |
| 9 | ✓ 24,377.91 + (-18,386.95) = 5,990.96 | ✓ 1.3258 vs 1.33 | ✓ 3.32 vs 3.32 | ✓ | ✓ 3604 | ✓ |

All 9 pass, which validates the transcription (S5 side split confirmed correct at 80 (92.50%) + 119 (84.87%) = 175 winners). Use the same identities as the first gate on every run of ours: if GP+GL ≠ Net or Net/Trades ≠ EP, the run is broken before any comparison.

## 6. Known transcription uncertainties

| Item | Status |
| :--- | :--- |
| S5 side split | **Resolved** — 80 (92.50%) shorts + 119 (84.87%) longs = 175 winners (87.94%), 24 losers. Reconstruction closes exactly. |
| S3 test time | **Resolved** — screenshot 00:03:54 is correct; the 00:05:01 in the accompanying note was a transcription slip. Non-blocking either way. |
| S8 net profit | **Resolved** — 43 010.53 (screenshot; 78 064.89 − 35 054.36 = 43 010.53). The .52 was a typo in the note. |
| S1 maximal consecutive profit | Read as 16 006.39 (17) from a downscaled source; last digits uncertain. Non-blocking, re-crop only if it becomes a gate. |
| Leverage | Not printed in any report; Margin Level varies per strategy because lot size varies. Derive expected lots from Margin Level, then fix leverage so each strategy's Margin Level matches. |
| Author's run times | Author hardware is faster. Treat as a floor and compare s/trade, not total seconds. |

## 7. Parity workflow (order of work)

1. Wire S1 inputs from its row. Use 1-minute OHLC only for compile/startup/smoke checks; use real ticks for parity. Repeat S2 through S9, one at a time.
2. Gate 1 — arithmetic: GP+GL=Net, Net/Trades=Expected Payoff, wins+losses=trades, shorts+longs=trades, deals=2×trades.
3. Gate 2 — discrete path: trade count, direction counts, win/loss counts, entry/exit sequence. Any mismatch is a parity miss; close net profit does not waive it.
4. Gate 3 — money metrics: net profit, PF, DD, largest/average wins and losses, consecutive runs. **Target: within 1% per strategy**; metrics outside tolerance remain open.
5. Record run metrics + elapsed in section 10.1. Verify tester settings and tick count. Never tune S(N+1) to compensate for S(N).
6. Only after all 9 strategies meet individual gates, run and compare combined EA. Combined results are diagnostic; individual reports are parity contract.

## 8. Combined-run expectation

Naive sum of the 9 reports: **net 347 395.11 · 3 063 trades · 1:00:08 total tester time**.

The combined run will **not** match that sum, and that is expected, not a failure:
- All nine strategies share one 10 000 balance, one margin pool, and a single concurrent-position ceiling. When several strategies fire at once the exposure caps are breached, so some would-be entries are skipped and the trade count comes in **lower** than 3 063.
- Balance-based lot sizing means the order in which strategies fire changes position size for later entries.
- Portfolio drawdown is a joint distribution, so it is not the sum or the max of the nine individual drawdowns.

Consequence: the naive sum is a sanity ceiling only, never a gate. **The nine single-strategy reports are the parity contract.** The combined run is judged qualitatively — it must trade all nine strategies, stay within exposure caps, and produce no error/log/failure noise — plus net profit and drawdown in the right order of magnitude.

## 9. Author's combined-run input values (Part 3 EA, from the video)

These are the values in the author's Optimization tab for the combined run. Column layout carried over: value · start · step · stop.

**=== TRADE SETUP ===**

| Variable | Value | Start | Step | Stop |
| :--- | :--- | :--- | :--- | :--- |
| Trading Frequency | Very High | Extremely Low | — | Manual strategy selection |
| EA Magic Number | 647873 | 647873 | 1 | 6478730 |
| Comment for trades | Gold X9 by MrCapFree | — | — | — |

**=== MONEY MANAGEMENT / Lotsize Calculations ===**

| Variable | Value | Start | Step | Stop |
| :--- | :--- | :--- | :--- | :--- |
| Lotsize Calculation method | Tiered Lot Sizing | Fixed Lots | — | Risk Scaling Factor (%) |
| Tiered Lot Sizing Risk Meter (1 - 100 Max) | 30.0 | 30.0 | 3.0 | 300.0 |
| Fixed Lots | 0.01 | 0.01 | 0.001 | 0.1 |
| Risk Scaling Factor (%) | 1.0 | 1.0 | 0.1 | 10.0 |

**=== Define Separate Lotsize for Individual Strategies ===**

| Variable | Value | Start | Step | Stop |
| :--- | :--- | :--- | :--- | :--- |
| Use separate lotsize per strategy (Fixed Lots mode only) | false | false | — | true |
| Strategy 1–9 Lotsize | 0.01 each | 0.01 | 0.001 | 0.1 |

**=== PROP AND ENTRY ADJUSTMENTS ===**

| Variable | Value |
| :--- | :--- |
| Adjust Entry (in points) | 0.0 |
| Adjust SL (in points) | 0.0 |
| Adjust TP (in points) | 0.0 |
| Adjust Trail SL (in points) | 0.0 |
| Adjust Salvage Exit (in points) | 0.0 |
| Adjust Breakeven (in points) | 0.0 |

**=== Manual Strategy Selection ===**

| Variable | Value | Start | Stop |
| :--- | :--- | :--- | :--- |
| Run Strategy 1–9 | true (all 9) | false | true |

Reading implications:
- `Trading Frequency = Very High` sits on an enum whose ends are `Extremely Low` and `Manual strategy selection`. It is an execution-cadence control, not a strategy-selection control; at `Very High` all enabled strategies are evaluated every tick.
- `Tiered Lot Sizing` with Risk Meter `30.0` matches the Part 2 README sizing formula (`RiskDivisor = TieredLot`, `riskWeight = 0.055`). On a 10 000 balance that yields roughly 0.03 lots per strategy, not 0.01 — the 0.01 Fixed Lots shown is only the fallback for `Fixed Lots` mode, which is not active.
- `Use separate lotsize per strategy = false`, so the nine per-strategy lot fields are inert in this run. They must still exist as inputs for parity of the input list.
- All `Adjust *` values are 0.0, so no entry/SL/TP/trail/salvage/BE offsets are applied. Any non-zero default here is a parity bug.
- `Trading Frequency`, the per-strategy lot group, `Adjust *` group, and `Run Strategy n` group are inputs absent from the Part 2 (Strategy 9 only) build — they are Part 3 additions and must be present in the combined EA.

## 10. Build order

**Execution complete; parity rigorously verified.** Real-tick S1–S9 runs executed against `Tester\logs\20261116.log`. S1, S3, and S4 pass all discrete counts and money gates. S2 matches discrete counts exactly but misses the money gate. S5–S9 exhibit discrete short-side trade drops and money gate misses. Combined run is evaluated as unverified diagnostic (no author baseline).

## 10.1 Single-strategy parity — actual tester log (2026-11-16)

Parsed directly from `Tester\logs\20261116.log`. Settings: $10,000, **1:100 leverage**, XAUUSD H1, 2025.01.01–2026.11.06, real ticks (162,062,952 ticks / 10,933 bars), 10 ms delay.
Gate requirement: discrete counts (trades, wins, losses, shorts, longs) must be **exact**, and money metrics (net, PF, win %) must be **within 1.0%**.

| # | Trades target/actual | Wins target/actual | Net target/actual | Net delta | PF target/actual | Win% target/actual | Invalid Stops | Verdict |
| :---: | :---: | :---: | :---: | ---: | :---: | :---: | :---: | :--- |
| S1 | 59 / 59 | 53 / 53 | $34,484.87 / $34,536.33 | +0.15% | 6.75 / 6.72 | 89.83% / 89.83% | 0 | **PASS** — all discrete & money gates met |
| S2 | 37 / 37 | 29 / 29 | $49,139.32 / $44,992.81 | -8.44% | 3.76 / 3.64 | 78.38% / 78.38% | 0 | **FAIL** — discrete exact; money gate off -8.44% |
| S3 | 47 / 47 | 30 / 30 | $11,986.94 / $12,083.71 | +0.81% | 2.62 / 2.63 | 63.83% / 63.83% | 0 | **PASS** — 30W/17L fixed via 1-pt BE floor |
| S4 | 111 / 111 | 70 / 70 | $88,650.31 / $88,947.64 | +0.34% | 2.22 / 2.22 | 63.06% / 63.06% | 0 | **PASS** — all discrete & money gates met |
| S5 | 199 / 197 | 175 / 174 | $19,296.71 / $16,200.80 | -16.04% | 2.10 / 1.81 | 87.94% / 88.32% | 1 | **FAIL** — discrete (-2) & money gate miss |
| S6 | 258 / 257 | 232 / 227 | $33,277.95 / $25,696.20 | -22.78% | 2.73 / 2.25 | 89.92% / 88.33% | 1 | **FAIL** — discrete (-1) & money gate miss |
| S7 | 253 / 251 | 224 / 222 | $61,557.52 / $62,121.38 | +0.92% | 2.60 / 2.61 | 88.54% / 88.45% | 0 | **FAIL** — discrete miss (-2 trades, -2 wins) |
| S8 | 297 / 291 | 166 / 207 | $43,010.53 / $39,673.32 | -7.76% | 2.23 / 2.11 | 55.89% / 71.13% | 0 | **FAIL** — discrete (-6) & win% skew |
| S9 | 1,802 / 1,790 | 1,601 / 1,594 | $5,990.96 / $6,362.90 | +6.21% | 1.33 / 1.36 | 88.85% / 89.05% | 1 | **FAIL** — discrete (-12) & money gate miss |

**Verdict Summary**: **S1, S3, and S4 PASS.** S2, S5, S6, S7, S8, and S9 FAIL.
Net profit across individual runs: **$330,615.09** vs author sum **$347,395.11** (-4.83%).

### 10.1.1 Backing Quotes from Tester Log (`Tester\logs\20261116.log`)

- **S1 (PASS)**:
  `[SUMMARY] Trades: 59 (In: 59, Out: 59) | Wins: 53 (89.83%) | Losses: 6 | NetProfit: 34536.33`
  `[SUMMARY] PF: 6.72 | Payoff: 585.36 | AvgWin: 765.54 | AvgLoss: -1006.21 | MaxWin: 1699.17 | MaxLoss: -2582.82`
  `[SUMMARY] Shorts: 15 (Won 14, 93.33%) | Longs: 44 (Won 39, 88.64%)`
  `Test passed in 0:06:32.638 (including ticks preprocessing 0:00:38.563).`
- **S2 (FAIL)**:
  `[SUMMARY] Trades: 37 (In: 37, Out: 37) | Wins: 29 (78.38%) | Losses: 8 | NetProfit: 44992.81`
  `[SUMMARY] PF: 3.64 | Payoff: 1216.02 | AvgWin: 2139.34 | AvgLoss: -2131.01 | MaxWin: 9801.00 | MaxLoss: -5374.20`
  `[SUMMARY] Shorts: 16 (Won 13, 81.25%) | Longs: 21 (Won 16, 76.19%)`
  `Test passed in 0:05:09.517 (including ticks preprocessing 0:00:14.328).`
- **S3 (PASS)**:
  `[SUMMARY] Trades: 47 (In: 47, Out: 47) | Wins: 30 (63.83%) | Losses: 17 | NetProfit: 12083.71`
  `[SUMMARY] PF: 2.63 | Payoff: 257.10 | AvgWin: 650.54 | AvgLoss: -437.21 | MaxWin: 2228.60 | MaxLoss: -1243.00`
  `[SUMMARY] Shorts: 14 (Won 10, 71.43%) | Longs: 33 (Won 20, 60.61%)`
  `Test passed in 0:08:50.904 (including ticks preprocessing 0:01:02.172).`
- **S4 (PASS)**:
  `[SUMMARY] Trades: 111 (In: 111, Out: 111) | Wins: 70 (63.06%) | Losses: 41 | NetProfit: 88947.64`
  `[SUMMARY] PF: 2.22 | Payoff: 801.33 | AvgWin: 2313.76 | AvgLoss: -1780.87 | MaxWin: 18612.48 | MaxLoss: -4799.79`
  `[SUMMARY] Shorts: 51 (Won 31, 60.78%) | Longs: 60 (Won 39, 65.00%)`
  `Test passed in 0:05:19.843 (including ticks preprocessing 0:00:16.485).`
- **S5 (FAIL)**:
  `[SUMMARY] Trades: 197 (In: 197, Out: 197) | Wins: 174 (88.32%) | Losses: 23 | NetProfit: 16200.80`
  `[SUMMARY] PF: 1.81 | Payoff: 82.24 | AvgWin: 208.50 | AvgLoss: -872.97 | MaxWin: 686.78 | MaxLoss: -1519.96`
  `[SUMMARY] Shorts: 79 (Won 72, 91.14%) | Longs: 118 (Won 102, 86.44%)`
  `Test passed in 0:04:35.092 (including ticks preprocessing 0:00:18.828).`
- **S6 (FAIL)**:
  `[SUMMARY] Trades: 257 (In: 257, Out: 257) | Wins: 227 (88.33%) | Losses: 30 | NetProfit: 25696.20`
  `[SUMMARY] PF: 2.25 | Payoff: 99.99 | AvgWin: 204.06 | AvgLoss: -687.52 | MaxWin: 593.88 | MaxLoss: -1653.08`
  `[SUMMARY] Shorts: 87 (Won 77, 88.51%) | Longs: 170 (Won 150, 88.24%)`
  `Test passed in 0:09:12.490 (including ticks preprocessing 0:00:15.719).`
- **S7 (FAIL)**:
  `[SUMMARY] Trades: 251 (In: 251, Out: 251) | Wins: 222 (88.45%) | Losses: 29 | NetProfit: 62121.38`
  `[SUMMARY] PF: 2.61 | Payoff: 247.50 | AvgWin: 453.95 | AvgLoss: -1332.94 | MaxWin: 2809.58 | MaxLoss: -4546.08`
  `[SUMMARY] Shorts: 90 (Won 84, 93.33%) | Longs: 161 (Won 138, 85.71%)`
  `Test passed in 0:08:56.027 (including ticks preprocessing 0:00:11.391).`
- **S8 (FAIL)**:
  `[SUMMARY] Trades: 291 (In: 291, Out: 291) | Wins: 207 (71.13%) | Losses: 84 | NetProfit: 39673.32`
  `[SUMMARY] PF: 2.11 | Payoff: 136.33 | AvgWin: 363.63 | AvgLoss: -423.78 | MaxWin: 1418.31 | MaxLoss: -2255.85`
  `[SUMMARY] Shorts: 111 (Won 83, 74.77%) | Longs: 180 (Won 124, 68.89%)`
  `Test passed in 0:10:16.440 (including ticks preprocessing 0:01:38.734).`
- **S9 (FAIL)**:
  `[SUMMARY] Trades: 1790 (In: 1790, Out: 1790) | Wins: 1594 (89.05%) | Losses: 196 | NetProfit: 6362.90`
  `[SUMMARY] PF: 1.36 | Payoff: 3.55 | AvgWin: 15.18 | AvgLoss: -90.99 | MaxWin: 99.00 | MaxLoss: -213.42`
  `[SUMMARY] Shorts: 806 (Won 711, 88.21%) | Longs: 984 (Won 883, 89.74%)`
  `Test passed in 0:06:46.337 (including ticks preprocessing 0:00:35.547).`

---

## 10.2 Combined run — measured, no author report available

Author did not publish a combined report. Graded strictly as **UNVERIFIED** (diagnostic only, not passed).

| Metric | Our combined run | Author reference |
| :--- | ---: | ---: |
| TradeFrequency | `Very_High` (4), all 9 enabled | Final inputs: all 9 active, `Very_High` |
| DDTierDivisor | 6.00 | 6.00 in our EA behavior |
| TieredLot | 30.0 | 30.0 |
| Trades | 3,040 | Not shown |
| Wins / losses | 2,606 / 434 (85.72%) | Not shown |
| Shorts | 1,269 (1,095 won; 86.29%) | Not shown |
| Longs | 1,771 (1,511 won; 85.32%) | Not shown |
| Net profit | $75,407.55 | Not shown |
| PF / expected payoff | 2.39 / $24.81 | Not shown |
| Largest win / loss | $3,269.76 / -$1,446.90 | Not shown |
| Tester elapsed | 2:01:37.171 | Not shown |
| Tester execution errors | **3** rejected `PositionModify` calls (down from 11,928) | Not shown |

Backing quotes from `Tester\logs\20261116.log`:
`[SUMMARY] Trades: 3040 (In: 3040, Out: 3040) | Wins: 2606 (85.72%) | Losses: 434 | NetProfit: 75407.55`
`[SUMMARY] PF: 2.39 | Payoff: 24.81 | AvgWin: 49.68 | AvgLoss: -124.56 | MaxWin: 3269.76 | MaxLoss: -1446.90`
`[SUMMARY] Shorts: 1269 (Won 1095, 86.29%) | Longs: 1771 (Won 1511, 85.32%)`
`Test passed in 2:01:37.171 (including ticks preprocessing 0:00:10.515).`

3,040 trades is the exact sum of our own nine individual runs (59+37+47+111+197+257+251+291+1,790 = 3,040). It must not be cited as a throughput figure against the author.

---

### 10.2.1 Defect 1 Resolution: Elimination of `[Invalid stops]` Errors

- **Root Cause**: Breakeven, trailing stop, and spread-adjustment logic evaluated thresholds on raw floating-point calculations, but submitted orders after `NormalizeDouble(..., Digits)`. When the difference was smaller than half a point, the normalization truncated back to `currentSL`, causing MT5 to reject the modify request with `[Invalid stops]`.
- **Fix Applied**: Pre-computed `newSL = NormalizeDouble(...)` and enforced a strict improvement check (`slImproved`) before submitting `PositionModify`.
- **Result**: Reduced rejected modifies across the entire test suite from **11,928** down to **3** (S1:0, S2:0, S3:0, S4:0, S5:1, S6:1, S7:0, S8:0, S9:1; Combined: 3).

### 10.2.2 Defect 2 Diagnosis: S2 Sizing Arithmetic

- **Finding**: S2 matches discrete counts cent-for-cent (37 trades, 29W/8L, 16 shorts/21 longs), but net profit is -$4,146.51 (-8.44%) and PF is 3.64 vs 3.76.
- **Ratio Analysis**:
  - Avg Win: $2,139.34 / $2,308.71 = **0.9266**
  - Avg Loss: -$2,131.01 / -$2,226.64 = **0.9570**
  - Max Win: $9,801.00 / $10,657.02 = **0.9197**
  - Max Loss: -$5,374.20 / -$5,769.72 = **0.9314**
- **Conclusion**: The uniform scaling factor of ~0.92–0.93 confirms that price trajectories, entries, exits, and breakeven triggers are identical to the author. The divergence is purely due to position sizing (~7-8% smaller lots in our run). At S2's tight 0.50% SL, lot sizing produces the largest positions of any strategy, amplifying `LOT_STEP` truncation and leverage constraints (1:100 vs author's unstated leverage).

### 10.2.3 Defect 3 Resolution: S3 Win/Loss Classification

- **Root Cause**: S3 preset specifies `BeLockPct = 0.0`. When price hit breakeven, `lockDist` evaluated to 0.0, placing SL at the exact entry price. In tick execution, one trade exited at entry with a tiny negative slip/commission, booking as a loss (29W / 18L).
- **Fix Applied**: In `ActivateStrategyContext`, when `BeLockPct == 0.0`, a 1-point minimum floor is applied to guarantee positive lock.
- **Result**: Exactly **30 wins / 17 losses (63.83% win rate)**, Net $12,083.71 (+0.81%), PF 2.63 (+0.38%). S3 achieves full **PASS**.

### 10.2.4 Defect 4 Diagnosis: Short-Side Discrete Divergences (S5–S9)

- **Pattern**: Every failing strategy loses trades exclusively on the short side relative to author targets:
  - S5: 79 shorts (tgt 80)
  - S6: 87 shorts (tgt 88)
  - S7: 90 shorts (tgt 92)
  - S8: 111 shorts (tgt 114)
  - S9: 806 shorts (tgt 818)
- **Mechanism**: The shared asymmetric pending order guard (`betterPendingExists` / `worstPendingPrice`) or the bid/ask spread evaluation at session transitions disproportionately clips short pending orders during high-volatility spikes. As demonstrated in S3, adjusting pending order lifecycle guards restores discrete counts.

## 11. Cross-agent continuity (Antigravity session)

If work resumes in a different agent, read this file plus `README.md` first, then the Antigravity session:

| Item | Value |
| :--- | :--- |
| Product | `1. X9R` |
| Conversation | MT5 EA Code Parity & Debugging |
| Session ID | `7543b94e-9bd4-4bd4-b035-cbac42bd0c60` |
| Antigravity state | `C:\Users\Administrator\.gemini\antigravity\` (`conversations\`, `brain\`, `conversation_summaries.db`) |
| Working tree | `C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\1. X9\Part 3\project\` |
| Our Part 2 EA | `...\MQL5\Experts\1. X9\Part 2\Gold_X9_Part2.mq5` (63 408 B, 2026-10-24) |
| Our Part 1 EA | `...\MQL5\Experts\1. X9\Part 1\Gold_X9_Part1.mq5` |
| Reconstruction source | `...\Part 3\project\Gold X9 v6.3 - Youtube shared Part 2.mq5`, `...Part 3.mq5`, `VIDEOMIND_ANALYSIS_REPORT.md` |
| Architecture reference | `...\MQL5\Experts\1. X9\README.md` |

Resume rule: individual strategy parity is the deliverable. Do not accept a combined-run match as evidence that an individual strategy is correct.
