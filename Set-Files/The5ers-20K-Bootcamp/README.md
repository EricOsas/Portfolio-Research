# The5ers $20,000 Bootcamp — EA set files

Load one file per chart. The `.set` files only override the sizing, magic and
enable inputs; every other strategy input keeps its shipped default.

## Phase-1

Book target USD 50 per trade (actual USD 49.89, 100% of target).

| # | EA | Symbol | Lots | Risk USD | Magic |
|---|---|---|---:|---:|---:|
| 1 | Gold X9 | XAUUSD | 0.01 | 12.96 | 760101 |
| 2 | GotobiFix EURJPY | EURJPY | 0.12 | 12.49 | 760102 |
| 3 | GotobiFix USDJPY | USDJPY | 0.12 | 12.31 | 760103 |
| 4 | Open Drive | USTEC | 0.32 | 12.12 | 760104 |

## Phase-2

Book target USD 50 per trade (actual USD 49.89, 100% of target).

| # | EA | Symbol | Lots | Risk USD | Magic |
|---|---|---|---:|---:|---:|
| 1 | Gold X9 | XAUUSD | 0.01 | 12.96 | 760201 |
| 2 | GotobiFix EURJPY | EURJPY | 0.12 | 12.49 | 760202 |
| 3 | GotobiFix USDJPY | USDJPY | 0.12 | 12.31 | 760203 |
| 4 | Open Drive | USTEC | 0.32 | 12.12 | 760204 |

## Phase-3

Book target USD 50 per trade (actual USD 49.89, 100% of target).

| # | EA | Symbol | Lots | Risk USD | Magic |
|---|---|---|---:|---:|---:|
| 1 | Gold X9 | XAUUSD | 0.01 | 12.96 | 760301 |
| 2 | GotobiFix EURJPY | EURJPY | 0.12 | 12.49 | 760302 |
| 3 | GotobiFix USDJPY | USDJPY | 0.12 | 12.31 | 760303 |
| 4 | Open Drive | USTEC | 0.32 | 12.12 | 760304 |

## Funded

Book target USD 100 per trade (actual USD 97.68, 98% of target).

| # | EA | Symbol | Lots | Risk USD | Magic |
|---|---|---|---:|---:|---:|
| 1 | Flash ORB | USTEC | 0.38 | 24.84 | 760401 |
| 2 | GotobiFix EURJPY | EURJPY | 0.24 | 24.99 | 760402 |
| 3 | Tokyo Coil | USDJPY | 0.14 | 23.39 | 760403 |
| 4 | Overnight Bias ORB | USTEC | 0.40 | 24.46 | 760404 |

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

- Phase 1, 2 and 3 use the same four-sleeve book and the same lots; only the magic changes so the
  pass of each step is attributable.
- The funded stage drops Gold X9 and switches to Flash ORB + GotobiFix EURJPY + Tokyo Coil +
  Overnight Bias ORB. Keeping gold in the funded book is what produced the ~41% funded breach
  in the earlier model.
