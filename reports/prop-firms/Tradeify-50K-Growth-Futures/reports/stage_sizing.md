# Tradeify $50k Growth — stage sizing in whole contracts

The prop engine starts from a requested dollar risk and rounds to whole
micros. That hides the binding constraint: on NQ a single micro has a mean
losing trade of roughly USD 127-182, so one micro per sleeve is already
about 1% of a $50k account against a $2,000 trailing drawdown. This report
enumerates contract allocations per sleeve, enforces the four-mini
concurrent cap, and reports the odds at each.

## 1R per sleeve in the NT8 exports

| Sleeve | Instrument | 1R per mini | 1R per micro (0.1) |
|---|---|---:|---:|
| FVG Duo | NQ DEC26 | $1,452 | $145 |
| Flash ORB | NQ DEC26 | $1,150 | $115 |
| Gold ORB (RBE) | GC DEC26 | $813 | $81 |
| Sigma ORB | NQ DEC26 | $1,704 | $170 |
| Opening-Shock Continuation | NQ DEC26 | $1,089 | $109 |
| Overnight Bias ORB | NQ DEC26 | $1,226 | $123 |

## Allocation ladder

| Book | Minis/sleeve | Micros/sleeve | Risk per trade | % of $50k | R to $2k trail | Pass | Eval breach | Funded breach | Payout | Median payout days | Days below the $1,250 clip |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Challenge book | 0.1 | 1 | $512 | 1.02% | 3.9 | 67.4% | 32.6% | 40.0% | 45.6% | 57 | 0.6% |
| Challenge book | 0.2 | 2 | $1,024 | 2.05% | 1.9 | 61.9% | 38.1% | 48.5% | 34.6% | 35 | 5.4% |
| Challenge book | 0.3 | 3 | $1,536 | 3.07% | 1.3 | 63.3% | 36.7% | 48.8% | 33.5% | 31 | 10.6% |
| Challenge book | 0.5 | 5 | $2,560 | 5.12% | 0.8 | 63.9% | 36.1% | 45.6% | 34.9% | 31 | 21.2% |
| Challenge book | 1 | 10 | $5,120 | 10.24% | 0.4 | 68.2% | 31.8% | 38.4% | 41.7% | 32 | 31.9% |
| Funded book | 0.1 | 1 | $476 | 0.95% | 4.2 | 74.2% | 25.8% | 34.5% | 57.4% | 73 | 0.2% |
| Funded book | 0.2 | 2 | $951 | 1.90% | 2.1 | 64.3% | 35.7% | 44.4% | 39.8% | 40 | 3.2% |
| Funded book | 0.3 | 3 | $1,427 | 2.85% | 1.4 | 65.1% | 34.9% | 45.9% | 37.2% | 33 | 8.2% |
| Funded book | 0.5 | 5 | $2,378 | 4.76% | 0.8 | 69.1% | 30.9% | 43.9% | 39.3% | 31 | 16.3% |
| Funded book | 1 | 10 | $4,756 | 9.51% | 0.4 | 71.6% | 28.4% | 36.8% | 45.2% | 31 | 26.1% |
| Lower-risk pair | 0.1 | 1 | $238 | 0.48% | 8.4 | 86.4% | 12.8% | 19.0% | 64.1% | 164 | 0.0% |
| Lower-risk pair | 0.2 | 2 | $475 | 0.95% | 4.2 | 65.2% | 34.8% | 44.4% | 42.7% | 75 | 0.2% |
| Lower-risk pair | 0.3 | 3 | $713 | 1.43% | 2.8 | 60.2% | 39.8% | 53.6% | 32.5% | 52 | 1.8% |
| Lower-risk pair | 0.5 | 5 | $1,188 | 2.38% | 1.7 | 60.9% | 39.1% | 55.0% | 30.1% | 39 | 6.8% |
| Lower-risk pair | 1 | 10 | $2,376 | 4.75% | 0.8 | 66.8% | 33.2% | 47.8% | 35.3% | 36 | 19.0% |

## What to set, stage by stage

NT8 sizing is whole contracts, so the settings are contract counts, not
percentages. `FixedContracts` is the input on every sleeve; Flash ORB,
FVG Duo and Open Drive also expose `RiskPercent` with `UseFixedContracts`
off, but that scales position size with account equity and will exceed the
four-mini cap on a $50k account once the book is sized sanely.

| EA (NinjaScript) | Evaluation | Funded |
|---|---|---|
| FVG Duo (`FVG_Duo_NT8.cs`) | 1 micro (0.1), `SizingMode=FixedContracts`, on MNQ | not traded |
| Flash ORB (`FlashTriggerOrbNT8.cs`) | 1 micro, `UseFixedContracts=true`, `FixedContracts=1` on MNQ | 1 micro |
| Gold ORB RBE (`RangeBreakoutNT8.cs`) | 1 micro on MGC | 1 micro |
| Sigma ORB (`SigmaBreakoutNT8.cs`) | 1 micro on MNQ | 1 micro |
| Opening-Shock Continuation (`OpeningShockContinuationNT8.cs`) | not traded | 1 micro |
| Overnight Bias ORB (`OvernightBiasRangeBreakoutNT8.cs`) | lower-risk alternative to FVG | 1 micro (alternative book) |

One contract on MNQ/MGC equals one micro, so `FixedContracts=1` is the
minimum position; it is also the only allocation that keeps the book inside
a sane R buffer. Nothing scales with the account: the four-mini cap and the
$2,000 trail both bind first.

**Rows above one micro per sleeve are not tradeable recommendations.** The
simulator clips a day's loss at the $1,250 soft daily limit; once a single
trade's risk approaches that limit the clip stops being a stop and starts
hiding the loss, which is why the large-size rows do not degrade the way the
R-buffer column says they should. The last column shows how often the clip
binds: at one micro it is rare, above two micros it is routine.

Model limits: closed-PnL only, EOD trailing drawdown, no intraday floating
losses, whole-micro rounding is exact here because every sleeve is set to a
whole number of micros. 1R is a realized-loss proxy, not the initial stop.
