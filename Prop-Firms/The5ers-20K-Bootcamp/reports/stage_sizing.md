# The5ers $20k Bootcamp — stage sizing with real lot floors

The main prop engine sizes a book in continuous dollars. Real EAs size in
whole lots, and 0.01 lot is the smallest position the broker allows, so each
sleeve has a dollar risk floor. On a $5k step the floor, not the percentage,
decides the risk. This report models `risk_i = max(pct x balance, 0.01-lot 1R_i)`
per sleeve, with the evaluation book through Steps 1-3 and the funded book
after funding (the real switch, not a product of two independent runs). A payout
requires at least USD 300 gross (USD 150 net at the 50% split).

## 0.01-lot 1R per sleeve (mean losing trade at 0.01 lot, from the export)

| Sleeve | Instrument | 1R at 0.01 lot |
|---|---|---:|
| Gold X9 (Low) | XAUUSD | $9.90 |
| GotobiFix EURJPY | EURJPY | $1.04 |
| GotobiFix USDJPY | USDJPY | $1.03 |
| Open Drive | USTEC | $0.38 |
| Flash ORB | USTEC | $0.65 |
| Tokyo Coil | USDJPY | $1.67 |
| Overnight Bias ORB | USTEC | $0.61 |

Gold X9 is the binding floor: 0.01 lot is already ~$20 of mean risk, which is
0.4% of a $5k step by itself. The FX and index sleeves cost $0.04-$1.15 at the
same minimum, so they cannot be scaled down to match a percentage either —
the book is gold-heavy at minimum size no matter what percentage you set.

## Scenarios

| Scenario | Stage 1 risk | Step 2 | Step 3 | Funded | Reach funded | Eval breach | First payout | Funded breach | Median payout days | Expected first payout |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A. Physical minimum, no scaling | 0.24% | 0.12% | 0.08% | 0.07% | 29.9% | 0.2% | 9.4% | 0.0% | 226 | $18 |
| B. 0.05%/sleeve, scaled | 0.34% | 0.25% | 0.21% | 0.20% | 76.6% | 0.3% | 51.2% | 0.0% | 214 | $102 |
| C. 0.125%/sleeve, scaled | 0.57% | 0.50% | 0.50% | 0.50% | 97.2% | 1.7% | 95.4% | 0.6% | 143 | $262 |
| D. 0.25%/sleeve, scaled | 1.00% | 1.00% | 1.00% | 1.00% | 81.9% | 18.1% | 80.0% | 26.0% | 80 | $345 |
| E. 0.5%/sleeve, scaled | 2.00% | 2.00% | 2.00% | 2.00% | 52.0% | 48.0% | 47.1% | 84.3% | 40 | $355 |
| F. Min eval, funded without X9 at 0.125%/sleeve | 0.34% | 0.25% | 0.21% | 0.50% | 76.6% | 0.3% | 56.4% | 0.1% | 210 | $129 |
| G. Min eval, funded without X9 at 0.25%/sleeve | 0.34% | 0.25% | 0.21% | 1.00% | 76.6% | 0.3% | 62.0% | 6.8% | 206 | $196 |

Realized risk is the average of (sum of sleeve dollar risk / start-of-day balance)
over that stage's trading days, so it shows the minimum-lot distortion directly.
"Reach funded" is the probability of passing all three steps; "first payout" includes
the funded stage; "funded breach" is conditional on reaching the funded account.

## Two-sleeve pairs

Pairs are the only books where the minimum-lot split is visible: the cheap sleeve
cannot be scaled down to match the expensive one, so the split is not 50/50.

| Pair | 0.01-lot risk (sleeve 1 / 2) | Total | % of $5k step | Split (1 / 2) | Reach funded | Eval breach | Payout | Funded breach | Balanced risk | Balanced payout | Balanced breach |
|---|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|
| Gold X9 (Low) + Overnight Bias ORB | $9.90 / $0.61 | $10.51 | 0.21% | 94% / 6% | 26.4% | 0.2% | 8.1% | 0.0% | $19.80 | 30.5% | 0.0% |
| GotobiFix EURJPY + Overnight Bias ORB | $1.04 / $0.61 | $1.65 | 0.03% | 63% / 37% | 0.0% | 0.0% | 0.0% | 0.0% | $2.08 | 0.0% | 0.0% |
| GotobiFix USDJPY + Overnight Bias ORB | $1.03 / $0.61 | $1.64 | 0.03% | 63% / 37% | 0.0% | 0.0% | 0.0% | 0.0% | $2.05 | 0.0% | 0.0% |
| Flash ORB + Overnight Bias ORB | $0.65 / $0.61 | $1.27 | 0.03% | 52% / 48% | 0.0% | 0.0% | 0.0% | 0.0% | $1.31 | 0.0% | 0.0% |
| Gold ORB (RBE) + Gold X9 (Low) | $8.23 / $9.90 | $18.13 | 0.36% | 45% / 55% | 85.7% | 1.8% | 68.0% | 0.0% | $19.80 | 74.9% | 0.0% |
| GotobiFix EURJPY + Tokyo Coil | $1.04 / $1.67 | $2.71 | 0.05% | 38% / 62% | 0.0% | 0.0% | 0.0% | 0.0% | $3.34 | 0.0% | 0.0% |

