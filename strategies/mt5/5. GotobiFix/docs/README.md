# GotobiFix — operator guide

MetaTrader 5 expert advisor: two fixed-lot legs on a JPY cross around the **09:55 Tokyo fix** on Japanese
gotobi settlement days. No stop, no target — the clock is the exit.

Strategy rules and the leg state machine: [MODEL.md](MODEL.md).

---

## Layout

Four files, one folder — copy them together, they are not independent:

| File | Role |
|---|---|
| `GotobiFix.mq5` | inputs, event handlers, `OnTester` summary |
| `StrategyEngine.mqh` | pure rule core: clock, Japanese calendar, Tokyo schedule |
| `ExecutionRuntime.mqh` | orders, exits, recovery, journal, guards |
| `ChartVisuals.mqh` | panel |
| `docs/` | this guide, [MODEL.md](MODEL.md), `tests/` |

---

## Requirements

- MetaTrader 5, **hedging** account (netting accounts are refused at init — the EA keeps a long and a short as
  separate tickets by design).
- `USDJPY`, `EURJPY` or `GBPJPY`. **One chart per pair.** Other symbols are refused unless
  `AllowOtherSymbols` is set.
- Algo trading enabled; the terminal must be connected (entries need a fresh quote, never a cached one).
- Broker clock resolvable. The EA derives the server→UTC offset from history and can persist it; if it cannot
  be resolved, entries pause and open positions are flattened rather than left unmanaged.

---

## Inputs

| Group | Input | Default | Meaning |
|---|---|---|---|
| 1 Trading | `EnableTrading` | `true` | `false` = manage and flatten only, no new entries |
| 2 Legs & Size | `Legs` | `Both legs` | `Both legs` / `Long only` / `Short only` |
| 2 Legs & Size | `Lots` | `0.10` | Fixed lots per leg — the only risk sizing |
| 3 Broker Clock | `ExtraHolidays` | `""` | Extra Japanese bank holidays, `YYYYMMDD` comma list |
| 4 Protection | `DisasterStopPips` | `0.0` | Catastrophic broker stop in pips; `0` = none, as per rule |
| 4 Protection | `MaxFloatingLossMoney` | `0.0` | Flatten and block the day at this floating loss; `0` = off |
| 4 Protection | `MaxEntrySpreadPips` | `0.0` | Skip entry above this spread; `0` = off |
| 4 Protection | `MaxLateEntrySec` | `0` | Skip a leg entered later than this after its window opens; `0` = off |
| 5 Execution | `Magic` | `26111701` | Must be unique per chart/pair |
| 5 Execution | `DeviationPts` | `30` | Maximum market-order deviation, points |
| 5 Execution | `JournalFile` | `gotobifix_trades` | Journal name under `Common\Files` |
| 5 Execution | `AllowOtherSymbols` | `false` | Permit symbols other than the three JPY crosses |
| 6 Display | `ShowPanel` | `true` | Information panel |

Sizing is fixed lots only. There is no percent-of-account mode and no exposure cap input: entries are only
attempted while the EA owns nothing, so exposure is exactly one leg.

The four group-4 guards exist for prop-firm or cent-account constraints. Every one of them is a deviation from
the model — leave them at `0`/`false` for rule-faithful results.

---

## Build

```
MetaEditor64.exe /compile:"...\MQL5\Experts\5. GotobiFix\GotobiFix.mq5"
                 /inc:"...\MQL5"
                 /log:"...\5. GotobiFix\docs\compile.log"
```

- `/inc` is required: without it `<Trade/Trade.mqh>` may resolve from the install directory instead of the
  terminal's data folder.
- The log is **UTF-16**; read it with `Get-Content -Encoding Unicode` or `read_text(encoding='utf-16')`.
  Plain `grep` finds nothing.
- The process exit code is unreliable — trust the `Result:` line.

Good build: `Result: 0 errors, 0 warnings`.

---

## Tests

```
python "…\5. GotobiFix\docs\tests\test_exposure_bound.py"
```

Runs the real flat-entry guard extracted from `ExecutionRuntime.mqh`, transpiled to C# and executed, plus two
structural assertions. Expected: `6/6 exposure bound checks passed`, exit 0.

What it proves: an entry is refused while any position is owned (both long and short paths), so exposure stays
at one leg of `Lots`, and no exposure-cap input or state has crept back in.

What it does **not** prove: no market, account, order or terminal call is made. This is a logic test, not a
backtest. `--root <dir>` points the same checks at another copy of the sources.

---

## Running

1. Drag `GotobiFix.ex5` onto a JPY-cross chart, one chart per pair, with `Magic` unique per chart.
2. Confirm the panel reads `clock OK`, the correct account currency and `hedging`.
3. Leave it alone. Entries appear inside the two Tokyo windows on gotobi days only; silence on other days is
   correct behaviour, not a fault.

A second instance for the same account/symbol/magic is refused by a lease file in `Common\Files`
(`GF.<login>.<scope-hash>.<magic>.lock`). The tester bypasses the lease.

### Panel

`CLK` server time and clock profile · `UTC` · `TKY` Tokyo time and clock state · `CFG` hedging, legs, lots,
stop · `DAY` today's phase · `NXT` next gotobi date · `LEG` per-leg state · `POS` open position ·
`SZ` size · `NOTE` last decision or skip reason.

### Journal

`Common\Files\<JournalFile>.csv` (`.tester` suffix inside the Strategy Tester), appended one row per closed
position, header written once:

```
version, symbol, magic, clock_rule, clock_base_min, clock_source, tokyo_gotobi_date, leg, position_id,
open_server, open_utc, open_tokyo, close_server, close_utc, close_tokyo, volume, model_open, fill_open,
fill_close, spread_pts_at_send, late_entry_sec, exit_reason, commission, swap, gross_profit, net_profit,
account_ccy
```

Rows are written only when history shows the full entry *and* exit volume, so a lagging history keeps the record
pending instead of dropping it. `exit_reason` values are documented in [MODEL.md](MODEL.md).

### Log tags worth knowing

| Tag | Meaning |
|---|---|
| `GF_INIT_FAIL …` | refused to start; the message names the input or the account property |
| `GF_ENTRY_FILLED` / `GF_ENTRY_RESULT` | entry outcome with retcode, spread, late seconds |
| `GF_ENTRY_SKIP …` | decision not to trade, with the reason |
| `GF_LEG_BLOCKED` / `GF_LEG_UNRESOLVED` | leg finished for the day; no duplicate will be attempted |
| `GF_CLOSE_REQUEST` / `GF_CLOSE_RETRY` | exit order outcome |
| `GF_RISK_CAP` | floating-loss guard fired; both legs blocked for the day |
| `GF_CALENDAR_UNSUPPORTED` | year outside 2007–2099; entries disabled, positions still managed |
| `GF_RECOVERY_*` | restart reconciliation; `GF_RECOVERY_READY` when historical ownership is proven |
| `GF_STOPPED` | tester only: broker clock could not be resolved, run ended |
| `GF_RESEARCH_RESULT` | `OnTester` one-line summary: trades, profit, PF, equity DD %, clock |

---

## Limits

- Valid for **2007–2099**; the Japanese holiday table is built in, plus `ExtraHolidays`.
- A leg that cannot be proven filled within 90 s is abandoned for the day — the design prefers a missed trade
  to a duplicate position.
- With `DisasterStopPips = 0` the only protection is the clock. If the terminal is offline across an exit
  deadline, the position stays open until the terminal reconnects and the EA flattens it.
- Results depend on broker fill quality: both legs are market orders at a fixed time.
