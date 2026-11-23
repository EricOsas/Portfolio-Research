# Moneta Funded $25,000 2-Step Standard — EA set files

Load one file per chart. The `.set` files only override the sizing, magic and
enable inputs; every other strategy input keeps its shipped default.

## Phase-1

Book target USD 100 per trade (actual USD 92.06, 92% of target).

| # | EA | Symbol | Lots | Risk USD | Magic |
|---|---|---|---:|---:|---:|
| 1 | Gold X9 | XAUUSD | 0.02 | 25.91 | 770101 |
| 2 | GotobiFix EURJPY | EURJPY | 0.32 | 33.32 | 770102 |
| 3 | GotobiFix USDJPY | USDJPY | 0.32 | 32.83 | 770103 |

## Phase-2

Book target USD 100 per trade (actual USD 92.06, 92% of target).

| # | EA | Symbol | Lots | Risk USD | Magic |
|---|---|---|---:|---:|---:|
| 1 | Gold X9 | XAUUSD | 0.02 | 25.91 | 770201 |
| 2 | GotobiFix EURJPY | EURJPY | 0.32 | 33.32 | 770202 |
| 3 | GotobiFix USDJPY | USDJPY | 0.32 | 32.83 | 770203 |

## Funded

Book target USD 200 per trade (actual USD 197.63, 99% of target).

| # | EA | Symbol | Lots | Risk USD | Magic |
|---|---|---|---:|---:|---:|
| 1 | Flash ORB | USTEC | 0.76 | 49.68 | 770301 |
| 2 | GotobiFix EURJPY | EURJPY | 0.48 | 49.97 | 770302 |
| 3 | Tokyo Coil | USDJPY | 0.29 | 48.46 | 770303 |
| 4 | Overnight Bias ORB | USTEC | 0.81 | 49.52 | 770304 |

## How to load a stage

1. Open one chart per row in the table and attach that EA.
2. `Right click > Load` the matching `.set` from this folder (or drag it onto the chart).
3. Confirm the size shown in the EA panel before enabling trading.
4. Keep the listed magic numbers: they separate stages in the report exports.

Sizing is written as whole lots rather than percent or cash risk because the broker
minimum (0.01 lot) is the binding constraint: on XAUUSD one 0.01 lot already risks
USD 12.96 at the model's 1R. Any percent or cash input
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
