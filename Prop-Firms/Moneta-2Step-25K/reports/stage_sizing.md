# Moneta 2-Step stage sizing with real lot floors

Account USD 25,000. Phase 1 target 5% (USD 1,250), Phase 2 target 10% (USD 2,500), 4% daily loss (USD 1,000), 8% static maximum loss (USD 2,000), 3 profitable days of at least 0.5% (USD 125) per phase and per payout cycle, 88% split, 14 calendar-day cycles approximated as 10 trading days.

Sizing rule: `lots = max(0.01, floor(target / sleeves / 1R_per_lot * 100) / 100)`, so the target is divided equally but gold cannot go below 0.01 lot and overshoots.

## 0.01-lot 1R by sleeve

| Sleeve | 0.01-lot 1R |
|---|---:|
| Gold X9 | $12.96 |
| Gold ORB (RBE) | $8.23 |
| Tokyo Coil | $1.67 |
| GotobiFix GBPJPY | $1.48 |
| GotobiFix EURJPY | $1.04 |
| GotobiFix USDJPY | $1.03 |
| FVG Duo | $0.88 |
| Sigma ORB | $0.83 |
| Noise Band Momentum | $0.67 |
| Flash ORB | $0.65 |
| Overnight Bias ORB | $0.61 |
| Opening-Shock Continuation | $0.54 |
| Vault Break | $0.47 |
| Open Drive | $0.38 |
| NQ Precision Bot | $0.26 |

## Books at each target

