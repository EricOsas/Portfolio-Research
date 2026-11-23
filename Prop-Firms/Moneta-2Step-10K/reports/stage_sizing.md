# Moneta 2-Step stage sizing with real lot floors

Account USD 10,000. Phase 1 target 5% (USD 500), Phase 2 target 10% (USD 1,000), 4% daily loss (USD 400), 8% static maximum loss (USD 800), 3 profitable days of at least 0.5% (USD 50) per phase and per payout cycle, 88% split, 14 calendar-day cycles approximated as 10 trading days.

Sizing rule: `lots = max(0.01, floor(target / sleeves / 1R_per_lot * 100) / 100)`, so the target is divided equally but gold cannot go below 0.01 lot and overshoots.

## 0.01-lot 1R by sleeve

| Sleeve | 0.01-lot 1R |
|---|---:|
| Gold X9 (Very high) | $13.09 |
| Gold X9 (Moderate) | $11.65 |
| Gold X9 (High) | $11.02 |
| Gold X9 (Extremely low) | $10.15 |
| Gold X9 (Low) | $9.90 |
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
| 4-sleeve | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $12 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.03, GotobiFix USDJPY 0.03, Open Drive 0.08 | $19.13 | 0.19% | 100.0% | 78.5% | 0.0% | 42.9% | 0.0% | 215 | $155 |
| 4-sleeve | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $25 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.06, GotobiFix USDJPY 0.06, Open Drive 0.16 | $28.36 | 0.28% | 100.0% | 92.8% | 0.0% | 80.4% | 0.0% | 194 | $235 |
| 4-sleeve | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $38 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.09, GotobiFix USDJPY 0.09, Open Drive 0.24 | $37.60 | 0.38% | 100.0% | 96.3% | 0.0% | 91.3% | 0.0% | 166 | $239 |
| 4-sleeve | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $50 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.12, GotobiFix USDJPY 0.12, Open Drive 0.32 | $46.83 | 0.47% | 99.9% | 97.7% | 0.1% | 96.0% | 0.1% | 145 | $224 |
| 4-sleeve | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $75 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.18, GotobiFix USDJPY 0.18, Open Drive 0.49 | $65.67 | 0.66% | 99.4% | 97.9% | 1.0% | 96.5% | 1.9% | 116 | $259 |
| 4-sleeve | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $100 | Gold X9 (Low) 0.02, GotobiFix EURJPY 0.24, GotobiFix USDJPY 0.24, Open Drive 0.65 | $94.04 | 0.94% | 96.4% | 90.5% | 9.5% | 87.2% | 30.5% | 76 | $318 |
| 4-sleeve | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY + Open Drive | $150 | Gold X9 (Low) 0.03, GotobiFix EURJPY 0.36, GotobiFix USDJPY 0.36, Open Drive 0.98 | $141.25 | 1.41% | 87.3% | 70.7% | 29.3% | 61.9% | 83.5% | 50 | $319 |
| X9 + OBR pair | Gold X9 (Low) + Overnight Bias ORB | $12 | Gold X9 (Low) 0.01, Overnight Bias ORB 0.10 | $16.01 | 0.16% | 100.0% | 70.3% | 0.0% | 35.3% | 0.0% | 216 | $126 |
| X9 + OBR pair | Gold X9 (Low) + Overnight Bias ORB | $25 | Gold X9 (Low) 0.01, Overnight Bias ORB 0.20 | $22.13 | 0.22% | 100.0% | 85.4% | 0.0% | 61.1% | 0.0% | 203 | $203 |
| X9 + OBR pair | Gold X9 (Low) + Overnight Bias ORB | $38 | Gold X9 (Low) 0.01, Overnight Bias ORB 0.30 | $28.24 | 0.28% | 100.0% | 92.0% | 0.0% | 79.2% | 0.0% | 188 | $249 |
| X9 + OBR pair | Gold X9 (Low) + Overnight Bias ORB | $50 | Gold X9 (Low) 0.02, Overnight Bias ORB 0.40 | $44.26 | 0.44% | 100.0% | 99.6% | 0.0% | 98.7% | 0.1% | 121 | $377 |
| X9 + OBR pair | Gold X9 (Low) + Overnight Bias ORB | $75 | Gold X9 (Low) 0.03, Overnight Bias ORB 0.61 | $66.99 | 0.67% | 99.3% | 98.1% | 1.9% | 96.9% | 8.2% | 87 | $462 |
| X9 + OBR pair | Gold X9 (Low) + Overnight Bias ORB | $100 | Gold X9 (Low) 0.05, Overnight Bias ORB 0.81 | $99.02 | 0.99% | 91.2% | 79.4% | 20.6% | 73.4% | 62.7% | 58 | $492 |
| X9 + OBR pair | Gold X9 (Low) + Overnight Bias ORB | $150 | Gold X9 (Low) 0.07, Overnight Bias ORB 1.22 | $143.89 | 1.44% | 82.8% | 62.8% | 37.2% | 52.2% | 95.2% | 43 | $473 |
| 3-sleeve (no index) | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY | $12 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.04, GotobiFix USDJPY 0.04 | $18.17 | 0.18% | 99.8% | 70.5% | 0.0% | 37.2% | 0.0% | 216 | $123 |
| 3-sleeve (no index) | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY | $25 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.08, GotobiFix USDJPY 0.08 | $26.44 | 0.26% | 99.9% | 85.8% | 0.0% | 66.5% | 0.0% | 203 | $191 |
| 3-sleeve (no index) | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY | $38 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.12, GotobiFix USDJPY 0.12 | $34.71 | 0.35% | 100.0% | 92.3% | 0.0% | 81.6% | 0.0% | 185 | $227 |
| 3-sleeve (no index) | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY | $50 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.16, GotobiFix USDJPY 0.16 | $42.97 | 0.43% | 99.9% | 95.4% | 0.0% | 88.9% | 0.0% | 168 | $249 |
| 3-sleeve (no index) | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY | $75 | Gold X9 (Low) 0.02, GotobiFix EURJPY 0.24, GotobiFix USDJPY 0.24 | $69.41 | 0.69% | 97.3% | 90.2% | 9.7% | 86.1% | 22.0% | 103 | $320 |
| 3-sleeve (no index) | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY | $100 | Gold X9 (Low) 0.03, GotobiFix EURJPY 0.32, GotobiFix USDJPY 0.32 | $95.85 | 0.96% | 95.5% | 88.0% | 12.0% | 82.9% | 39.2% | 75 | $394 |
| 3-sleeve (no index) | Gold X9 (Low) + GotobiFix EURJPY + GotobiFix USDJPY | $150 | Gold X9 (Low) 0.05, GotobiFix EURJPY 0.48, GotobiFix USDJPY 0.48 | $148.72 | 1.49% | 84.7% | 65.7% | 34.3% | 54.8% | 89.6% | 50 | $389 |
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
| with gold | Flash ORB + Gold X9 (Low) + GotobiFix EURJPY + Tokyo Coil | $12 | Flash ORB 0.04, Gold X9 (Low) 0.01, GotobiFix EURJPY 0.03, Tokyo Coil 0.01 | $17.31 | 0.17% | 99.9% | 70.2% | 0.0% | 35.2% | 0.0% | 219 | $123 |
| with gold | Flash ORB + Gold X9 (Low) + GotobiFix EURJPY + Tokyo Coil | $25 | Flash ORB 0.09, Gold X9 (Low) 0.01, GotobiFix EURJPY 0.06, Tokyo Coil 0.03 | $27.04 | 0.27% | 100.0% | 87.4% | 0.0% | 56.4% | 0.0% | 210 | $210 |
| with gold | Flash ORB + Gold X9 (Low) + GotobiFix EURJPY + Tokyo Coil | $38 | Flash ORB 0.14, Gold X9 (Low) 0.01, GotobiFix EURJPY 0.09, Tokyo Coil 0.05 | $36.78 | 0.37% | 100.0% | 95.2% | 0.0% | 82.6% | 0.0% | 190 | $268 |
| with gold | Flash ORB + Gold X9 (Low) + GotobiFix EURJPY + Tokyo Coil | $50 | Flash ORB 0.19, Gold X9 (Low) 0.01, GotobiFix EURJPY 0.12, Tokyo Coil 0.07 | $46.51 | 0.47% | 100.0% | 98.1% | 0.0% | 94.5% | 0.0% | 168 | $265 |
| with gold | Flash ORB + Gold X9 (Low) + GotobiFix EURJPY + Tokyo Coil | $75 | Flash ORB 0.28, Gold X9 (Low) 0.01, GotobiFix EURJPY 0.18, Tokyo Coil 0.11 | $65.32 | 0.65% | 100.0% | 99.2% | 0.0% | 98.1% | 0.0% | 138 | $270 |
| with gold | Flash ORB + Gold X9 (Low) + GotobiFix EURJPY + Tokyo Coil | $100 | Flash ORB 0.38, Gold X9 (Low) 0.02, GotobiFix EURJPY 0.24, Tokyo Coil 0.14 | $93.02 | 0.93% | 100.0% | 99.9% | 0.1% | 99.8% | 0.4% | 90 | $342 |
| with gold | Flash ORB + Gold X9 (Low) + GotobiFix EURJPY + Tokyo Coil | $150 | Flash ORB 0.57, Gold X9 (Low) 0.03, GotobiFix EURJPY 0.36, Tokyo Coil 0.22 | $141.20 | 1.41% | 94.5% | 89.6% | 10.4% | 85.7% | 42.4% | 61 | $379 |