"Balanced" sizes both sleeves to the larger one's 0.01-lot risk (a placeable
whole-lot size for the cheap sleeve), so the book is no longer gold-dominated but
the total risk roughly doubles. The minimum-lot column is the gold-dominated
reality; the USD 25 equal-split model (12.50 per sleeve) is not placeable on Gold
X9 or Gold ORB (RBE), which need more than that for one 0.01 lot.

## Reading it

- Scenarios B-E all start from the same stage-1 floor, so stage 1 is nearly
  identical; the percentage only starts to bite on Steps 2-3 and funded.
- Scaling the funded book with the balance is what breaks it: at 0.125%/sleeve
  the funded book with Gold X9 breaches the 4% floor in more than half of paths.
- The fix is to drop Gold X9 from the funded book (F-G): the remaining sleeves
  are cheap at 0.01 lot, so the same percentage is a much smaller book and the
  funded breach collapses.

## Books sized to a target risk, in whole 0.01 lots

0.01 lot is not a strategy choice, it is the broker floor. This table sizes each
book to a target risk instead, rounds down to 0.01 lots, and never goes below the
floor, so gold still overshoots its share.

| Book | Target | Lots | Actual risk | % of $5k | % of $20k | Reach funded | Eval breach | Payout | Funded breach | Median days |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Phase book (4 sleeves) | $25 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.06, GotobiFix USDJPY 0.06, Open Drive 0.16 | $28.36 | 0.57% | 0.14% | 79.9% | 0.8% | 53.5% | 0.0% | 213 |
| Phase book (4 sleeves) | $50 | Gold X9 (Low) 0.01, GotobiFix EURJPY 0.12, GotobiFix USDJPY 0.12, Open Drive 0.32 | $46.83 | 0.94% | 0.23% | 89.4% | 6.1% | 80.7% | 0.0% | 177 |
| Phase book (4 sleeves) | $100 | Gold X9 (Low) 0.02, GotobiFix EURJPY 0.24, GotobiFix USDJPY 0.24, Open Drive 0.65 | $94.04 | 1.88% | 0.47% | 76.3% | 23.7% | 75.1% | 8.5% | 93 |
| Phase book (X9 + OBR pair) | $25 | Gold X9 (Low) 0.01, Overnight Bias ORB 0.20 | $22.13 | 0.44% | 0.11% | 66.2% | 0.2% | 37.4% | 0.0% | 220 |
| Phase book (X9 + OBR pair) | $50 | Gold X9 (Low) 0.02, Overnight Bias ORB 0.40 | $44.26 | 0.89% | 0.22% | 93.4% | 5.7% | 91.0% | 0.0% | 143 |
| Phase book (X9 + OBR pair) | $100 | Gold X9 (Low) 0.05, Overnight Bias ORB 0.81 | $99.02 | 1.98% | 0.50% | 74.0% | 26.0% | 72.9% | 16.7% | 70 |
| Funded book (no gold) | $25 | Flash ORB 0.09, GotobiFix EURJPY 0.06, Tokyo Coil 0.03, Overnight Bias ORB 0.10 | $23.26 | 0.47% | 0.12% | 0.0% | 0.1% | 0.0% | 0.0% | nan |
| Funded book (no gold) | $50 | Flash ORB 0.19, GotobiFix EURJPY 0.12, Tokyo Coil 0.07, Overnight Bias ORB 0.20 | $48.84 | 0.98% | 0.24% | 39.1% | 1.9% | 15.0% | 0.0% | 230 |
| Funded book (no gold) | $100 | Flash ORB 0.38, GotobiFix EURJPY 0.24, Tokyo Coil 0.14, Overnight Bias ORB 0.40 | $97.68 | 1.95% | 0.49% | 85.2% | 12.0% | 79.6% | 0.4% | 159 |
| Low-risk book (Flash + OBR) | $25 | Flash ORB 0.19, Overnight Bias ORB 0.20 | $24.65 | 0.49% | 0.12% | 0.1% | 1.3% | 0.0% | 0.0% | nan |
| Low-risk book (Flash + OBR) | $50 | Flash ORB 0.38, Overnight Bias ORB 0.40 | $49.30 | 0.99% | 0.25% | 37.0% | 11.8% | 17.3% | 0.0% | 218 |
| Low-risk book (Flash + OBR) | $100 | Flash ORB 0.76, Overnight Bias ORB 0.81 | $99.20 | 1.98% | 0.50% | 62.1% | 35.0% | 56.7% | 7.7% | 146 |