| Book | Sleeves | Target | Lots | Actual risk | % of $25k | Phase 1 pass | Both phases | Eval breach | Payout | Funded breach | Days | Expected first payout |
|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $50 | Gold X9 0.01, GotobiFix EURJPY 0.12, GotobiFix USDJPY 0.12, Open Drive 0.32 | $49.89 | 0.20% | 99.9% | 92.0% | 0.0% | 82.7% | 0.0% | 183 | $588 |
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $100 | Gold X9 0.01, GotobiFix EURJPY 0.24, GotobiFix USDJPY 0.24, Open Drive 0.65 | $87.20 | 0.35% | 99.8% | 96.7% | 0.1% | 94.1% | 0.2% | 150 | $596 |
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $150 | Gold X9 0.02, GotobiFix EURJPY 0.36, GotobiFix USDJPY 0.36, Open Drive 0.98 | $137.46 | 0.55% | 98.8% | 97.7% | 2.2% | 96.6% | 9.0% | 87 | $809 |
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $200 | Gold X9 0.03, GotobiFix EURJPY 0.48, GotobiFix USDJPY 0.48, Open Drive 1.31 | $187.73 | 0.75% | 93.5% | 84.7% | 15.3% | 81.2% | 49.7% | 58 | $885 |
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $300 | Gold X9 0.05, GotobiFix EURJPY 0.72, GotobiFix USDJPY 0.73, Open Drive 1.97 | $289.29 | 1.16% | 78.9% | 56.2% | 43.8% | 44.7% | 99.5% | 35 | $790 |
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $500 | Gold X9 0.09, GotobiFix EURJPY 1.20, GotobiFix USDJPY 1.21, Open Drive 3.29 | $490.35 | 1.96% | 67.4% | 40.9% | 59.1% | 24.7% | 100.0% | 23 | $813 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $50 | Gold X9 0.01, Overnight Bias ORB 0.40 | $37.41 | 0.15% | 99.9% | 88.2% | 0.0% | 72.4% | 0.0% | 194 | $544 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $100 | Gold X9 0.03, Overnight Bias ORB 0.81 | $88.39 | 0.35% | 95.7% | 90.5% | 9.5% | 87.6% | 30.5% | 75 | $916 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $150 | Gold X9 0.05, Overnight Bias ORB 1.22 | $139.38 | 0.56% | 79.8% | 57.3% | 42.7% | 48.2% | 97.4% | 42 | $756 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $200 | Gold X9 0.07, Overnight Bias ORB 1.63 | $190.36 | 0.76% | 75.3% | 49.3% | 50.7% | 36.6% | 100.0% | 31 | $781 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $300 | Gold X9 0.11, Overnight Bias ORB 2.45 | $292.32 | 1.17% | 65.1% | 38.4% | 61.6% | 22.0% | 100.0% | 23 | $776 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $500 | Gold X9 0.19, Overnight Bias ORB 4.08 | $495.63 | 1.98% | 57.4% | 31.4% | 68.6% | 12.3% | 100.0% | 19 | $806 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $50 | Gold X9 0.01, GotobiFix EURJPY 0.16, GotobiFix USDJPY 0.16 | $46.03 | 0.18% | 100.0% | 90.0% | 0.0% | 76.7% | 0.0% | 191 | $526 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $100 | Gold X9 0.02, GotobiFix EURJPY 0.32, GotobiFix USDJPY 0.32 | $92.06 | 0.37% | 99.4% | 98.4% | 1.3% | 97.6% | 3.3% | 104 | $762 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $150 | Gold X9 0.03, GotobiFix EURJPY 0.48, GotobiFix USDJPY 0.48 | $138.10 | 0.55% | 92.8% | 84.0% | 16.0% | 79.1% | 48.9% | 68 | $811 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $200 | Gold X9 0.05, GotobiFix EURJPY 0.64, GotobiFix USDJPY 0.64 | $197.09 | 0.79% | 80.7% | 57.8% | 42.2% | 47.7% | 97.0% | 40 | $749 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $300 | Gold X9 0.07, GotobiFix EURJPY 0.96, GotobiFix USDJPY 0.97 | $290.18 | 1.16% | 73.5% | 47.9% | 52.1% | 33.0% | 100.0% | 30 | $752 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $500 | Gold X9 0.12, GotobiFix EURJPY 1.60, GotobiFix USDJPY 1.62 | $488.29 | 1.95% | 65.6% | 38.3% | 61.7% | 20.6% | 100.0% | 22 | $794 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $50 | Flash ORB 0.19, GotobiFix EURJPY 0.12, Tokyo Coil 0.07, Overnight Bias ORB 0.20 | $48.84 | 0.20% | 12.2% | 0.0% | 0.0% | 0.0% | 0.0% | nan | $0 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $100 | Flash ORB 0.38, GotobiFix EURJPY 0.24, Tokyo Coil 0.14, Overnight Bias ORB 0.40 | $97.68 | 0.39% | 99.4% | 33.9% | 0.0% | 10.6% | 0.0% | 232 | $63 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $150 | Flash ORB 0.57, GotobiFix EURJPY 0.36, Tokyo Coil 0.22, Overnight Bias ORB 0.61 | $148.80 | 0.59% | 100.0% | 84.9% | 0.0% | 70.9% | 0.0% | 195 | $423 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $200 | Flash ORB 0.76, GotobiFix EURJPY 0.48, Tokyo Coil 0.29, Overnight Bias ORB 0.81 | $197.63 | 0.79% | 100.0% | 95.8% | 0.1% | 91.5% | 0.1% | 156 | $531 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $300 | Flash ORB 1.14, GotobiFix EURJPY 0.72, Tokyo Coil 0.44, Overnight Bias ORB 1.22 | $297.59 | 1.19% | 99.5% | 98.4% | 1.0% | 97.6% | 2.5% | 108 | $689 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $500 | Flash ORB 1.91, GotobiFix EURJPY 1.20, Tokyo Coil 0.74, Overnight Bias ORB 2.04 | $498.16 | 1.99% | 96.8% | 93.7% | 6.3% | 91.0% | 25.9% | 68 | $902 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $50 | Flash ORB 0.25, GotobiFix EURJPY 0.16, Overnight Bias ORB 0.27 | $49.51 | 0.20% | 17.2% | 0.0% | 0.0% | 0.0% | 0.0% | nan | $0 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $100 | Flash ORB 0.50, GotobiFix EURJPY 0.32, Overnight Bias ORB 0.54 | $99.02 | 0.40% | 98.8% | 36.7% | 0.0% | 12.3% | 0.0% | 230 | $79 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $150 | Flash ORB 0.76, GotobiFix EURJPY 0.48, Overnight Bias ORB 0.81 | $149.18 | 0.60% | 99.8% | 82.5% | 0.0% | 71.8% | 0.0% | 189 | $383 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $200 | Flash ORB 1.01, GotobiFix EURJPY 0.64, Overnight Bias ORB 1.09 | $199.30 | 0.80% | 99.9% | 94.4% | 0.1% | 90.3% | 0.3% | 152 | $500 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $300 | Flash ORB 1.52, GotobiFix EURJPY 0.96, Overnight Bias ORB 1.63 | $298.97 | 1.20% | 99.3% | 97.8% | 1.5% | 96.5% | 4.2% | 108 | $674 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $500 | Flash ORB 2.54, GotobiFix EURJPY 1.60, Overnight Bias ORB 2.72 | $498.92 | 2.00% | 91.3% | 79.6% | 20.4% | 72.3% | 64.9% | 63 | $719 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $50 | Flash ORB 0.19, Gold X9 0.01, GotobiFix EURJPY 0.12, Tokyo Coil 0.07 | $49.57 | 0.20% | 99.9% | 90.4% | 0.0% | 74.5% | 0.0% | 194 | $572 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $100 | Flash ORB 0.38, Gold X9 0.01, GotobiFix EURJPY 0.24, Tokyo Coil 0.14 | $86.18 | 0.34% | 100.0% | 97.5% | 0.0% | 93.1% | 0.0% | 164 | $598 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $150 | Flash ORB 0.57, Gold X9 0.02, GotobiFix EURJPY 0.36, Tokyo Coil 0.22 | $137.42 | 0.55% | 99.6% | 99.1% | 0.8% | 98.6% | 3.0% | 95 | $796 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $200 | Flash ORB 0.76, Gold X9 0.03, GotobiFix EURJPY 0.48, Tokyo Coil 0.29 | $186.98 | 0.75% | 94.0% | 87.6% | 12.4% | 84.0% | 45.3% | 65 | $862 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $300 | Flash ORB 1.14, Gold X9 0.05, GotobiFix EURJPY 0.72, Tokyo Coil 0.44 | $287.79 | 1.15% | 81.6% | 61.0% | 39.0% | 51.3% | 97.5% | 38 | $810 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $500 | Flash ORB 1.91, Gold X9 0.09, GotobiFix EURJPY 1.20, Tokyo Coil 0.74 | $490.05 | 1.96% | 70.7% | 45.4% | 54.6% | 28.9% | 100.0% | 24 | $874 |

