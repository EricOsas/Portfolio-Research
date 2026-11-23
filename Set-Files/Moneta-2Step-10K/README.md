# Moneta Funded $10,000 2-Step Standard — EA set files

Load one file per chart. The `.set` files only override the sizing, magic and
enable inputs; every other strategy input keeps its shipped default.

## Phase-1

Book target USD 50 per trade (actual USD 44.26, 89% of target).

| # | EA | Symbol | Lots | Risk USD | Magic |
|---|---|---|---:|---:|---:|
| 1 | Gold X9 Low | XAUUSD | 0.02 | 19.80 | 770101 |
| 2 | Overnight Bias ORB | USTEC | 0.40 | 24.46 | 770102 |

## Phase-2

Book target USD 50 per trade (actual USD 44.26, 89% of target).

| # | EA | Symbol | Lots | Risk USD | Magic |
|---|---|---|---:|---:|---:|
| 1 | Gold X9 Low | XAUUSD | 0.02 | 19.80 | 770201 |
| 2 | Overnight Bias ORB | USTEC | 0.40 | 24.46 | 770202 |

## Funded

Book target USD 100 per trade (actual USD 97.68, 98% of target).

| # | EA | Symbol | Lots | Risk USD | Magic |
|---|---|---|---:|---:|---:|
| 1 | Flash ORB | USTEC | 0.38 | 24.84 | 770301 |
| 2 | GotobiFix EURJPY | EURJPY | 0.24 | 24.99 | 770302 |
| 3 | Tokyo Coil | USDJPY | 0.14 | 23.39 | 770303 |
| 4 | Overnight Bias ORB | USTEC | 0.40 | 24.46 | 770304 |

## How to load a stage

1. Open one chart per row in the table and attach that EA.
2. `Right click > Load` the matching `.set` from this folder (or drag it onto the chart).
3. Confirm the size shown in the EA panel before enabling trading.
4. Keep the listed magic numbers: they separate stages in the report exports.

Sizing is written as whole lots rather than percent or cash risk because the broker
minimum (0.01 lot) is the binding constraint: on XAUUSD one 0.01 lot already risks
USD 0.00 at the model's 1R. Any percent or cash input
below that floor silently becomes 0.01 lot anyway.

### Before going live

- Check the broker's contract size and minimum volume for each symbol.
- Confirm the chart timeframes each EA expects (see its `MODEL.md`).
- Run one day on demo to compare the risk the EA reports against the table above.

### Stage notes

- Phase 1 (target 5%) and Phase 2 (target 10%) run the same book and the same lots; the
  binding constraint is Phase 2, which needs twice the R in the same 8% static budget.
- The funded stage drops gold. The 4% daily loss is a hard breach at Moneta, so the
  funded book is sized well below it.
- News: no new or held exposure from 5 minutes before to 5 minutes after high-impact
  releases, in evaluation and funded. The set files do not enable the EAs' news filters
  because some of them need a calendar CSV; flatten manually for those windows.
- Incidental opposing positions from independent EAs on the same account are allowed.
  Do not run opposing exposure deliberately across accounts.