## End-to-end plan with the funded switch

| Phase book | Phase target | Funded book | Funded target | Both phases | Eval breach | Payout | Conditional payout | Funded breach | Days |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 4-sleeve | $75 | no gold | $100 | 98.2% | 1.1% | 96.7% | 98.5% | 0.5% | 118 |
| 4-sleeve | $75 | no gold, 3-sleeve | $100 | 97.9% | 1.1% | 96.5% | 98.6% | 0.9% | 118 |
| 4-sleeve | $75 | with gold | $100 | 97.9% | 1.1% | 97.2% | 99.3% | 0.4% | 115 |
| X9 + OBR pair | $50 | no gold | $100 | 99.7% | 0.0% | 98.8% | 99.1% | 0.4% | 116 |
| X9 + OBR pair | $50 | no gold, 3-sleeve | $100 | 99.5% | 0.0% | 98.5% | 99.0% | 1.1% | 116 |
| X9 + OBR pair | $50 | with gold | $100 | 99.6% | 0.0% | 99.1% | 99.5% | 0.4% | 114 |
| 3-sleeve (no index) | $50 | no gold | $100 | 95.3% | 0.0% | 91.4% | 95.9% | 0.4% | 162 |
| 3-sleeve (no index) | $50 | no gold, 3-sleeve | $100 | 95.0% | 0.0% | 90.7% | 95.5% | 0.5% | 161 |
| 3-sleeve (no index) | $50 | with gold | $100 | 95.2% | 0.0% | 92.3% | 97.0% | 0.3% | 160 |

