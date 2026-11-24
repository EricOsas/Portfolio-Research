# GotobiFix — strategy model

What the EA trades, when, and why. Operator usage, inputs and build steps live in [README.md](README.md).

---

## 1. The trade

A **gotobi** day is a Japanese settlement date: the 5th, 10th, 15th, 20th, 25th and month-end. JPY flows
concentrate into the **09:55 Tokyo fix**, and the spot move around that fix tends to revert afterwards.

GotobiFix takes two fixed-lot legs on a JPY cross, one per phase:

| | Entry window (Tokyo) | Exit (Tokyo) | Direction | Thesis |
|---|---|---|---|---|
| Leg 1 | 03:00 – 09:55 | 09:55 | **LONG** | buy the pre-fix drift into the fix |
| Leg 2 | 09:55 – 10:30 | 10:30 | **SHORT** | sell the post-fix overshoot back to the fix |

**The clock is the exit.** There is no stop loss and no take profit by rule
(`DisasterStopPips = 0` is the default and the rule-faithful setting). Both legs are entered at market and
closed at a fixed Tokyo time.

---

## 2. Calendar

- Nominal gotobi dates: **5, 10, 15, 20, 25, and the last calendar day of the month**.
- Each nominal date is **shifted back to the previous Japanese bank day**. A date that falls on a weekend or a
  Japanese holiday trades on the last open day before it, never after.
- Bank days exclude weekends, the built-in Japanese holiday table, and any date listed in `ExtraHolidays`
  (`YYYYMMDD` list) for one-off exchange closures.
- Supported range: **2007–2099**. Outside it the EA reports `GF_CALENDAR_UNSUPPORTED` and takes no entries
  (existing positions are still managed).
- Tokyo is **UTC+9 all year** — Japan has no DST — so all windows are fixed offsets from UTC and never shift.

Two gotobi days can collapse onto the same trading day (e.g. the 25th and month-end over a long weekend).
The EA does not double up: each leg is allowed once per gotobi date.

---

## 3. Position discipline

**One position at a time, always.** This is structural, not an input:

- An entry is only attempted when nothing of this EA is owned on the symbol.
- Leg 2 waits for leg 1 to close (`waiting for long to close before short`) so the book is never long *and*
  short at once.
- Each leg is attempted at most once per gotobi date. A leg that cannot be resolved is blocked for the rest
  of that day rather than retried into a possible duplicate.

Exposure therefore equals exactly one leg of `Lots`. There is no percent-of-account mode and no exposure cap
input: `Lots` is the only risk sizing, and the per-order margin check (`OrderCalcMargin` against free margin)
is the only account-level bound.

---

## 4. Leg state machine

Per symbol × magic, persisted in terminal global variables so a restart does not replay a day:

| State | Meaning |
|---|---|
| `0` idle | eligible if the clock and window say so |
| `1` in flight | order sent, fill not yet proven by position or history |
| `2` filled | position open, tracked for exit |
| `9` blocked | no more attempts for this gotobi date |

Rules that drive it:

- **Intent before submission.** State `1` is written *before* `OrderSend`, so a terminal death mid-send cannot
  produce a second order after restart.
- **Resolution window.** State `1` is resolved by finding the position, or by finding an entry deal in history.
  If neither appears **90 s** after the request, the leg is set to `9` and logged as `GF_LEG_UNRESOLVED` — a
  deliberate choice to miss a trade rather than risk a duplicate.
- **Definitive rejections** (bad volume, market closed, etc.) retry twice, then block the day.
- Transient results (timeout, unknown) stay in `1`; they are never treated as "did not fill".
- The state rolls over on a new gotobi date.

---

## 5. Exit reasons

Written to the journal as `exit_reason`:

| Reason | Trigger |
|---|---|
| `fix_0955` | long leg reached the 09:55 Tokyo fix |
| `flat_1030` | short leg reached 10:30 Tokyo |
| `orphan` | position was opened on a date that is not a gotobi day (e.g. inherited from elsewhere) |
| `risk_cap` | floating loss on the owned position reached `MaxFloatingLossMoney`; both legs blocked for the day |
| `clock_unverified` | broker clock could not be resolved, so the exit deadline is unknown — flat is the fail-safe |
| `protect_fail` | a requested `DisasterStopPips` could not be placed after 3 attempts — flat is the fail-safe |

`orphan`, `clock_unverified` and `protect_fail` are defensive paths. On a healthy broker connection with the
rule-faithful settings (`DisasterStopPips = 0`) they should never fire.

---

## 6. Clock model

Server time is not UTC and brokers change their offset. The clock core is a pure function
`server = UTC + base + DST(rule, UTC)` with a dated schedule, so one EA run can span a broker that moved its
offset mid-sample. US, EU and fixed-offset rules are supported for 2007 onward.

- Conversions are resolved, never halted: a fall-back hour is resolved against the previous known instant, a
  spring-forward gap with the pre-transition offset.
- **Entry** requires a resolved clock (`ClkEntryOK`). Unresolved means no new risk.
- **Exits** do not wait for a clean clock. If the deadline cannot be computed, the position is flattened rather
  than left unmanaged — with no stop by rule, the clock *is* the protection.
- In the Strategy Tester a clock that can never resolve ends the run with one `GF_STOPPED` message instead of
  silently doing nothing.

---

## 7. Guards (all optional, all default off)

These exist for prop/cent constraints, not for the rule. Turning any of them on is a **deviation from the
PDF model** and must be recorded as such:

- `DisasterStopPips` — a catastrophic broker-side stop. If the paper is valid it should stay `0`.
- `MaxFloatingLossMoney` — flatten and block the day at a money loss.
- `MaxEntrySpreadPips` — skip an entry while the spread is wide.
- `MaxLateEntrySec` — skip a leg entered too long after its window opened.

Rejections are always "no trade", never "wider stop" or "bigger size".

---

## 8. What the EA deliberately does not do

- No stop loss, no take profit, no trailing, no break-even, no partial closes.
- No pyramiding, no averaging, no re-entry after an exit on the same day.
- No percent-risk sizing, no recovery lot, no martingale.
- No entries outside the two Tokyo windows, and no entries while the clock is unverified.
- No second instance: a lease file in `Common\Files` refuses a duplicate executor for the same
  account/symbol/magic (the tester bypasses it).
