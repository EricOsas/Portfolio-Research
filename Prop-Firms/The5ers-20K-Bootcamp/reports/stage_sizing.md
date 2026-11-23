# The5ers $20k Bootcamp — stage sizing with real lot floors

The main prop engine sizes a book in continuous dollars. Real EAs size in
whole lots, and 0.01 lot is the smallest position the broker allows, so each
sleeve has a dollar risk floor. On a $5k step the floor, not the percentage,
decides the risk. This report models `risk_i = max(pct x balance, 0.01-lot 1R_i)`
per sleeve, with the evaluation book through Steps 1-3 and the funded book
after funding (the real switch, not a product of two independent runs).

## 0.01-lot 1R per sleeve (mean losing trade at 0.01 lot, from the export)

| Sleeve | Instrument | 1R at 0.01 lot |
|---|---|---:|
| Gold X9 | XAUUSD | $20.02 |
| GotobiFix EURJPY | EURJPY | $1.05 |
| GotobiFix USDJPY | USDJPY | $1.14 |
| Open Drive | USTEC | $0.04 |
| Flash ORB | USTEC | $0.73 |
| Tokyo Coil | USDJPY | $0.13 |
| Overnight Bias ORB | USTEC | $0.08 |

Gold X9 is the binding floor: 0.01 lot is already ~$20 of mean risk, which is
0.4% of a $5k step by itself. The FX and index sleeves cost $0.04-$1.15 at the
same minimum, so they cannot be scaled down to match a percentage either —
the book is gold-heavy at minimum size no matter what percentage you set.

## Scenarios

| Scenario | Stage 1 risk | Step 2 | Step 3 | Funded | Reach funded | Eval breach | First payout | Funded breach | Median payout days | Expected first payout |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A. Physical minimum, no scaling | 0.44% | 0.22% | 0.15% | 0.11% | 63.4% | 36.6% | 60.8% | 44.6% | 69 | $130 |
| B. 0.05%/sleeve, scaled | 0.55% | 0.35% | 0.28% | 0.25% | 65.0% | 35.0% | 62.8% | 42.7% | 65 | $139 |
| C. 0.125%/sleeve, scaled | 0.77% | 0.57% | 0.51% | 0.50% | 65.2% | 34.8% | 61.9% | 57.7% | 58 | $187 |
| D. 0.25%/sleeve, scaled | 1.15% | 1.00% | 1.00% | 1.00% | 57.3% | 42.7% | 51.5% | 88.3% | 39 | $320 |
| E. 0.5%/sleeve, scaled | 2.00% | 2.00% | 2.00% | 2.00% | 44.5% | 55.5% | 37.9% | 96.3% | 25 | $508 |
| F. Min eval, funded without X9 at 0.125%/sleeve | 0.55% | 0.35% | 0.28% | 0.50% | 65.0% | 35.0% | 64.9% | 1.0% | 67 | $67 |
| G. Min eval, funded without X9 at 0.25%/sleeve | 0.55% | 0.35% | 0.28% | 1.00% | 65.0% | 35.0% | 63.3% | 26.1% | 66 | $132 |

Realized risk is the average of (sum of sleeve dollar risk / start-of-day balance)
over that stage's trading days, so it shows the minimum-lot distortion directly.
"Reach funded" is the probability of passing all three steps; "first payout" includes
the funded stage; "funded breach" is conditional on reaching the funded account.

## Reading it

- Scenarios B-E all start from the same stage-1 floor, so stage 1 is nearly
  identical; the percentage only starts to bite on Steps 2-3 and funded.
- Scaling the funded book with the balance is what breaks it: at 0.125%/sleeve
  the funded book with Gold X9 breaches the 4% floor in more than half of paths.
- The fix is to drop Gold X9 from the funded book (F-G): the remaining sleeves
  are cheap at 0.01 lot, so the same percentage is a much smaller book and the
  funded breach collapses.

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
