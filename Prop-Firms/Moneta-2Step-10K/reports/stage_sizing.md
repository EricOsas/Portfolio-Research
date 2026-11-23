# Moneta 2-Step stage sizing with real lot floors

Account USD 10,000. Phase 1 target 5% (USD 500), Phase 2 target 10% (USD 1,000), 4% daily loss (USD 400), 8% static maximum loss (USD 800), 3 profitable days of at least 0.5% (USD 50) per phase and per payout cycle, 88% split, 14 calendar-day cycles approximated as 10 trading days.

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

| Book | Sleeves | Target | Lots | Actual risk | % of $10k | Phase 1 pass | Both phases | Eval breach | Payout | Funded breach | Days | Expected first payout |
|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $12 | Gold X9 0.01, GotobiFix EURJPY 0.03, GotobiFix USDJPY 0.03, Open Drive 0.08 | $22.19 | 0.22% | 98.2% | 96.0% | 3.7% | 94.4% | 10.4% | 96 | $338 |
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $25 | Gold X9 0.01, GotobiFix EURJPY 0.06, GotobiFix USDJPY 0.06, Open Drive 0.16 | $31.42 | 0.31% | 98.3% | 96.5% | 3.3% | 95.5% | 11.4% | 89 | $339 |
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $38 | Gold X9 0.01, GotobiFix EURJPY 0.09, GotobiFix USDJPY 0.09, Open Drive 0.24 | $40.65 | 0.41% | 98.2% | 96.3% | 3.6% | 95.1% | 13.7% | 84 | $332 |
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $50 | Gold X9 0.01, GotobiFix EURJPY 0.12, GotobiFix USDJPY 0.12, Open Drive 0.32 | $49.89 | 0.50% | 98.0% | 96.1% | 3.9% | 94.9% | 13.6% | 78 | $347 |
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $75 | Gold X9 0.01, GotobiFix EURJPY 0.18, GotobiFix USDJPY 0.18, Open Drive 0.49 | $68.73 | 0.69% | 97.2% | 95.0% | 4.9% | 93.3% | 20.7% | 69 | $365 |
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $100 | Gold X9 0.01, GotobiFix EURJPY 0.24, GotobiFix USDJPY 0.24, Open Drive 0.65 | $87.20 | 0.87% | 92.9% | 84.8% | 15.2% | 80.0% | 54.1% | 60 | $340 |
| 4-sleeve | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $150 | Gold X9 0.02, GotobiFix EURJPY 0.36, GotobiFix USDJPY 0.36, Open Drive 0.98 | $137.46 | 1.38% | 76.5% | 53.2% | 46.8% | 42.2% | 99.7% | 33 | $316 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $12 | Gold X9 0.01, Overnight Bias ORB 0.10 | $19.07 | 0.19% | 98.2% | 96.3% | 3.3% | 94.9% | 10.0% | 97 | $339 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $25 | Gold X9 0.01, Overnight Bias ORB 0.20 | $25.18 | 0.25% | 98.2% | 96.4% | 3.4% | 94.9% | 10.0% | 93 | $341 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $38 | Gold X9 0.01, Overnight Bias ORB 0.30 | $31.30 | 0.31% | 98.4% | 96.6% | 3.3% | 95.4% | 8.9% | 90 | $355 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $50 | Gold X9 0.01, Overnight Bias ORB 0.40 | $37.41 | 0.37% | 98.6% | 96.8% | 3.1% | 95.8% | 10.4% | 85 | $354 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $75 | Gold X9 0.02, Overnight Bias ORB 0.61 | $63.21 | 0.63% | 81.9% | 58.6% | 41.4% | 48.4% | 96.9% | 41 | $307 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $100 | Gold X9 0.03, Overnight Bias ORB 0.81 | $88.39 | 0.88% | 70.6% | 45.5% | 54.5% | 32.4% | 100.0% | 29 | $295 |
| X9 + OBR pair | Gold X9 + Overnight Bias ORB | $150 | Gold X9 0.05, Overnight Bias ORB 1.22 | $139.38 | 1.39% | 62.8% | 37.8% | 62.2% | 19.7% | 100.0% | 22 | $317 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $12 | Gold X9 0.01, GotobiFix EURJPY 0.04, GotobiFix USDJPY 0.04 | $21.23 | 0.21% | 98.2% | 96.5% | 3.4% | 94.7% | 10.5% | 99 | $337 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $25 | Gold X9 0.01, GotobiFix EURJPY 0.08, GotobiFix USDJPY 0.08 | $29.49 | 0.29% | 98.4% | 96.5% | 3.4% | 95.7% | 9.5% | 93 | $337 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $38 | Gold X9 0.01, GotobiFix EURJPY 0.12, GotobiFix USDJPY 0.12 | $37.76 | 0.38% | 98.6% | 97.1% | 2.7% | 95.9% | 9.8% | 89 | $340 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $50 | Gold X9 0.01, GotobiFix EURJPY 0.16, GotobiFix USDJPY 0.16 | $46.03 | 0.46% | 98.7% | 97.2% | 2.8% | 96.0% | 9.9% | 85 | $341 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $75 | Gold X9 0.01, GotobiFix EURJPY 0.24, GotobiFix USDJPY 0.24 | $62.57 | 0.63% | 97.0% | 90.8% | 9.2% | 86.5% | 33.3% | 75 | $326 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $100 | Gold X9 0.02, GotobiFix EURJPY 0.32, GotobiFix USDJPY 0.32 | $92.06 | 0.92% | 80.8% | 57.7% | 42.3% | 46.5% | 97.7% | 39 | $299 |
| 3-sleeve (no index) | Gold X9 + GotobiFix EURJPY + GotobiFix USDJPY | $150 | Gold X9 0.03, GotobiFix EURJPY 0.48, GotobiFix USDJPY 0.48 | $138.10 | 1.38% | 72.4% | 45.9% | 54.1% | 30.6% | 100.0% | 29 | $305 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $12 | Flash ORB 0.04, GotobiFix EURJPY 0.03, Tokyo Coil 0.01, Overnight Bias ORB 0.05 | $10.47 | 0.10% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | nan | $0 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $25 | Flash ORB 0.09, GotobiFix EURJPY 0.06, Tokyo Coil 0.03, Overnight Bias ORB 0.10 | $23.26 | 0.23% | 31.3% | 0.1% | 0.0% | 0.0% | 0.0% | nan | $0 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $38 | Flash ORB 0.14, GotobiFix EURJPY 0.09, Tokyo Coil 0.05, Overnight Bias ORB 0.15 | $36.05 | 0.36% | 98.9% | 22.5% | 0.0% | 3.4% | 0.0% | 234 | $8 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $50 | Flash ORB 0.19, GotobiFix EURJPY 0.12, Tokyo Coil 0.07, Overnight Bias ORB 0.20 | $48.84 | 0.49% | 99.6% | 66.4% | 0.0% | 43.1% | 0.0% | 214 | $101 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $75 | Flash ORB 0.28, GotobiFix EURJPY 0.18, Tokyo Coil 0.11, Overnight Bias ORB 0.30 | $73.77 | 0.74% | 99.9% | 93.7% | 0.0% | 87.9% | 0.0% | 167 | $207 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $100 | Flash ORB 0.38, GotobiFix EURJPY 0.24, Tokyo Coil 0.14, Overnight Bias ORB 0.40 | $97.68 | 0.98% | 99.8% | 98.1% | 0.3% | 96.4% | 0.7% | 129 | $240 |
| no gold | Flash ORB + GotobiFix EURJPY + Tokyo Coil + Overnight Bias ORB | $150 | Flash ORB 0.57, GotobiFix EURJPY 0.36, Tokyo Coil 0.22, Overnight Bias ORB 0.61 | $148.80 | 1.49% | 98.9% | 97.3% | 2.4% | 96.1% | 7.9% | 89 | $306 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $12 | Flash ORB 0.06, GotobiFix EURJPY 0.04, Overnight Bias ORB 0.06 | $11.76 | 0.12% | 0.2% | 0.0% | 0.0% | 0.0% | 0.0% | nan | $0 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $25 | Flash ORB 0.12, GotobiFix EURJPY 0.08, Overnight Bias ORB 0.13 | $24.12 | 0.24% | 64.8% | 0.2% | 0.0% | 0.0% | 0.0% | nan | $0 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $38 | Flash ORB 0.19, GotobiFix EURJPY 0.12, Overnight Bias ORB 0.20 | $37.14 | 0.37% | 98.8% | 27.6% | 0.0% | 6.6% | 0.0% | 233 | $17 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $50 | Flash ORB 0.25, GotobiFix EURJPY 0.16, Overnight Bias ORB 0.27 | $49.51 | 0.49% | 99.5% | 68.4% | 0.0% | 45.4% | 0.0% | 212 | $109 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $75 | Flash ORB 0.38, GotobiFix EURJPY 0.24, Overnight Bias ORB 0.40 | $74.28 | 0.74% | 99.9% | 92.9% | 0.1% | 87.7% | 0.1% | 162 | $191 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $100 | Flash ORB 0.50, GotobiFix EURJPY 0.32, Overnight Bias ORB 0.54 | $99.02 | 0.99% | 99.6% | 97.6% | 0.6% | 95.8% | 1.0% | 127 | $237 |
| no gold, 3-sleeve | Flash ORB + GotobiFix EURJPY + Overnight Bias ORB | $150 | Flash ORB 0.76, GotobiFix EURJPY 0.48, Overnight Bias ORB 0.81 | $149.18 | 1.49% | 98.2% | 95.8% | 4.0% | 94.2% | 11.8% | 88 | $304 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $12 | Flash ORB 0.04, Gold X9 0.01, GotobiFix EURJPY 0.03, Tokyo Coil 0.01 | $20.37 | 0.20% | 98.1% | 95.7% | 3.9% | 94.1% | 9.8% | 99 | $343 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $25 | Flash ORB 0.09, Gold X9 0.01, GotobiFix EURJPY 0.06, Tokyo Coil 0.03 | $30.10 | 0.30% | 98.6% | 96.9% | 2.9% | 95.3% | 9.2% | 95 | $351 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $38 | Flash ORB 0.14, Gold X9 0.01, GotobiFix EURJPY 0.09, Tokyo Coil 0.05 | $39.83 | 0.40% | 98.5% | 97.2% | 2.6% | 96.1% | 9.0% | 89 | $349 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $50 | Flash ORB 0.19, Gold X9 0.01, GotobiFix EURJPY 0.12, Tokyo Coil 0.07 | $49.57 | 0.50% | 98.9% | 97.7% | 2.2% | 97.1% | 9.1% | 84 | $353 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $75 | Flash ORB 0.28, Gold X9 0.01, GotobiFix EURJPY 0.18, Tokyo Coil 0.11 | $68.38 | 0.68% | 98.9% | 97.7% | 2.3% | 96.8% | 9.2% | 77 | $358 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $100 | Flash ORB 0.38, Gold X9 0.01, GotobiFix EURJPY 0.24, Tokyo Coil 0.14 | $86.18 | 0.86% | 99.1% | 98.0% | 2.0% | 97.1% | 10.3% | 71 | $365 |
| with gold | Flash ORB + Gold X9 + GotobiFix EURJPY + Tokyo Coil | $150 | Flash ORB 0.57, Gold X9 0.02, GotobiFix EURJPY 0.36, Tokyo Coil 0.22 | $137.42 | 1.37% | 82.5% | 61.0% | 39.0% | 50.7% | 97.2% | 36 | $332 |