## End-to-end plan with the funded switch

| Phase book | Phase target | Funded book | Funded target | Both phases | Eval breach | Payout | Conditional payout | Funded breach | Days |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 4-sleeve | $150 | no gold | $200 | 97.3% | 2.6% | 97.1% | 99.7% | 0.1% | 93 |
| 4-sleeve | $150 | no gold, 3-sleeve | $200 | 97.6% | 2.3% | 97.4% | 99.8% | 0.3% | 93 |
| 4-sleeve | $150 | with gold | $100 | 97.7% | 2.2% | 97.5% | 99.8% | 0.0% | 98 |
| X9 + OBR pair | $50 | no gold | $200 | 89.2% | 0.0% | 81.1% | 90.9% | 0.0% | 184 |
| X9 + OBR pair | $50 | no gold, 3-sleeve | $200 | 89.2% | 0.0% | 81.3% | 91.2% | 0.1% | 183 |
| X9 + OBR pair | $50 | with gold | $100 | 89.6% | 0.0% | 80.5% | 89.9% | 0.0% | 187 |
| 3-sleeve (no index) | $100 | no gold | $200 | 98.4% | 1.3% | 97.8% | 99.4% | 0.1% | 109 |
| 3-sleeve (no index) | $100 | no gold, 3-sleeve | $200 | 98.8% | 1.0% | 98.1% | 99.3% | 0.3% | 108 |
| 3-sleeve (no index) | $100 | with gold | $100 | 98.6% | 1.0% | 98.0% | 99.3% | 0.0% | 112 |

Recommended: **3-sleeve (no index)** at USD 100 through Phase 1-2, then **no gold** at USD 200 when funded (97.8% first payout, 0.1% funded breach).


## Selected allocations

| Stage | Book | Target | Lots | Actual risk | Both phases / payout | Eval breach |
|---|---|---:|---|---:|---:|---:|
| Phase 1-2 | 4-sleeve | $150 | Gold X9 0.02, GotobiFix EURJPY 0.36, GotobiFix USDJPY 0.36, Open Drive 0.98 | $137.46 | 97.7% / 96.6% | 2.2% |
| Phase 1-2 | X9 + OBR pair | $50 | Gold X9 0.01, Overnight Bias ORB 0.40 | $37.41 | 88.2% / 72.4% | 0.0% |
| Phase 1-2 | 3-sleeve (no index) | $100 | Gold X9 0.02, GotobiFix EURJPY 0.32, GotobiFix USDJPY 0.32 | $92.06 | 98.4% / 97.6% | 1.3% |
| Funded | no gold | $200 | Flash ORB 0.76, GotobiFix EURJPY 0.48, Tokyo Coil 0.29, Overnight Bias ORB 0.81 | $197.63 | 95.5% / 0.1% | – |
| Funded | no gold, 3-sleeve | $200 | Flash ORB 1.01, GotobiFix EURJPY 0.64, Overnight Bias ORB 1.09 | $199.30 | 95.6% / 0.3% | – |
| Funded | with gold | $100 | Flash ORB 0.38, Gold X9 0.01, GotobiFix EURJPY 0.24, Tokyo Coil 0.14 | $86.18 | 95.5% / 0.0% | – |

Machine-readable allocation for the EA set files: [ea_allocation.json](ea_allocation.json).
