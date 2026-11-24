# Twin v5: MT5 / NinjaTrader 8 source forks

**Status:** Research implementations. Static source checks passed. **Neither platform has been compiled or tested in the user's terminal, nor has broker reconnect/order behaviour been runtime-verified. Do not trade live until those gates pass.**

Built from the supplied `VaultBreak.mq5`, its `StrategyEngine.mqh`, `ExecutionRuntime.mqh`, `ChartVisuals.mqh`, and `VaultBreakNT8(1).cs`. These are source forks, not a reimplementation of every broker safeguard from memory. They keep the source's ownership journals, risk-in-account-currency sizing, chart objects, cost assumptions, logging, broker context checks and exposure reservation. Research signal sections and bracket orientation are new and must pass native compilation, playback and recovery tests.

## Files

- `OpeningShock/OpeningShock.mq5`, plus its three `.mqh` files. **MT5** opening-shock continuation.
- `OpeningShock/OpeningShockContinuationNT8.cs`. **NT8** opening-shock continuation.
- `PostCloseFade/PostCloseFade.mq5`, plus its three `.mqh` files. **MT5** post-close shock fade for CFD research.
- `PostCloseFade/PostCloseShockFadeNT8.cs`. **NT8 research-backtest only** post-close fade. *Realtime NQ futures entry is deliberately blocked.*

## Frozen intended rules (New York local time, auto DST)

| | Opening Shock Continuation | Post-Close Shock Fade |
|---|---|---|
| Signal | At 10:00, direction of 09:30–10:00 price movement | At 16:00, **opposite** direction of 15:30–16:00 movement |
| Reference | Mean of up to 20 fully completed earlier 09:30–16:00 RTH ranges; at least 15 required | Mean of 15 completed earlier RTH ranges, **skipping the most recent completed RTH session** |
| Minimum shock | `0.30 × reference` | `0.20 × reference` |
| Initial stop | `0.30 × reference` | `0.30 × reference` |
| Target | `0.20 × reference` | `0.06 × reference` |
| Time exit | 60 minutes from fill; hard-flat no later than **15:55 ET** | **01:00 ET next day** (00:00 Central), stop or target first |
| Trades | 1 per day | 1 per day; no Friday/weekend signals |
| Direction | Long/short | Long/short |
| Execution | Following executable M1 open / market quote | First available post-close M1 quote; skips unavailable markets |

**Backtest distinction:** Opening-shock entries target 10:00/10:01 ET on the next executable minute. The previous Python result used 1-minute NQ futures OHLCV. MT5 CFD spreads and market closures differ. The post-close research figure came from an NQ proxy, **not** a CFD bid/ask backtest. The C# and MQL5 strategies have not been proven to reproduce the historical P&L or trade lists.


## Tradeify futures session restriction — verified 2026-10-29

- Tradeify requires **all futures positions flat by 16:45 ET** (15:45 CT) on regular trading days, **12:59 ET** on holiday shortened days. This applies to Evaluation, Sim Funded, and Live accounts. CME closes for maintenance 17:00–18:00 ET.
- Trading after 18:00 ET and holding until the following day is permitted **within that same 18:00–16:45 ET trading session**. It is not permission to hold across maintenance.
- An internal **16:40 ET** flatten target gives five minutes of buffer, but is not an exchange or Tradeify requirement.
- **NT8 PostCloseShockFade remains realtime-entry blocked.** Its researched 16:00 ET entry / 01:00 ET exit crosses Tradeify's flat-by time and cannot be enabled without materially changing and retesting the model. The current historical NT8 research mode does not enforce Tradeify's earlier liquidation.
- Do **not** simply shift the original 16:00 ET entry to 18:00 ET or change its exit to 16:40 ET and assume historical results are preserved. Either is a new strategy requiring a fresh backtest and cost/risk audit.
- MT5 PostCloseFade is intended for eligible CFD brokers, not a Tradeify futures account; CFD trading-hour rules depend on the broker.

Official Tradeify rule: https://help.tradeify.co/en/articles/10495876-rules-permitted-times-to-trade

## Install

**MT5:** Copy each model's `.mq5` and its three `.mqh` files into the same folder under `MQL5/Experts/` in MetaTrader's Data Folder. Open the `.mq5` in MetaEditor, compile, and run the Strategy Tester in M1/tick mode on your CFD symbol. Do not combine the two sets of `.mqh` into one folder: their copies deliberately retain the sample's helper names.

**NT8:** Copy each `.cs` into the `NinjaTrader 8/bin/Custom/Strategies/` directory, then import/compile in NinjaScript Editor. Run the Strategy Analyzer with exchange **ETH M1** historical source. The code supports NQ, MNQ, or NNQ where matching data series exist. Tick-level validation and execution fill-parity remain required. `PostCloseShockFadeNT8` only admits historical research entries; it cannot place live NQ after-hours orders.

## Preserved from template

- Owned-order and account-context recovery boundaries, journals and locks.
- Protected stops and targets; OCO treatment and stop-first assumed intrabar collisions for research checks.
- Risk-based integer contract sizing in NT8; broker lot-step sizing in MT5.
- One account/contract ownership namespace per model (`91008031` / `91008032`).
- Historical chart display infrastructure and native broker-protection tracking.
- Commission and slippage reserve controls, change/close paths and logs.
- NT8 signal NQ source series even when execution is MNQ/NNQ.

## Native acceptance gates before any live use

1. **Compile** both native platform projects. Fix real MetaEditor / NT8 compiler errors; static text checks cannot replace compilation.
2. **Instrument clock**: compare timestamped signals and completed M1 history at DST boundaries against the research dates. Confirm broker server-to-New-York offset and the nontrading overnight window.
3. **Fill parity**: compare *every* signal/stop/target/time exit against NQ backtest trade logs. Verify round-to-tick effects, opposite side, same-minute stop/target collisions, missed quotes, broker stops-level and spread.
4. **Safety**: test long and short partial fills, rejections, intraday disconnection, reboot/restart, retained stop/target OCO, old-order ownership, and shared-account opposing strategies in NT8/MT5 paper accounts.
5. **Prop constraints**: use the firm-specific trailing equity DD, loss caps, holidays and liquidation rules. The observed historical models did **not** pass a $1,000 max-trailing-DD gate at the assumptions tested.
6. **MT5 CFD**: test native bid/ask and holiday/session data. NQ futures 1-contract $20/point costs and P&L do not transfer directly to broker CFD lot sizing.

## Static check

Run `python validate_sources.py`. This checks that source files exist, share unique model IDs, contain the expected signal/stop/recovery code paths and have balanced braces. It does **not** compile MQL5/C#, validate runtime recovery, or prove historical fill parity.

## Scope / limitations

The order-recovery and chart architectures are **ported by copying the provided samples**, with intentional strategy-specific modifications. Their existing tests are not portable to this environment because MetaTrader and NinjaTrader installations are absent. These derivatives are not certified as production-identical to the sample. Some displayed template metrics and instrument roll assumptions require user-terminal parity checks. The scripts are provided for investigation and native iteration, not approved automated trading.