## End-to-end plan with the funded switch

| Phase book | Phase target | Funded book | Funded target | Both phases | Eval breach | Payout | Conditional payout | Funded breach | Days |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 4-sleeve | $25 | no gold | $100 | 96.7% | 3.2% | 96.4% | 99.8% | 0.8% | 92 |
| 4-sleeve | $25 | no gold, 3-sleeve | $100 | 96.6% | 3.3% | 96.3% | 99.6% | 1.1% | 92 |
| 4-sleeve | $25 | with gold | $50 | 96.4% | 3.5% | 95.4% | 98.9% | 8.4% | 90 |
| X9 + OBR pair | $50 | no gold | $100 | 97.4% | 2.5% | 97.3% | 99.8% | 0.7% | 88 |
| X9 + OBR pair | $50 | no gold, 3-sleeve | $100 | 97.4% | 2.6% | 97.0% | 99.7% | 1.4% | 88 |
| X9 + OBR pair | $50 | with gold | $50 | 97.2% | 2.7% | 96.2% | 99.0% | 9.4% | 85 |
| 3-sleeve (no index) | $50 | no gold | $100 | 97.3% | 2.6% | 97.0% | 99.7% | 0.8% | 89 |
| 3-sleeve (no index) | $50 | no gold, 3-sleeve | $100 | 97.1% | 2.9% | 96.7% | 99.6% | 1.4% | 88 |
| 3-sleeve (no index) | $50 | with gold | $50 | 97.0% | 2.9% | 96.0% | 99.0% | 9.3% | 84 |

