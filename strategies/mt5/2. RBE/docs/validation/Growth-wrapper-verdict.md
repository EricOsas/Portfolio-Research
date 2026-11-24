# Growth RBE C1 wrapper result

**October 4 NT8 port update: old odds are not estimates for the new close-first workflow.** The source can hold opposite strategy positions simultaneously. This wrapper preserved those positions but did not distinguish virtual strategy books from actual futures account netting or enforce Tradeify's prohibition on same-instrument or correlated opposing holdings across accounts. The user has now selected close-first-then-reverse within an instance, with existing long-only/short-only controls available for independent charts. Two chart books are not proof of two independent broker inventories; a native account/feed comparison and a workflow rerun are needed before quoting replacement pass, breach or payout odds. See `../docs/nt8-port-contract.md` and https://help.tradeify.co/en/articles/10495868-rules-hedging-correlated-products .

EA defaults now carry the frozen RBE-C1 trading configuration. Native compilation completed with zero errors and zero warnings. A default-driven M1 OHLC replay, with only research/display switches overridden, completed with 1,141 trades from January 2020 through October 2 2026. The temporary tester launch file was removed; the user does not need to maintain a preset. Existing running EA instances retain their old loaded inputs until reattached or reset; installing new defaults does not silently change active instances.

The offline Growth wrapper is implemented. It uses the user-selected MGC instrument, CME $10 point value and 0.10 tick size, the Tradeify $2.12 round-trip fee, and one assumed slippage tick each way. Total modeled round-trip friction is $4.12 per contract, with a doubled-friction sensitivity of $8.24. Current publicly documented Growth evaluation and funded stages are modeled separately. The source quotes are XAUUSD CFD paths replayed with synthetic ticks; these results are explicitly futures proxies, not native MGC-feed execution evidence.

Source capture is bounded: 1,961,963 ordered quote records, 47,087,112 bytes, across 1,744 logged sessions. Research path logging is off by default. The wrapper preserves overlapping positions when marking combined account equity, rounds prices adversely to the MGC tick grid, sizes integer contracts, includes friction inside the risk budget, enforces total concurrent exposure, flattens at a DLL crossing and skips later signals that session. EOD trailing floors are checked intraday. Funded floors lock at starting balance plus $100; evaluation floors do not lock. Funded DLL increases apply next session after an eligible EOD balance.

## Primary 25K fixture

| Fixed budget | Taken of 1,141 | Skipped | Worst monthly funded breach baseline | Doubled friction |
|---|---:|---:|---:|---:|
| $100 | 22 | 1,119 | 0.00% | 0.00% |
| $200 | 723 | 418 | 0.57% | 0.69% |
| $300 | 1,089 | 52 | 25.54% | 28.97% |
| $500 | 1,141 | 0 | 61.01% | 61.87% |

All 22 signals fitting $100 risk occurred in 2020. None of the 250 source signals in 2026 fits $200. Before account controls, $300 fits 198 of those 250 signals and $500 fits all 250. The low breach figures at $100/$200 are therefore not evidence of representative current strategy coverage. This is a minimum-contract cash-risk constraint, unrelated to the user's accepted low strategy frequency or synthetic tick standard.

The source strategy remains a research candidate. The $25K MGC sleeve is not assigned for deployment: budgets retaining most source signals spend too much of its $1,000 trailing room in these proxy simulations. Larger Growth accounts are included in the report; for example, baseline worst monthly funded breach at $300 is 1.42% on 50K, 0.02% on 100K, and 0.00% observed on 150K. These are estimates conditional on the historical sample, not guaranteed probabilities or automatic account recommendations. No new safety threshold was inferred after the results.

## Proof and reproducibility

- `python -m unittest discover -s RBE/validation -p test_growth_wrapper.py`: five focused tests pass for integer sizing and exposure, intraday floor touches, stage-specific floor locking, zero-trade sessions, and DLL flatten/skip behavior.
- `python RBE/validation/growth_wrapper.py`: 10,000 simulated 21-session months for each method, risk budget, account size and cost sensitivity, for evaluation and funded stages separately. Four sizes, four budgets, two friction levels, daily i.i.d. and contiguous five-day block resampling produce 1,280,000 stage paths. Seed is 20261003.
- `growth_results.json`: numerical results, source hashes, stage-specific metrics and modeling assumptions.
- `growth_sizing_ledger.csv`: per-signal sizes, modeled risk and skip/cap reasons. Reproduce without rerunning Monte Carlo using `python RBE/validation/export_growth_ledger.py`.
- `Tradeify_Growth_RBE_C1_SOP.docx`: report follows the supplied Lightning SOP's page style, ten-section structure and table patterns, with Growth/RBE content. The retained reference is unchanged.

Payout figures measure eligibility and capped hypothetical first-payout opportunity, including minimum balance, qualifying days, consistency and the payout share. They do not simulate actual withdrawals, approval delay, recurring payouts, account-purchase fees or annual take-home income. All source windows are retrospective development evidence. Target checks are conservatively deferred to EOD. Source export timestamps are second precision; same-second events use conservative open/mark/close ordering. Quote prices retain CFD spread, and no native futures basis, spread, roll or order-routing parity is claimed.

**Verdict: GROWTH-RISK-CANDIDATE_PROXY; offline wrapper complete, 25K MGC deployment unsupported at a budget preserving current source coverage.** Next evidence gate is a frozen native MGC comparison at an explicitly selected account size and executable integer risk budget. No strategy tuning was performed to repair the account mismatch. No live orders, account changes or payouts were initiated.

## Rule sources

- Commission: https://help.tradeify.co/en/articles/10468315-trading-commission-fees
- Evaluation: https://help.tradeify.co/en/articles/10495915-growth-evaluation-accounts
- Trailing floor: https://help.tradeify.co/en/articles/10495897-rules-trailing-max-drawdowns
- DLL: https://help.tradeify.co/en/articles/10468321-rules-daily-loss-limit
- Funded payout: https://help.tradeify.co/en/articles/11083796-growth-funded-account-payout-policy
- MGC economics: https://www.cmegroup.com/education/lessons/micro-gold-and-micro-silver-futures-product-overview

Public rules checked October 3 2026 during the run. Deliverable finalized October 4 2026 Africa Lagos time. Account-specific purchase terms and dashboard values remain authoritative for deployment.
