# Tradeify $50,000 Growth — strategy settings

Tradeify is a futures account, so these are NinjaTrader strategy parameters, not
MT5 `.set` files. NinjaTrader has no portable preset file; set the values below in
the strategy dialog and save a workspace.

| Stage | Sleeves | Contracts |
|---|---|---|
| Challenge | FVG Duo, Flash ORB, Gold ORB (RBE), Sigma ORB | 1 micro each (MNQ/MGC) |
| Funded | Flash ORB, Gold ORB (RBE), Opening-Shock, Sigma ORB | 1 micro each |
| Lower risk | Flash ORB + Overnight Bias ORB | 1 micro each |

Required parameter changes:

- `UseFixedContracts = true` and `FixedContracts = 1` on every sleeve.
- Keep `UseFixedContracts = true` on Flash, FVG Duo and Open Drive so a
  `RiskPercent` input cannot scale the book.
- Do not raise any sleeve above one micro: the four-mini cap does not bind, but
  the USD 2,000 trailing drawdown does, and above one micro the simulator's
  USD 1,250 daily-loss clip starts hiding losses.

One micro per sleeve is already about 1% of the $50k account. See
`Prop-Firms/Tradeify-50K-Growth-Futures/reports/stage_sizing.md` in the research
repository for the per-sleeve 1R values and pass/payout odds.