Recommended: **X9 + OBR pair** at USD 50 through Phase 1-2, then **no gold** at USD 100 when funded (97.3% first payout, 0.7% funded breach).


## Selected allocations

| Stage | Book | Target | Lots | Actual risk | Both phases / payout | Eval breach |
|---|---|---:|---|---:|---:|---:|
| Phase 1-2 | 4-sleeve | $25 | Gold X9 0.01, GotobiFix EURJPY 0.06, GotobiFix USDJPY 0.06, Open Drive 0.16 | $31.42 | 96.5% / 95.5% | 3.3% |
| Phase 1-2 | X9 + OBR pair | $50 | Gold X9 0.01, Overnight Bias ORB 0.40 | $37.41 | 96.8% / 95.8% | 3.1% |
| Phase 1-2 | 3-sleeve (no index) | $50 | Gold X9 0.01, GotobiFix EURJPY 0.16, GotobiFix USDJPY 0.16 | $46.03 | 97.2% / 96.0% | 2.8% |
| Funded | no gold | $100 | Flash ORB 0.38, GotobiFix EURJPY 0.24, Tokyo Coil 0.14, Overnight Bias ORB 0.40 | $97.68 | 98.2% / 0.7% | – |
| Funded | no gold, 3-sleeve | $100 | Flash ORB 0.50, GotobiFix EURJPY 0.32, Overnight Bias ORB 0.54 | $99.02 | 98.2% / 1.0% | – |
| Funded | with gold | $50 | Flash ORB 0.19, Gold X9 0.01, GotobiFix EURJPY 0.12, Tokyo Coil 0.07 | $49.57 | 99.3% / 9.1% | – |

Machine-readable allocation for the EA set files: [ea_allocation.json](ea_allocation.json).