Reading: the cheap books only work once they are sized up, and their limit is
time, not risk. At USD 25 total the cheap pairs pass Step 1 in 96-99% of paths but
cannot finish three steps inside 252 days; at USD 50 they complete. Gold still
cannot be sized below 0.01 lot, so any gold book overshoots its target share.

## Execution plan with the funded switch

The plan places the four-sleeve evaluation book at a USD 50 target through
Steps 1-3, then switches to the no-gold funded book at USD 100. Both stages
share one path matrix, so the switch is simulated, not multiplied.

| Phase lots (USD 50) | Phase risk | Funded lots (USD 100) | Funded risk | Reach funded | Eval breach | First payout | Funded breach | Median payout days | Expected first payout |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|
| Gold X9 (Low) 0.01, GotobiFix EURJPY 0.12, GotobiFix USDJPY 0.12, Open Drive 0.32 | $46.83 | Flash ORB 0.38, GotobiFix EURJPY 0.24, Tokyo Coil 0.14, Overnight Bias ORB 0.40 | $97.68 | 89.6% | 5.9% | 80.9% | 0.5% | 174 | $183 |

Conditional first payout after funding is 90.4%; median payout on successful paths is $210.

## Recommended settings (verified against the EA sources)

Sleeves and inputs are in the MetaQuotes terminal tree, not in this repo.
Hold these unchanged through Steps 1-3; do not scale them as the balance grows.

| EA (file) | Input | Challenge value | Funded value |
|---|---|---|---|
| Gold X9 (`1. X9/Gold_X9_v6_3.mq5`) | `Lotsizing_Method` / `FixedLots` | `Manual_Lotsize` / `0.01` | not traded |
| GotobiFix (`5. GotobiFix/GotobiFix.mq5`) | `Lots` / `MaxExposureLots` | `0.05` / `0.10` per pair | `0.24` / `0.50` (EURJPY) |
| Open Drive (`4. Index Book/3. OpenDrive`) | `RiskMoney` (with `UseFixedLots=false`) | `8` | not traded |
| Flash ORB (`4. Index Book/7. FlashTriggerORB`) | `RiskMoney` (with `UseFixedSize=false`) | not traded | `25` |
| Tokyo Coil (`3. TokyoCoil`) | `RiskMoney` (with `RiskPct` ignored) | not traded | `25` |
| Overnight Bias ORB (`4. Index Book/2. OvernightBiasRangeBreakout`) | `RiskMoney` (with `UseFixedSize=false`) | not traded | `25` |

Why these inputs: Gold X9 defaults to `Tiered_Lotsizing`, whose per-trade budget
is `(TieredLot/DDTierDivisor) x balance x 0.0001 x RiskWeight`; with the shipped
`TieredLot=30` and `RiskWeight` summing to ~2.84 over nine strategies that is
about $1.50 per strategy at $5k, below the 0.01-lot floor, so the EA always
min-lots on a small account. `Manual_Lotsize` makes that explicit.
GotobiFix has only fixed lots; Flash ORB, Overnight Bias and the rest of the
Index Book have `RiskMoney` (fixed cash) or fixed lots, not percentage risk.
Only Open Drive (`RiskPercent`) and Tokyo Coil (`RiskPct`) offer percentage
sizing, which is why they are listed with fixed `RiskMoney` when the plan calls
for a constant dollar book.

Model limits: closed-PnL only (no floating-loss breaches), no spread/slippage
beyond the export, no evaluation fees, funded scale-up ladder not modeled.
1R is a realized-loss proxy, not the initial stop.