Recommended: **X9 + OBR pair** at USD 50 through Phase 1-2, then **no gold** at USD 100 when funded (98.8% first payout, 0.4% funded breach).


## Selected allocations

| Stage | Book | Target | Lots | Actual risk | Both phases / payout | Eval breach |
|---|---|---:|---|---:|---:|---:|
| Phase 1-2 | 4-sleeve | $75 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.18, GotobiFix USDJPY 0.18, Open Drive 0.49 | $65.67 | 97.9% / 96.5% | 1.0% |
| Phase 1-2 | X9 + OBR pair | $50 | Gold X9 (Low) 0.02, Overnight Bias ORB 0.40 | $44.26 | 99.6% / 98.7% | 0.0% |
| Phase 1-2 | 3-sleeve (no index) | $50 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.16, GotobiFix USDJPY 0.16 | $42.97 | 95.4% / 88.9% | 0.0% |
| Funded | no gold | $100 | Flash ORB 0.38, GotobiFix EURJPY 0.24, Tokyo Coil 0.14, Overnight Bias ORB 0.40 | $97.68 | 98.2% / 0.7% | – |
| Funded | no gold, 3-sleeve | $100 | Flash ORB 0.50, GotobiFix EURJPY 0.32, Overnight Bias ORB 0.54 | $99.02 | 98.2% / 1.0% | – |
| Funded | with gold | $100 | Flash ORB 0.38, Gold X9 (Low) 0.02, GotobiFix EURJPY 0.24, Tokyo Coil 0.14 | $93.02 | 100.0% / 0.4% | – |

Machine-readable allocation for the EA set files: [ea_allocation.json](ea_allocation.json).
