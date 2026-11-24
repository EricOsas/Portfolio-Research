#!/usr/bin/env python3
"""Build normalized-live and prop-firm portfolio research from exported trades.

This is an analysis layer only. It does not change strategy execution or stops.
"""
from __future__ import annotations
import itertools, json, math, re
from pathlib import Path
from datetime import datetime, timezone

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
LIVE_ROOT = ROOT / "reports" / "normalized-live"
PROP_ROOT = ROOT / "reports" / "prop-firms"
N_SIMS = 5000
HORIZON = 252
BLOCK = 5
SEED = 20261101
THE5ERS_RISKS = [10.0, 25.0, 50.0, 100.0]
MONETA_SIZE = 10000.0
MONETA_RISKS = [12.5, 25.0, 50.0, 75.0, 100.0]
TRADEIFY_RISKS = [100.0, 250.0, 500.0, 750.0]

def strategy_family(name):
    """Gold X9 presets are one EA at five TradeFrequency settings.

    Two presets in one book would be the same trade stream counted twice, so a
    book may hold at most one member of the family.
    """
    return "Gold X9" if str(name).startswith("Gold X9") else str(name)


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", str(s).lower()).strip("-")

def as_bool(x):
    if isinstance(x, bool): return x
    return str(x).strip().lower() in {"true", "1", "yes"}

def finite(x, default=0.0):
    try:
        v = float(x)
        return v if np.isfinite(v) else default
    except Exception:
        return default

def load_platform_trades(platform):
    path = ROOT / "reports" / platform.lower() / "reports" / "normalized_event_ledger.csv"
    if not path.exists():
        raise FileNotFoundError(path)
    raw = pd.read_csv(path, low_memory=False)
    raw["timestamp"] = pd.to_datetime(raw["timestamp"], errors="coerce")
    if "entry_timestamp" in raw:
        raw["entry_timestamp"] = pd.to_datetime(raw["entry_timestamp"], errors="coerce")
    raw = raw.dropna(subset=["timestamp"]).copy()
    trades, quality = [], []

    if platform == "NT8":
        for _, r in raw[raw["is_closed_trade"].map(as_bool)].iterrows():
            qty = abs(finite(r.get("quantity"), 1.0))
            if qty <= 0: qty = 1.0
            trades.append({
                "platform": platform, "strategy": str(r["strategy"]),
                "instrument": str(r.get("instrument", "")), "side": str(r.get("side", "")),
                "entry_timestamp": r.get("entry_timestamp"), "exit_timestamp": r["timestamp"],
                "quantity": qty, "native_pnl": finite(r.get("net_pnl")) / qty,
                "gross_pnl": finite(r.get("gross_pnl")) / qty,
                "commission": finite(r.get("commission")) / qty,
                "swap": finite(r.get("swap")) / qty,
                "mae": abs(finite(r.get("mae"), np.nan)) / qty if pd.notna(r.get("mae")) else np.nan,
                "mfe": finite(r.get("mfe"), np.nan) / qty if pd.notna(r.get("mfe")) else np.nan,
                "source_file": str(r.get("source_file", "")),
                "pairing_warning": "",
            })
    else:
        for strategy, g in raw.groupby("strategy", sort=False):
            g = g.sort_values("timestamp")
            custom = g[g.get("event_type", pd.Series(index=g.index, dtype=str)).astype(str).eq("completed_trade")]
            if not custom.empty:
                for _, r in custom.iterrows():
                    entry = r.get("entry_timestamp")
                    trades.append({
                        "platform": platform, "strategy": str(strategy),
                        "instrument": str(r.get("instrument", "")), "side": str(r.get("side", "")),
                        "entry_timestamp": entry, "exit_timestamp": r["timestamp"],
                        "quantity": abs(finite(r.get("quantity"))),
                        "native_pnl": finite(r.get("net_pnl")),
                        "gross_pnl": finite(r.get("gross_pnl")),
                        "commission": finite(r.get("commission")),
                        "swap": finite(r.get("swap")),
                        "mae": np.nan, "mfe": np.nan,
                        "source_file": str(r.get("source_file", "")),
                        "pairing_warning": "",
                    })
                continue

            # Standard MT5 Deals exports do not include a position ID. Pair each
            # entry with the next compatible exit, FIFO. Any concurrent open
            # positions or unmatched legs are surfaced as data-quality warnings.
            opened = []
            max_open = 0
            unmatched_exits = 0
            partial_volume_mismatches = 0
            for _, r in g.iterrows():
                direction = str(r.get("direction", "")).strip().lower().replace("_", " ")
                typ = str(r.get("side", "")).strip().lower()
                instrument = str(r.get("instrument", ""))
                volume = abs(finite(r.get("quantity")))
                cash = finite(r.get("net_pnl"))
                gross = finite(r.get("gross_pnl"))
                comm = finite(r.get("commission"))
                swap = finite(r.get("swap"))
                if direction in {"in", "entry"}:
                    opened.append({
                        "platform": platform, "strategy": str(strategy), "instrument": instrument,
                        "side": typ, "entry_timestamp": r["timestamp"], "exit_timestamp": pd.NaT,
                        "quantity": volume, "native_pnl": cash, "gross_pnl": gross,
                        "commission": comm, "swap": swap, "mae": np.nan, "mfe": np.nan,
                        "source_file": str(r.get("source_file", "")),
                    })
                    max_open = max(max_open, len(opened))
                elif direction in {"out", "out by", "outby", "close", "exit"}:
                    wanted = "buy" if typ == "sell" else "sell" if typ == "buy" else ""
                    candidates = [i for i, p in enumerate(opened)
                                  if p["instrument"] == instrument and (not wanted or p["side"] == wanted)]
                    # Prefer exact volume matches; this helps where two positions overlap.
                    match_idx = next((i for i in candidates
                                      if volume and abs(opened[i]["quantity"] - volume) <= 1e-6), None)
                    if match_idx is None and candidates:
                        match_idx = candidates[0]
                    if match_idx is None and opened:
                        match_idx = 0
                    if match_idx is None:
                        unmatched_exits += 1
                        continue
                    p = opened.pop(match_idx)
                    if volume and p["quantity"] and abs(volume - p["quantity"]) > 1e-6:
                        partial_volume_mismatches += 1
                    p["native_pnl"] += cash
                    p["gross_pnl"] += gross
                    p["commission"] += comm
                    p["swap"] += swap
                    p["exit_timestamp"] = r["timestamp"]
                    p["pairing_warning"] = ""
                    trades.append(p)
                else:
                    # Ignore balance/deposit rows and unsupported deal directions.
                    continue
            unclosed = len(opened)
            quality.append({
                "platform": platform, "strategy": str(strategy),
                "pairing_method": "FIFO by symbol and opposite deal side; no position ID in source export",
                "max_simultaneous_open_positions_seen": max_open,
                "unmatched_exit_legs": unmatched_exits,
                "unclosed_entry_legs": unclosed,
                "entry_exit_volume_mismatches": partial_volume_mismatches,
            })
            # Unmatched entries are excluded from realized PnL and retained in the quality summary.

    out = pd.DataFrame(trades)
    if out.empty:
        raise ValueError(f"No completed trades parsed for {platform}")
    out["entry_timestamp"] = pd.to_datetime(out["entry_timestamp"], errors="coerce")
    out["exit_timestamp"] = pd.to_datetime(out["exit_timestamp"], errors="coerce")
    out = out.dropna(subset=["exit_timestamp"]).copy()
    if platform == "MT5":
        # Strip position-size compounding. Several MT5 exports size from account
        # balance (Gold X9 grows from ~0.09 to 50+ lots), so raw dollar PnL is not
        # comparable across systems or years. Express each trade per 1.00 lot.
        qty = out["quantity"].where(out["quantity"].abs() > 1e-12)
        for col in ("native_pnl", "gross_pnl", "commission", "swap"):
            out[col] = (out[col] / qty).fillna(0.0)
    out["duration_seconds"] = (out["exit_timestamp"] - out["entry_timestamp"]).dt.total_seconds()
    out["entry_date"] = out["entry_timestamp"].dt.normalize()
    out["exit_date"] = out["exit_timestamp"].dt.normalize()
    out["risk_unit"] = np.nan
    out["r_multiple"] = np.nan
    out["live_pnl"] = np.nan
    out["risk_unit_basis"] = ""
    for strategy, idx in out.groupby("strategy").groups.items():
        loss = out.loc[idx, "native_pnl"]
        losses = loss[loss < 0]
        unit = abs(float(losses.mean())) if len(losses) else float(loss.abs().median())
        if not np.isfinite(unit) or unit <= 0:
            unit = float(loss.abs().mean()) if len(loss) else 1.0
        if not np.isfinite(unit) or unit <= 0: unit = 1.0
        out.loc[idx, "risk_unit"] = unit
        out.loc[idx, "r_multiple"] = out.loc[idx, "native_pnl"] / unit
        if platform == "NT8":
            out.loc[idx, "live_pnl"] = out.loc[idx, "native_pnl"]  # one contract equivalent
            out.loc[idx, "risk_unit_basis"] = "mean absolute losing trade PnL per contract"
        else:
            out.loc[idx, "live_pnl"] = out.loc[idx, "r_multiple"] * 100.0
            out.loc[idx, "risk_unit_basis"] = "per-lot mean absolute losing trade PnL; $100 = 1R"
    return out.sort_values("exit_timestamp").reset_index(drop=True), quality

def daily_series(trades, value_col, dates=None):
    if trades.empty: return pd.Series(dtype=float)
    s = trades.groupby("exit_date")[value_col].sum()
    idx = dates if dates is not None else pd.bdate_range(s.index.min(), s.index.max())
    return s.reindex(idx, fill_value=0.0).astype(float)

def series_metrics(s, trades=None):
    s = s.astype(float).fillna(0.0)
    eq = s.cumsum()
    dd = eq.cummax() - eq
    pos, neg = float(s[s > 0].sum()), abs(float(s[s < 0].sum()))
    pf = pos / neg if neg > 0 else (float("inf") if pos > 0 else 0.0)
    sd = float(s.std(ddof=1)) if len(s) > 1 else 0.0
    sharpe = float(s.mean() / sd * math.sqrt(252)) if sd > 0 else 0.0
    monthly, yearly = s.resample("ME").sum(), s.resample("YE").sum()
    active_months, active_years = monthly[monthly != 0], yearly[yearly != 0]
    positive_total = float(s[s > 0].sum())
    best = float(s.max()) if len(s) else 0.0
    return {
        "net_pnl": float(s.sum()), "annualized_pnl": float(s.mean() * 252),
        "daily_pf": float(pf), "daily_sharpe": sharpe,
        "max_drawdown": float(dd.max()) if len(dd) else 0.0,
        "net_to_maxdd": float(s.sum() / dd.max()) if len(dd) and dd.max() > 0 else 0.0,
        "positive_month_share": float((active_months > 0).mean()) if len(active_months) else 0.0,
        "positive_year_share": float((active_years > 0).mean()) if len(active_years) else 0.0,
        "positive_day_share": float((s[s != 0] > 0).mean()) if (s != 0).any() else 0.0,
        "best_day": best, "worst_day": float(s.min()) if len(s) else 0.0,
        "best_day_share": best / positive_total if positive_total > 0 else 0.0,
        "daily_std": sd, "equity": eq, "drawdown": dd,
    }

def make_matrices(trades):
    strategies = sorted(trades["strategy"].unique().tolist())
    start, end = trades["exit_date"].min(), trades["exit_date"].max()
    dates = pd.bdate_range(start, end)
    rmat, gross_rmat, livemat, activemat = {}, {}, {}, {}
    for s in strategies:
        t = trades[trades["strategy"] == s]
        rmat[s] = daily_series(t, "r_multiple", dates)
        gross_rmat[s] = daily_series(t, "gross_r_multiple", dates)
        livemat[s] = daily_series(t, "live_pnl", dates)
        a = t.groupby("entry_date").size()
        activemat[s] = a.reindex(dates, fill_value=0).gt(0)
    return (dates, pd.DataFrame(rmat, index=dates), pd.DataFrame(gross_rmat, index=dates),
            pd.DataFrame(livemat, index=dates), pd.DataFrame(activemat, index=dates))

def plot_equity(s, title, path, subtitle=""):
    path.parent.mkdir(parents=True, exist_ok=True)
    s = s.astype(float).fillna(0.0)
    eq = s.cumsum()
    dd = eq.cummax() - eq
    fig, (ax, axd) = plt.subplots(2, 1, figsize=(12.5, 6.8), sharex=True, gridspec_kw={"height_ratios":[3,1]})
    fig.patch.set_facecolor("#f7f8fa")
    for a in (ax, axd):
        a.set_facecolor("white")
        a.grid(True, alpha=.22, linestyle="--")
        a.spines[["top","right"]].set_visible(False)
    ax.plot(eq.index, eq.values, linewidth=1.8, color="#1769aa")
    ax.axhline(0, color="#555", linewidth=.8)
    ax.set_ylabel("Cumulative equity / PnL")
    ax.set_title(title, loc="left", fontsize=14, fontweight="bold")
    m = series_metrics(s)
    label = f"Net {m['net_pnl']:,.1f} | Max DD {m['max_drawdown']:,.1f} | PF {m['daily_pf']:.2f} | Sharpe {m['daily_sharpe']:.2f}"
    ax.text(.01,.97, (subtitle + "\n" if subtitle else "") + label, transform=ax.transAxes, va="top", fontsize=8)
    axd.fill_between(dd.index, -dd.values, 0, color="#c0392b", alpha=.25)
    axd.plot(dd.index, -dd.values, color="#c0392b", linewidth=1)
    axd.set_ylabel("Drawdown")
    loc = mdates.AutoDateLocator(minticks=4, maxticks=9)
    axd.xaxis.set_major_locator(loc)
    axd.xaxis.set_major_formatter(mdates.ConciseDateFormatter(loc))
    fig.tight_layout()
    fig.savefig(path, dpi=160, bbox_inches="tight")
    plt.close(fig)

def plot_dashboard(curves, title, path):
    items = list(curves.items())
    if not items: return
    cols = 3
    rows = math.ceil(len(items)/cols)
    fig, axes = plt.subplots(rows, cols, figsize=(15, 3.6*rows), squeeze=False)
    fig.suptitle(title, fontsize=16, fontweight="bold", x=.04, ha="left")
    for ax in axes.flat: ax.set_visible(False)
    for ax, (name, s) in zip(axes.flat, items):
        ax.set_visible(True)
        eq = s.cumsum()
        ax.plot(eq.index, eq.values, linewidth=1.25)
        ax.axhline(0, color="#666", linewidth=.6)
        ax.grid(True, alpha=.2, linestyle="--")
        ax.set_title(name, fontsize=9, loc="left")
        ax.tick_params(labelsize=7)
    fig.tight_layout(rect=[0,0,1,.96])
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)

def book_metrics(rmat, active, combo, idx):
    k = len(combo)
    s = rmat.loc[idx, list(combo)].sum(axis=1) / k
    a = active.loc[idx, list(combo)].any(axis=1)
    m = series_metrics(s)
    m["active_days"] = int(a.sum())
    m["strategies"] = " + ".join(combo)
    m["size"] = k
    return m, s, a

def rank_pct(df, col, ascending=True):
    x = df[col].replace([np.inf,-np.inf], np.nan)
    return x.rank(pct=True, ascending=ascending).fillna(0.0)

def build_books(rmat, active):
    names = list(rmat.columns)
    idx = rmat.index
    cut = max(1, min(len(idx)-1, int(len(idx)*0.60)))
    train_idx, val_idx = idx[:cut], idx[cut:]
    rows = []
    for k in range(1, min(4, len(names))+1):
        for combo in itertools.combinations(names, k):
            if len({strategy_family(x) for x in combo}) < len(combo):
                continue
            tr, _, _ = book_metrics(rmat, active, combo, train_idx)
            va, _, _ = book_metrics(rmat, active, combo, val_idx)
            rows.append({
                "book": " + ".join(combo), "strategies": " | ".join(combo), "size": k,
                "train_net_R": tr["net_pnl"], "train_net_to_maxdd_R": tr["net_to_maxdd"], "train_sharpe": tr["daily_sharpe"],
                "train_pf": tr["daily_pf"], "train_maxdd_R": tr["max_drawdown"],
                "train_positive_month_share": tr["positive_month_share"],
                "train_worst_day_R": tr["worst_day"], "train_best_day_share": tr["best_day_share"],
                "train_active_days": tr["active_days"],
                "validation_net_R": va["net_pnl"], "validation_sharpe": va["daily_sharpe"],
                "validation_pf": va["daily_pf"], "validation_maxdd_R": va["max_drawdown"],
                "validation_positive_month_share": va["positive_month_share"],
                "validation_worst_day_R": va["worst_day"], "validation_best_day_share": va["best_day_share"],
                "validation_active_days": va["active_days"],
            })
    df = pd.DataFrame(rows)
    # Ranking is based only on the earlier training segment. Validation is held aside.
    df["live_score"] = (.35*rank_pct(df,"train_sharpe") + .25*rank_pct(df,"train_pf") +
                        .20*rank_pct(df,"train_positive_month_share") + .20*rank_pct(df,"train_maxdd_R",ascending=False))
    df["challenge_score"] = (.35*rank_pct(df,"train_net_to_maxdd_R") + .30*rank_pct(df,"train_sharpe") +
                             .20*rank_pct(df,"train_net_R") + .15*rank_pct(df,"train_active_days"))
    df["funded_score"] = (.30*rank_pct(df,"train_sharpe") + .25*rank_pct(df,"train_positive_month_share") +
                          .20*rank_pct(df,"train_worst_day_R") + .15*rank_pct(df,"train_best_day_share",ascending=False) +
                          .10*rank_pct(df,"train_pf"))
    df["recovery_score"] = (.35*rank_pct(df,"train_sharpe") + .25*rank_pct(df,"train_maxdd_R",ascending=False) +
                            .25*rank_pct(df,"train_worst_day_R") + .15*rank_pct(df,"train_net_R"))
    selected = {}
    for cat in ["live","challenge","funded","recovery"]:
        ranked = df.sort_values(f"{cat}_score", ascending=False)
        chosen = []
        for _, row in ranked.iterrows():
            combo = tuple(row["strategies"].split(" | "))
            if row["train_net_R"] <= 0 or row["train_active_days"] < 30:
                continue
            if combo not in chosen:
                chosen.append(combo)
            if len(chosen) == 3: break
        selected[cat] = chosen
    return df, selected, train_idx, val_idx

def sample_block_paths(values, active, n_sims=N_SIMS, horizon=HORIZON, block=BLOCK,
                       seed=SEED, date_index=None):
    values = np.asarray(values, dtype=float)
    active = np.asarray(active, dtype=bool)
    if len(values) == 0:
        raise ValueError("No daily observations for bootstrap.")
    rng = np.random.default_rng(seed)
    block = max(1, min(block, len(values)))
    nblocks = int(math.ceil(horizon / block))
    offsets = np.arange(block)
    # Sample complete Monday-Friday blocks where dates are available. This
    # preserves weekly activity and weekday structure rather than starting
    # each five-day block on an arbitrary weekday.
    if date_index is not None and block == 5 and len(date_index) == len(values):
        dates = pd.DatetimeIndex(date_index)
        candidates = np.flatnonzero((dates.weekday == 0) &
                                    (np.arange(len(values)) + block <= len(values)))
    else:
        candidates = np.arange(max(1, len(values) - block + 1))
    if len(candidates) == 0:
        candidates = np.arange(len(values))
    starts = rng.choice(candidates, size=(n_sims, nblocks), replace=True)
    indices = (starts[:,:,None] + offsets[None,None,:]) % len(values)
    indices = indices.reshape(n_sims, -1)[:,:horizon]
    return values[indices], active[indices]

def live_bootstrap_summary(paths):
    eq = np.cumsum(paths, axis=1)
    peak = np.maximum.accumulate(np.concatenate([np.zeros((len(eq),1)), eq], axis=1), axis=1)[:,1:]
    dd = peak - eq
    maxdd = dd.max(axis=1)
    terminal = eq[:,-1]
    return {
        "simulations": int(len(paths)), "horizon_trading_days": int(paths.shape[1]), "block_length_days": BLOCK,
        "terminal_R_mean": float(terminal.mean()), "terminal_R_p05": float(np.quantile(terminal,.05)),
        "terminal_R_median": float(np.median(terminal)), "terminal_R_p95": float(np.quantile(terminal,.95)),
        "maxdd_R_p50": float(np.median(maxdd)), "maxdd_R_p95": float(np.quantile(maxdd,.95)),
        "ruin_10R": float((maxdd >= 10).mean()), "ruin_20R": float((maxdd >= 20).mean()),
        "ruin_50R": float((maxdd >= 50).mean()),
    }

def monthly_path_summary(paths, risk):
    """Summarize 21-session month blocks from the bootstrapped strategy PnL path.

    These are strategy-stream estimates at the configured book risk, before
    account failure, payout eligibility, withdrawal resets, or rule-based stops.
    """
    daily = np.asarray(paths, dtype=float) * float(risk)
    n, h = daily.shape
    months = h // 21
    if months < 1:
        return {}
    blocks = daily[:, :months * 21].reshape(n, months, 21)
    monthly_pnl = blocks.sum(axis=2).reshape(-1)

    month_equity = np.cumsum(blocks, axis=2)
    month_high_water = np.maximum.accumulate(np.maximum(month_equity, 0.0), axis=2)
    monthly_drawdown = np.maximum(month_high_water - month_equity, 0.0).max(axis=2).reshape(-1)

    equity = np.cumsum(daily, axis=1)
    high_water = np.maximum.accumulate(np.maximum(equity, 0.0), axis=1)
    max_drawdown_252d = np.maximum(high_water - equity, 0.0).max(axis=1)

    return {
        "mean_monthly_strategy_pnl_usd": float(np.mean(monthly_pnl)),
        "median_monthly_strategy_pnl_usd": float(np.median(monthly_pnl)),
        "p10_monthly_strategy_pnl_usd": float(np.percentile(monthly_pnl, 10)),
        "p90_monthly_strategy_pnl_usd": float(np.percentile(monthly_pnl, 90)),
        "median_monthly_peak_to_trough_dd_usd": float(np.median(monthly_drawdown)),
        "p90_monthly_peak_to_trough_dd_usd": float(np.percentile(monthly_drawdown, 90)),
        "p95_max_drawdown_252d_usd": float(np.percentile(max_drawdown_252d, 95)),
        "monthly_metric_basis": (
            "21-trading-day blocks; strategy PnL before account failures, "
            "DLL clipping, payout rules or withdrawal resets. Monthly DD is "
            "within-block peak-to-trough; 252d DD is full-path peak-to-trough."
        ),
    }


def simulate_the5ers(paths, active, risk):
    """The5ers $20k Bootcamp: 3 evaluation steps, then a funded account.

    Verified structure (The5ers Bootcamp page / FAQ, checked 2026-11-22):
    Step 1 $5,000, Step 2 $10,000, Step 3 $15,000; each needs 6% with a 5%
    static max loss and has no daily loss limit. The funded $20,000 account has
    a 4% static max loss ($800 floor), a 3% daily pause (trading stops for the
    rest of the day, the triggering loss stands) and payouts every 14 calendar
    days (approximated as 10 trading days) at a 50% split, with a USD 300 gross
    minimum per payout (USD 150 to the trader); smaller gains carry forward. No consistency rule,
    no time limit. Scaling after each 5% funded gain is not modeled.
    """
    n, h = paths.shape
    step = np.ones(n, dtype=np.int8)  # 1..3 = evaluation steps, 4 = funded, 5 = failed
    bal = np.full(n, 5000.0)
    step_balances = (5000.0, 10000.0, 15000.0)
    step_target = tuple(b * 1.06 for b in step_balances)
    step_floor = tuple(b * 0.95 for b in step_balances)
    funded_balance = 20000.0
    funded_floor = funded_balance * 0.96

    pass1_day = np.full(n, -1, dtype=int)
    pass2_day = np.full(n, -1, dtype=int)
    pass3_day = np.full(n, -1, dtype=int)
    fail_step = np.zeros((3, n), dtype=bool)
    fail_max = np.zeros(n, dtype=bool)
    funded_breach = np.zeros(n, dtype=bool)
    funded_breach_day = np.full(n, -1, dtype=int)
    funded_age = np.zeros(n, dtype=int)
    pause_days = np.zeros(n, dtype=int)
    payout_day = np.full(n, -1, dtype=int)
    payout = np.zeros(n)
    payout_count = np.zeros(n, dtype=int)
    total_cash = np.zeros(n)

    for d in range(h):
        start_step = step.copy()
        start_bal = bal.copy()
        daily = paths[:, d] * risk

        for idx, st in enumerate((1, 2, 3)):
            m = (start_step == st)
            if not m.any():
                continue
            bal[m] += daily[m]
            bad = m & (bal <= step_floor[idx])
            fail_step[idx] |= bad
            fail_max |= bad
            step[bad] = 5
            passed = m & (step == st) & (bal >= step_target[idx])
            if passed.any():
                step[passed] = st + 1
                next_balance = (10000.0, 15000.0, funded_balance)[idx]
                bal[passed] = next_balance
                if st == 1:
                    pass1_day[passed] = d
                elif st == 2:
                    pass2_day[passed] = d
                else:
                    pass3_day[passed] = d
                    funded_age[passed] = 0

        funded = (start_step == 4) & (step == 4)
        if funded.any():
            pause_limit = 0.03 * start_bal[funded]
            raw = daily[funded]
            paused = raw < -pause_limit
            pause_days[funded] += paused.astype(int)
            bal[funded] += np.maximum(raw, -pause_limit)
            funded_age[funded] += 1
            bad = funded & (bal <= funded_floor)
            funded_breach |= bad
            funded_breach_day[bad] = d
            fail_max |= bad
            step[bad] = 5

            # The5ers pays only when the profit reaches USD 300 gross (USD 150 net at
            # the 50% split); a smaller gain carries forward to the next cycle.
            due = funded & (step == 4) & (funded_age > 0) & (funded_age % 10 == 0) & (bal - funded_balance >= 300.0 - 1e-9)
            if due.any():
                amount = np.zeros(n)
                amount[due] = (bal[due] - funded_balance) * 0.50
                total_cash[due] += amount[due]
                payout_count[due] += 1
                no_payout_yet = due & (payout_day < 0)
                payout_day[no_payout_yet] = d
                payout[no_payout_yet] = amount[no_payout_yet]
                bal[due] = funded_balance

    reached_funded = pass3_day >= 0
    first_payout = payout_day >= 0
    funded_days_to_first = np.full(n, np.nan)
    funded_days_to_first[first_payout] = (payout_day[first_payout] - pass3_day[first_payout] + 1)
    evaluable_90 = reached_funded & ((pass3_day + 90) < h)
    funded_ok_90 = evaluable_90 & (~funded_breach | (funded_breach_day > pass3_day + 90))

    return {
        "pass_phase1_rate": float((pass1_day >= 0).mean()),
        "pass_step1_rate": float((pass1_day >= 0).mean()),
        "pass_step2_conditional_rate": float((pass2_day >= 0).sum() / max(1, (pass1_day >= 0).sum())),
        "pass_step3_conditional_rate": float((pass3_day >= 0).sum() / max(1, (pass2_day >= 0).sum())),
        "pass_verification_conditional_rate": float((pass3_day >= 0).sum() / max(1, (pass1_day >= 0).sum())),
        "pass_both_phases_rate": float(reached_funded.mean()),
        "funded_first_reward_rate_conditional": float(first_payout[reached_funded].mean()) if reached_funded.any() else 0.0,
        "funded_first_payout_rate_conditional": float(first_payout[reached_funded].mean()) if reached_funded.any() else 0.0,
        "challenge_to_first_reward_rate": float(first_payout.mean()),
        "challenge_to_first_payout_rate": float(first_payout.mean()),
        "fail_daily_loss_rate": 0.0,
        "fail_max_loss_rate": float(fail_max.mean()),
        "challenge_daily_loss_breach_rate": 0.0,
        "challenge_max_loss_breach_rate": float((fail_step[0] | fail_step[1] | fail_step[2]).mean()),
        "step1_max_loss_breach_rate": float(fail_step[0].mean()),
        "step2_max_loss_breach_rate": float(fail_step[1].mean()),
        "step3_max_loss_breach_rate": float(fail_step[2].mean()),
        "verification_daily_loss_breach_rate": 0.0,
        "verification_max_loss_breach_rate": float((fail_step[1] | fail_step[2]).mean()),
        "funded_daily_loss_breach_rate_conditional": 0.0,
        "funded_max_loss_breach_rate_conditional": float(funded_breach[reached_funded].mean()) if reached_funded.any() else 0.0,
        "funded_hard_breach_rate_conditional": float(funded_breach[reached_funded].mean()) if reached_funded.any() else 0.0,
        "evaluation_hard_breach_rate": float((fail_step[0] | fail_step[1] | fail_step[2]).mean()),
        "funded_daily_pause_days_mean": float(pause_days[reached_funded].mean()) if reached_funded.any() else 0.0,
        "median_days_to_phase1": float(np.median(pass1_day[pass1_day >= 0]) + 1) if (pass1_day >= 0).any() else np.nan,
        "median_days_to_phase2": float(np.median(pass3_day[pass3_day >= 0]) + 1) if reached_funded.any() else np.nan,
        "median_days_to_funded_from_start": float(np.median(pass3_day[reached_funded]) + 1) if reached_funded.any() else np.nan,
        "median_days_to_first_reward_from_start": float(np.median(payout_day[first_payout]) + 1) if first_payout.any() else np.nan,
        "median_funded_days_to_first_payout": float(np.nanmedian(funded_days_to_first)) if first_payout.any() else np.nan,
        "expected_first_reward_usd": float(payout.mean()),
        "median_first_reward_usd_conditional": float(np.median(payout[first_payout])) if first_payout.any() else 0.0,
        "total_payout_cash_mean": float(total_cash.mean()),
        "payout_count_mean": float(payout_count.mean()),
        "survival_90d_conditional_approx": float(funded_ok_90.sum() / max(1, evaluable_90.sum())) if evaluable_90.any() else np.nan,
        "simulations": int(n), "horizon_trading_days": int(h),
        "note": (
            "Daily closed-PnL model. Bootcamp evaluation: three steps on $5k/$10k/$15k, 6% target and "
            "5% static max loss each, no daily limit. Funded: $20k, 4% static max loss ($800), 3% daily "
            "pause modeled as a closed-PnL clip, 50% split, payouts every 14 calendar days approximated "
            "as 10 trading days, USD 300 gross minimum per payout (USD 150 net). No consistency rule. "
            "5% funded scale-up ladder not modeled. "
            "Floating-loss breaches and intraday pause timing are not visible in exports."
        ),
    }


def simulate_moneta(paths, active, risk, size=MONETA_SIZE, daily_pct=0.04, max_pct=0.08,
                    phase1_target_pct=0.05, phase2_target_pct=0.10,
                    split=0.88, cycle_trading_days=10, min_profit_days=3,
                    min_profit_day_pct=0.005, cycle_min_profit_usd=0.0,
                    funded_paths=None, funded_risk=None):
    """Moneta Funded 2-Step Standard (USD 10,000 by default).

    Rules per the Moneta Funded support clarification of 2026-11-21 and the
    published programme rules: Phase 1 target 5%, Phase 2 target 10%; daily loss
    4% (5% with the wider drawdown option); maximum loss 8% static (10% with the
    wider option); three profitable days of at least 0.5% net in each phase and
    in each funded payout cycle; no consistency rule; 88% split; 14 calendar-day
    payout cycle approximated as 10 trading days. News is restricted from five
    minutes before to five minutes after high-impact releases in both evaluation
    and funded stages; that is not visible in daily export data and is not
    modeled here.
    """
    n, h = paths.shape
    size = float(size)
    phase = np.ones(n, dtype=np.int8)          # 1, 2 = evaluation, 3 = funded, 4 = failed
    bal = np.full(n, size)
    p1_target = size * (1.0 + phase1_target_pct)
    p2_target = size * (1.0 + phase2_target_pct)
    floor = size * (1.0 - max_pct)

    pass1_day = np.full(n, -1, dtype=int)
    pass2_day = np.full(n, -1, dtype=int)
    good_days = np.zeros(n, dtype=int)
    fail_daily = np.zeros((2, n), dtype=bool)
    fail_max = np.zeros((2, n), dtype=bool)
    funded_breach = np.zeros(n, dtype=bool)
    funded_breach_day = np.full(n, -1, dtype=int)
    funded_age = np.zeros(n, dtype=int)
    cycle_good_days = np.zeros(n, dtype=int)
    payout_day = np.full(n, -1, dtype=int)
    payout = np.zeros(n)
    payout_count = np.zeros(n, dtype=int)
    total_cash = np.zeros(n)
    blocked_cycles = np.zeros(n)

    for d in range(h):
        start_phase = phase.copy()
        start_bal = bal.copy()
        daily = paths[:, d] * risk
        if funded_paths is not None:
            fdaily = funded_paths[:, d] * (risk if funded_risk is None else funded_risk)
        else:
            fdaily = daily

        for idx, st in enumerate((1, 2)):
            m = (start_phase == st)
            if not m.any():
                continue
            idxs = np.where(m)[0]
            day_floor = -daily_pct * start_bal[idxs]
            blew = daily[idxs] <= day_floor
            fail_daily[idx][idxs] |= blew
            bal[idxs] += np.where(blew, 0.0, daily[idxs])
            good = (daily[idxs] >= min_profit_day_pct * start_bal[idxs]) & ~blew
            good_days[idxs] += good.astype(int)
            target = p1_target if st == 1 else p2_target
            reached = bal[idxs] >= target - 1e-9
            passed = reached & (good_days[idxs] >= min_profit_days)
            under = bal[idxs] <= floor
            fail_max[idx][idxs] |= under
            failed = blew | under
            phase[idxs] = np.where(passed, 2 if st == 1 else 3, np.where(failed, 4, st))
            if st == 1 and passed.any():
                ok = idxs[passed]
                pass1_day[ok] = d
                bal[ok] = size
                good_days[ok] = 0
            if st == 2 and passed.any():
                ok = idxs[passed]
                pass2_day[ok] = d
                bal[ok] = size
                good_days[ok] = 0
                funded_age[ok] = 0

        fd = np.where((start_phase == 3))[0]
        if len(fd):
            day_floor = -daily_pct * start_bal[fd]
            raw = fdaily[fd]
            blew = raw <= day_floor
            bal[fd] += np.where(blew, 0.0, raw)
            funded_age[fd] += 1
            good = (raw >= min_profit_day_pct * start_bal[fd]) & ~blew
            cycle_good_days[fd] += good.astype(int)
            bad_mask = (bal[fd] <= floor) | blew
            bad = fd[bad_mask]
            funded_breach[bad] = True
            funded_breach_day[bad] = d
            phase[bad] = 4

            due_all = fd[(funded_age[fd] > 0) & (funded_age[fd] % cycle_trading_days == 0)]
            due_all = due_all[phase[due_all] == 3]
            if len(due_all):
                profit = bal[due_all] - size
                eligible = (profit > cycle_min_profit_usd) & (cycle_good_days[due_all] >= min_profit_days)
                paid = due_all[eligible]
                if len(paid):
                    amount = (bal[paid] - size) * split
                    total_cash[paid] += amount
                    payout_count[paid] += 1
                    first = paid[payout_day[paid] < 0]
                    payout_day[first] = d
                    payout[first] = amount[np.isin(paid, first)]
                    bal[paid] = size
                    cycle_good_days[paid] = 0
                blocked_cycles[due_all[~eligible]] += 1

    reached_funded = pass2_day >= 0
    first_payout = payout_day >= 0
    eval_breach = fail_daily[0] | fail_daily[1] | fail_max[0] | fail_max[1]
    days_funded = np.where(reached_funded, pass2_day, -1)
    funded_flat = funded_breach
    funded_ok_90 = np.zeros(n, dtype=bool)
    evaluable = reached_funded & ((pass2_day + 90) < h)
    for i in np.where(evaluable)[0]:
        if not funded_flat[i] or funded_breach_day[i] > pass2_day[i] + 90:
            funded_ok_90[i] = True
    return {
        "pass_phase1_rate": float((pass1_day >= 0).mean()),
        "pass_step1_rate": float((pass1_day >= 0).mean()),
        "pass_phase2_conditional_rate": float((pass2_day >= 0).sum() / max(1, (pass1_day >= 0).sum())),
        "pass_both_phases_rate": float((pass2_day >= 0).mean()),
        "funded_first_payout_rate_conditional": float(first_payout[reached_funded].mean()) if reached_funded.any() else 0.0,
        "challenge_to_first_payout_rate": float(first_payout.mean()),
        "fail_daily_loss_rate": float(fail_daily[0].mean()),
        "fail_max_loss_rate": float(fail_max[0].mean()),
        "challenge_daily_loss_breach_rate": float((fail_daily[0] | fail_daily[1]).mean()),
        "challenge_max_loss_breach_rate": float((fail_max[0] | fail_max[1]).mean()),
        "phase1_daily_loss_breach_rate": float(fail_daily[0].mean()),
        "phase1_max_loss_breach_rate": float(fail_max[0].mean()),
        "phase2_daily_loss_breach_rate": float(fail_daily[1].mean()),
        "phase2_max_loss_breach_rate": float(fail_max[1].mean()),
        "evaluation_hard_breach_rate": float(eval_breach.mean()),
        "funded_hard_breach_rate_conditional": float(funded_breach[reached_funded].mean()) if reached_funded.any() else 0.0,
        "funded_daily_loss_breach_rate_conditional": float(funded_breach[reached_funded].mean()) if reached_funded.any() else 0.0,
        "funded_max_loss_breach_rate_conditional": float(funded_breach[reached_funded].mean()) if reached_funded.any() else 0.0,
        "median_days_to_phase1": float(np.median(pass1_day[pass1_day >= 0]) + 1) if (pass1_day >= 0).any() else np.nan,
        "median_days_to_funded_from_start": float(np.median(days_funded[pass2_day >= 0]) + 1) if (pass2_day >= 0).any() else np.nan,
        "median_days_to_first_payout_from_start": float(np.median(payout_day[first_payout]) + 1) if first_payout.any() else np.nan,
        "expected_first_payout_usd": float(payout.mean()),
        "median_first_payout_usd_conditional": float(np.median(payout[first_payout])) if first_payout.any() else 0.0,
        "total_payout_cash_mean": float(total_cash.mean()),
        "payout_count_mean": float(payout_count.mean()),
        "blocked_payout_cycles_mean": float(blocked_cycles[reached_funded].mean()) if reached_funded.any() else 0.0,
        "survival_90d_conditional_approx": float(funded_ok_90.sum() / max(1, evaluable.sum())) if evaluable.any() else np.nan,
        "simulations": int(n), "horizon_trading_days": int(h),
        "note": ("Daily closed-PnL model. Moneta 2-Step Standard: Phase 1 +5%, Phase 2 +10%, "
                 "4% daily loss and 8% static maximum loss (5%/10% with the wider drawdown option), "
                 "three profitable days of at least 0.5% net per phase and per payout cycle, no "
                 "consistency rule, 88% split, 14 calendar-day cycles approximated as 10 trading "
                 "days, balance reset to the account size after each payout. `funded_paths`/`funded_risk` "
                 "switch the book at funding. Floating-loss breaches, "
                 "the news window (5 minutes either side of high-impact releases) and intraday "
                 "trigger timing are not visible in daily export data."),
    }


def simulate_tradeify(paths, active, risk, microscalp_ok, weekly_activity_ok,
                      position_limit_compliant=True, consistency_paths=None):
    n, h = paths.shape
    consistency_paths = np.asarray(paths if consistency_paths is None else consistency_paths, dtype=float)
    if consistency_paths.shape != paths.shape:
        raise ValueError("Consistency paths must align with net-PnL paths.")
    phase = np.zeros(n, dtype=np.int8)  # 0=Evaluation, 1=Funded, 2=Failed
    eval_eq = np.zeros(n); eval_hwm = np.zeros(n); eval_floor = np.full(n,-2000.0)
    funded_eq = np.zeros(n); funded_hwm = np.zeros(n); funded_floor = np.full(n,-2000.0)
    funded_dll_limit = np.full(n,1250.0)
    locked = np.zeros(n, dtype=bool)
    eval_active_days = np.zeros(n,dtype=int)
    eval_pass_day = np.full(n,-1,dtype=int)
    fail_eval = np.zeros(n,dtype=bool)
    fail_funded = np.zeros(n,dtype=bool)
    fail_funded_day = np.full(n,-1,dtype=int)
    eval_dll_hits = np.zeros(n,dtype=int)
    dll_hits = np.zeros(n,dtype=int)
    funded_age = np.zeros(n,dtype=int)
    win_days = np.zeros(n,dtype=int)
    cycle_profit = np.zeros(n)
    best_cycle_day = np.zeros(n)
    payout_count = np.zeros(n,dtype=int)
    payout_cash = np.zeros(n)
    first_payout_cash = np.zeros(n)
    first_payout_day = np.full(n,-1,dtype=int)
    pending_amount = np.zeros(n)
    pending_days = np.zeros(n,dtype=int)
    cycle_best_day = np.zeros(n)
    for d in range(h):
        start_phase = phase.copy()
        raw_daily = paths[:,d] * risk
        consistency_daily = consistency_paths[:,d] * risk
        # Growth DLL is a soft pause. Evaluation starts at $1,250. On funded
        # accounts, it rises to $2,000 from the next session after the balance
        # first reaches $53,000 (+$3,000). Closed-PnL clipping is only an
        # approximation; intraday trigger timing and overshoot are unavailable.
        eval_daily = np.maximum(raw_daily, -1250.0)
        funded_daily = np.maximum(raw_daily, -funded_dll_limit)
        act = active[:,d]

        ev = start_phase == 0
        if ev.any():
            eval_eq[ev] += eval_daily[ev]
            eval_dll_hits[ev & (raw_daily <= -1250.0)] += 1
            eval_active_days[ev] += act[ev].astype(int)
            eval_hwm[ev] = np.maximum(eval_hwm[ev], eval_eq[ev])
            eval_floor[ev] = np.maximum(eval_floor[ev], eval_hwm[ev] - 2000.0)
            hit_floor = ev & (eval_eq <= eval_floor)
            fail_eval |= hit_floor
            phase[hit_floor] = 2
            min_days_ok = eval_active_days >= 1
            passed = ev & (phase == 0) & (eval_eq >= 3000.0) & min_days_ok
            if passed.any():
                eval_pass_day[passed] = d
                phase[passed] = 1
                funded_eq[passed] = 0.0
                funded_hwm[passed] = 0.0
                funded_floor[passed] = -2000.0
                locked[passed] = False
                funded_age[passed] = 0
                win_days[passed] = 0
                cycle_profit[passed] = 0.0
                best_cycle_day[passed] = 0.0
                payout_count[passed] = 0

        fu = (start_phase == 1) & (phase == 1)
        if fu.any():
            funded_eq[fu] += funded_daily[fu]
            funded_age[fu] += 1
            dll_hits[fu & (raw_daily <= -funded_dll_limit)] += 1
            # Tradeify's 35% consistency rule excludes commissions. Use the
            # matched gross daily PnL series for this test; account equity,
            # DLL, drawdown and winning-day checks remain net of trading costs.
            cycle_profit[fu] += consistency_daily[fu]
            best_cycle_day[fu] = np.maximum(best_cycle_day[fu], consistency_daily[fu])
            win_days[fu] += (funded_daily[fu] > 150.0).astype(int)
            # The higher DLL applies from the next simulated trading session.
            funded_dll_limit[fu & (funded_eq >= 3000.0)] = 2000.0

            # EOD trailing update from the closed daily equity path.
            funded_hwm[fu] = np.maximum(funded_hwm[fu], funded_eq[fu])
            lock_now = fu & (~locked) & (funded_hwm >= 2100.0)
            locked[lock_now] = True
            funded_floor[fu & locked] = 100.0
            funded_floor[fu & (~locked)] = np.maximum(funded_floor[fu & (~locked)], funded_hwm[fu & (~locked)] - 2000.0)

            hit_floor = fu & (funded_eq <= funded_floor)
            fail_funded |= hit_floor
            fail_funded_day[hit_floor] = d
            phase[hit_floor] = 2

            # A payout request is subject to 2-day processing. Balance must stay
            # at or above +$3,000 until approval. The model assumes requests are
            # submitted at EOD and trading continues during processing.
            pending = fu & (pending_days > 0) & (phase == 1)
            if pending.any():
                denied = pending & (funded_eq < 3000.0)
                pending_days[denied] = 0
                pending_amount[denied] = 0.0
                approve = pending & (~denied) & (pending_days <= 1)
                if approve.any():
                    payout_cash[approve] += 0.90 * pending_amount[approve]
                    first_new = approve & (first_payout_day < 0)
                    first_payout_cash[first_new] = 0.90 * pending_amount[first_new]
                    first_payout_day[first_new] = d
                    funded_eq[approve] -= pending_amount[approve]
                    payout_count[approve] += 1
                    cycle_profit[approve] = 0.0
                    best_cycle_day[approve] = 0.0
                    win_days[approve] = 0
                    pending_days[approve] = 0
                    pending_amount[approve] = 0.0
                pending_days[pending & (~denied) & (~approve)] -= 1

            no_pending = fu & (pending_days == 0) & (phase == 1)
            consistency_ok = (cycle_profit > 0) & (best_cycle_day <= 0.35 * cycle_profit)
            payout_ok = (funded_eq >= 3000.0) & (win_days >= 5) & consistency_ok
            if not microscalp_ok or not weekly_activity_ok or not position_limit_compliant:
                payout_ok[:] = False
            cap_idx = np.minimum(payout_count,3)
            caps = np.array([1500.0,2000.0,2500.0,3000.0])
            cap = caps[cap_idx]
            available = np.maximum(0.0, funded_eq - funded_floor)
            amount = np.minimum(cap, available)
            request = no_pending & payout_ok & (amount >= 500.0)
            pending_amount[request] = amount[request]
            pending_days[request] = 2

    target_reached = eval_pass_day >= 0
    # Weekly activity applies during evaluation and funded trading. The
    # microscalping test applies to funded payout eligibility only.
    evaluation_account_eligible = bool(weekly_activity_ok and position_limit_compliant)
    payout_account_eligible = bool(weekly_activity_ok and microscalp_ok and position_limit_compliant)
    reached_funded = target_reached & evaluation_account_eligible
    first_payout = first_payout_day >= 0
    survived_90 = []
    for i in np.where(reached_funded)[0]:
        pass_day = eval_pass_day[i]
        end_day = pass_day + 90
        if end_day < h:
            survived_90.append(fail_funded_day[i] < 0 or fail_funded_day[i] > end_day)
    return {
        "evaluation_target_hit_rate": float(target_reached.mean()),
        "evaluation_pass_rate": float(reached_funded.mean()),
        "evaluation_account_eligible": evaluation_account_eligible,
        "funded_payout_eligible": payout_account_eligible,
        "funded_first_payout_rate_conditional": float(first_payout[reached_funded].mean()) if reached_funded.any() else np.nan,
        "challenge_to_first_payout_rate": float(first_payout.mean()),
        "funded_hard_breach_rate": float(fail_funded.mean()),
        "funded_hard_breach_rate_conditional": float(fail_funded[reached_funded].mean()) if reached_funded.any() else np.nan,
        "evaluation_hard_breach_rate": float(fail_eval.mean()),
        "evaluation_soft_dll_hit_days_mean": float(eval_dll_hits.mean()),
        "daily_loss_soft_breach_days_mean": float(dll_hits.mean()),
        "median_days_to_evaluation_pass": float(np.median(eval_pass_day[reached_funded]) + 1) if reached_funded.any() else np.nan,
        "median_days_to_first_payout_from_start": float(np.median(first_payout_day[first_payout]) + 1) if first_payout.any() else np.nan,
        "median_funded_days_to_first_payout": float(np.median(first_payout_day[first_payout] - eval_pass_day[first_payout]) + 1) if first_payout.any() else np.nan,
        "first_payout_net_usd_mean": float(first_payout_cash.mean()),
        "total_net_payout_cash_mean": float(payout_cash.mean()),
        "first_payout_net_usd_median_conditional": float(np.median(first_payout_cash[first_payout])) if first_payout.any() else 0.0,
        "any_payout_rate": float((payout_count > 0).mean()),
        "payout_count_mean": float(payout_count.mean()),
        "survival_90d_conditional_approx": float(np.mean(survived_90)) if survived_90 else np.nan,
        "survival_90d_observed_sample_count": int(len(survived_90)),
        "microscalping_eligible": bool(microscalp_ok),
        "weekly_activity_eligible": bool(weekly_activity_ok),
        "evaluation_consistency_variant": "official Growth rules: no evaluation consistency",
        "simulations": int(n), "horizon_trading_days": int(h),
        "note": "35% consistency uses gross daily PnL before commissions; account balance, DLL, trailing drawdown and $150 winning-day checks use net closed PnL. EOD trailing updates are modeled. Closed daily losses are clipped at -$1,250 initially and -$2,000 from the next session after +$3,000 funded profit; intraday DLL trigger timing, overshoot, floating equity and slippage are not reconstructable from closed-trade exports.",
    }

def microscalping_stats(trades):
    if trades.empty:
        return {"trade_share_over_10s": np.nan, "profit_share_over_10s": np.nan,
                "duration_coverage": 0.0, "eligible": False}
    known = trades.dropna(subset=["duration_seconds"]).copy()
    coverage = len(known) / len(trades)
    long = known["duration_seconds"] > 10.0
    # Missing durations count as not-over-10s; use all trades and all positive
    # profit as denominators so incomplete timestamps cannot create eligibility.
    trade_share = float(long.sum() / len(trades))
    pos_total = float(trades.loc[trades["native_pnl"] > 0, "native_pnl"].sum())
    pos_long = float(known.loc[long & (known["native_pnl"] > 0), "native_pnl"].sum())
    profit_share = pos_long / pos_total if pos_total > 0 else 0.0
    return {"trade_share_over_10s": trade_share, "profit_share_over_10s": profit_share,
            "duration_coverage": float(coverage),
            "eligible": bool(trade_share > .50 and profit_share > .50)}

def weekly_activity_ok(active):
    if len(active) < 5:
        return False
    # Ignore incomplete first/last calendar weeks in the validation window.
    flags = active.astype(int)
    weekly = flags.resample("W-FRI").sum()
    weekdays = flags.resample("W-FRI").size()
    full_weeks = weekly[weekdays >= 5]
    return bool(len(full_weeks) and (full_weeks > 0).all())

def max_concurrent_mini_equiv(trades, combo, sizes):
    events = []
    for strategy in combo:
        t = trades[trades["strategy"] == strategy]
        size = sizes[strategy]
        for _, r in t.iterrows():
            if pd.isna(r["entry_timestamp"]) or pd.isna(r["exit_timestamp"]):
                continue
            events.append((r["entry_timestamp"], 1, size))
            events.append((r["exit_timestamp"], 0, -size))
    events.sort(key=lambda x:(x[0],x[1]))
    current = peak = 0.0
    for _, _, delta in events:
        current += delta
        peak = max(peak, current)
    return float(peak)

def tradeify_position_weights(trades, combo, requested_total_risk, exposure_trades=None):
    """One micro minimum, whole-micro sizing, four-mini account cap.

    Risk units come from the training-calibrated full trade frame; simultaneous
    exposure is checked only on the validation-period overlap frame.
    """
    exposure_source = trades if exposure_trades is None else exposure_trades
    per_sleeve = requested_total_risk / max(1, len(combo))
    units = {}
    sizes = {}
    for strategy in combo:
        t = trades[trades["strategy"] == strategy]
        unit = float(t["risk_unit"].iloc[0]) if not t.empty else 0.0
        units[strategy] = max(unit, 1e-9)
        raw_size = per_sleeve / units[strategy]
        # Futures micros are 0.1 mini increments. Round down to avoid
        # exceeding the target risk, but never below one micro.
        sizes[strategy] = max(0.1, math.floor(raw_size * 10.0 + 1e-9) / 10.0)
    def exposure_for(size_map):
        events = []
        for strategy in combo:
            t = exposure_source[exposure_source["strategy"] == strategy]
            for _, r in t.iterrows():
                if pd.isna(r["entry_timestamp"]) or pd.isna(r["exit_timestamp"]):
                    continue
                size = size_map[strategy]
                events.append((r["entry_timestamp"], 1, size))
                events.append((r["exit_timestamp"], 0, -size))
        events.sort(key=lambda x:(x[0],x[1]))
        current = peak = 0.0
        for _, _, delta in events:
            current += delta
            peak = max(peak, current)
        return float(peak)
    exposure = exposure_for(sizes)
    scale = 1.0
    if exposure > 4.0:
        scale = 4.0 / exposure
        sizes = {s:max(0.1, math.floor(size*scale*10.0+1e-9)/10.0) for s,size in sizes.items()}
        exposure = exposure_for(sizes)
    compliant = exposure <= 4.0 + 1e-9
    weights = {s:sizes[s]*units[s] for s in combo}
    return weights, sizes, exposure, scale, compliant

def weighted_daily_pnl(rmat, dates, combo, weights):
    result = pd.Series(0.0, index=dates)
    for strategy in combo:
        result = result + rmat.loc[dates, strategy] * weights[strategy]
    return result

def simulate_recovery(paths, risk, floor, start_cushion, target, daily_limit=None, daily_limit_mode="hard"):
    n,h=paths.shape
    eq=np.full(n, floor+start_cushion, dtype=float)
    recovered=eq >= target
    ruined=eq <= floor
    day=np.where(recovered,0,-1).astype(int)
    soft_pause_days=np.zeros(n,dtype=int)
    for d in range(h):
        raw_daily=paths[:,d]*risk
        active=~recovered & ~ruined
        bad_day=np.zeros(n,dtype=bool)
        daily=raw_daily.copy()
        if daily_limit is not None and daily_limit_mode=="hard":
            bad_day=active & (raw_daily < -daily_limit)
        elif daily_limit is not None and daily_limit_mode=="soft":
            soft_pause_days[active & (raw_daily <= -daily_limit)] += 1
            daily=np.maximum(raw_daily, -daily_limit)
        eq[active] += daily[active]
        ruined |= active & ((eq <= floor) | bad_day)
        hit=active & (~ruined) & (eq >= target)
        recovered[hit]=True
        day[hit]=d
    return {
        "recovery_probability": float(recovered.mean()),
        "ruin_probability": float(ruined.mean()),
        "soft_dll_pause_days_mean": float(soft_pause_days.mean()),
        "median_days_to_target": float(np.median(day[recovered])+1) if recovered.any() else np.nan,
        "mean_terminal_equity": float(eq.mean()),
    }

def write_json(path, obj):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(obj,indent=2,default=str),encoding="utf-8")

def build_prop_outputs(firm_dir, df, recovery_df, risk_col, base_risk,
                       pass_col, payout_col, breach_col, title,
                       eligibility_cols=None, stress_filter=None, funded_pool=None):
    charts=firm_dir/"charts"
    reports=firm_dir/"reports"
    charts.mkdir(parents=True,exist_ok=True)
    base=df[df[risk_col].astype(float).eq(float(base_risk))].copy()
    if stress_filter and stress_filter in base.columns:
        base=base[base[stress_filter].astype(str).str.contains("base case|no consistency",case=False,regex=True)]
    if eligibility_cols:
        for col in eligibility_cols:
            if col in base.columns:
                base=base[base[col].astype(str).str.lower().eq("true")]
    # Do not silently fall back to ineligible books when no candidate passes
    # the firm's minimum activity, microscalping or position-limit screens.
    conditional_col=("funded_first_payout_rate_conditional" if "funded_first_payout_rate_conditional" in base.columns
                     else "funded_first_reward_rate_conditional")
    ranking=base.copy()
    ranking["validation_funded_score"]=(ranking[conditional_col].astype(float)*
                                         (1.0-ranking[breach_col].astype(float))) if conditional_col in ranking.columns else 0.0
    ranking["validation_payout_rank"]=ranking[payout_col].rank(ascending=False,method="min").astype(int)
    ranking["validation_funded_rank"]=ranking["validation_funded_score"].rank(ascending=False,method="min").astype(int)
    # Candidate selection is frozen on the training segment. Validation Monte
    # Carlo estimates are reported as holdout outcomes, not used to choose the
    # winner after looking at the holdout.
    if "train_challenge_score" in ranking.columns:
        ranking=ranking.sort_values(["train_challenge_score","train_funded_score"],ascending=False)
    else:
        ranking=ranking.sort_values(payout_col,ascending=False)
    ranking.to_csv(reports/"book_rankings.csv",index=False)

    top_books=ranking["book"].head(3).tolist()
    fig,ax=plt.subplots(figsize=(10.5,5.8))
    for book in top_books:
        g=df[df["book"]==book].copy()
        if stress_filter and stress_filter in g.columns:
            g=g[g[stress_filter].astype(str).str.contains("base case|no consistency",case=False,regex=True)]
        g=g.sort_values(risk_col)
        ax.plot(g[risk_col].astype(float),g[payout_col].astype(float),marker="o",linewidth=1.7,label=book)
    ax.set_title(f"{title}: challenge-to-payout probability",loc="left",fontweight="bold")
    ax.set_xlabel("Requested total book risk per trade (USD)")
    ax.set_ylabel("Probability")
    ax.set_ylim(0,1)
    ax.grid(True,alpha=.25,linestyle="--")
    ax.legend(fontsize=7,loc="best")
    fig.tight_layout()
    fig.savefig(charts/"challenge_to_payout_probability.png",dpi=160,bbox_inches="tight")
    plt.close(fig)

    fig,ax=plt.subplots(figsize=(10.5,5.8))
    for book in top_books:
        g=df[df["book"]==book].copy()
        if stress_filter and stress_filter in g.columns:
            g=g[g[stress_filter].astype(str).str.contains("base case|no consistency",case=False,regex=True)]
        g=g.sort_values(risk_col)
        ax.plot(g[risk_col].astype(float),g[breach_col].astype(float),marker="o",linewidth=1.7,label=book)
    ax.set_title(f"{title}: drawdown breach probability",loc="left",fontweight="bold")
    ax.set_xlabel("Requested total book risk per trade (USD)")
    ax.set_ylabel("Probability")
    ax.set_ylim(0,1)
    ax.grid(True,alpha=.25,linestyle="--")
    ax.legend(fontsize=7,loc="best")
    fig.tight_layout()
    fig.savefig(charts/"drawdown_breach_probability.png",dpi=160,bbox_inches="tight")
    plt.close(fig)

    if not recovery_df.empty:
        target_col="target_label" if "target_label" in recovery_df.columns else "state"
        rec=recovery_df.copy()
        # Firms publish different cushion grids (The5ers 100, Moneta 150/300/500/750,
        # Tradeify 200), so pick the grid point closest to the preferred cushion
        # instead of dropping the recovery chart when the exact value is absent.
        preferred_cushion=100.0 if "The5ers" in title else 200.0
        near_cushion=min(sorted(rec["starting_cushion_usd"].astype(float).unique()),
                         key=lambda v:(abs(v-preferred_cushion),v))
        near=rec[rec["starting_cushion_usd"].astype(float).eq(near_cushion)]
        if target_col=="target_label":
            near=near[near[target_col].astype(str).str.contains("buffer",case=False,regex=True)]
            buffer_rows=rec[rec[target_col].astype(str).str.contains("buffer",case=False,regex=True)]
        else:
            buffer_rows=rec
        if "weekly_activity_eligible" in near.columns:
            near=near[near["weekly_activity_eligible"].astype(bool)]
            buffer_rows=buffer_rows[(buffer_rows["weekly_activity_eligible"].astype(bool)) | (buffer_rows["book"]=="No trade")]
        active_near=near[near["book"]!="No trade"]
        if not active_near.empty:
            chosen=active_near.sort_values(
                ["recovery_probability","ruin_probability"],ascending=[False,True]
            ).iloc[0]["book"]
            g=buffer_rows[buffer_rows["book"].isin([chosen,"No trade"])]
            fig,ax=plt.subplots(figsize=(10.5,5.8))
            g["series_label"]=g.apply(
                lambda row: "No trade (zero-risk control)" if row["book"]=="No trade" else
                f'{row["book"]} | USD {float(row["risk_usd_per_book_trade"]):,.2f}/trade',
                axis=1)
            for label,part in g.groupby("series_label"):
                part=part.sort_values("starting_cushion_usd")
                ax.plot(part["starting_cushion_usd"],part["recovery_probability"],
                        marker="o",label=str(label))
            ax.set_title(f"{title}: near-floor recovery | {chosen} vs no-trade",loc="left",fontweight="bold")
            ax.set_xlabel("Starting cushion above breach floor (USD)")
            ax.set_ylabel("Probability of reaching target")
            ax.set_ylim(0,1)
            ax.grid(True,alpha=.25,linestyle="--")
            ax.legend(fontsize=7,loc="best")
            fig.tight_layout()
            fig.savefig(charts/"recovery_probability.png",dpi=160,bbox_inches="tight")
            plt.close(fig)

        # Tradeify's $53k balance target is separate from the $500 floor buffer
        # and is not a payout-eligibility simulation.
        if target_col=="target_label":
            payout_rows=rec[rec[target_col].astype(str).str.contains("53,000",case=False,regex=True)]
            if "weekly_activity_eligible" in payout_rows.columns:
                payout_rows=payout_rows[(payout_rows["weekly_activity_eligible"].astype(bool) &
                                          payout_rows["microscalping_eligible"].astype(bool)) |
                                         (payout_rows["book"]=="No trade")]
            payout_near=payout_rows[payout_rows["starting_cushion_usd"].astype(float).eq(near_cushion)]
            payout_active=payout_near[payout_near["book"]!="No trade"]
            if not payout_active.empty:
                payout_chosen=payout_active.sort_values(
                    ["recovery_probability","ruin_probability"],ascending=[False,True]
                ).iloc[0]["book"]
                g=payout_rows[payout_rows["book"].isin([payout_chosen,"No trade"])]
                fig,ax=plt.subplots(figsize=(10.5,5.8))
                g["series_label"]=g.apply(
                    lambda row: "No trade (zero-risk control)" if row["book"]=="No trade" else
                    f'{row["book"]} | USD {float(row["risk_usd_per_book_trade"]):,.2f}/trade',
                    axis=1)
                for label,part in g.groupby("series_label"):
                    part=part.sort_values("starting_cushion_usd")
                    ax.plot(part["starting_cushion_usd"],part["recovery_probability"],
                            marker="o",label=str(label))
                ax.set_title(f"{title}: $53k balance recovery | {payout_chosen} vs no-trade",loc="left",fontweight="bold")
                ax.set_xlabel("Starting cushion above locked floor (USD)")
                ax.set_ylabel("Probability of reaching $53,000 balance")
                ax.set_ylim(0,1)
                ax.grid(True,alpha=.25,linestyle="--")
                ax.legend(fontsize=7,loc="best")
                fig.tight_layout()
                fig.savefig(charts/"recovery_payout_threshold_probability.png",dpi=160,bbox_inches="tight")
                plt.close(fig)

    if "evaluation_hard_breach_rate" in df.columns:
        fig,ax=plt.subplots(figsize=(10.5,5.8))
        for book in top_books:
            g=df[df["book"]==book].copy()
            if stress_filter and stress_filter in g.columns:
                g=g[g[stress_filter].astype(str).str.contains("base case|no consistency",case=False,regex=True)]
            g=g.sort_values(risk_col)
            ax.plot(g[risk_col].astype(float),g["evaluation_hard_breach_rate"].astype(float),marker="o",linewidth=1.7,label=book)
        ax.set_title(f"{title}: evaluation drawdown breach probability",loc="left",fontweight="bold")
        ax.set_xlabel("Requested total book risk per trade (USD)")
        ax.set_ylabel("Probability")
        ax.set_ylim(0,1)
        ax.grid(True,alpha=.25,linestyle="--")
        ax.legend(fontsize=7,loc="best")
        fig.tight_layout()
        fig.savefig(charts/"evaluation_breach_probability.png",dpi=160,bbox_inches="tight")
        plt.close(fig)

    challenge=ranking.iloc[0] if len(ranking) else None
    funded_pool_df=base
    if funded_pool and "train_challenge_score" in base.columns:
        # A funded-stage book still has to be reachable: for multi-step programs
        # restrict the funded choice to the best training challenge books.
        funded_pool_df=base.sort_values("train_challenge_score",ascending=False).head(int(funded_pool))
    if len(funded_pool_df) and "train_funded_score" in funded_pool_df.columns:
        funded=funded_pool_df.sort_values("train_funded_score",ascending=False).iloc[0]
    else:
        funded=base.assign(validation_funded_score=base[conditional_col].astype(float)*(1.0-base[breach_col].astype(float))).sort_values("validation_funded_score",ascending=False).iloc[0] if len(base) and conditional_col in base.columns else challenge
    recovery_candidate="No active book met the near-floor recovery threshold; preserve the account rather than force trades."
    if not recovery_df.empty:
        near_cushion=100.0 if "The5ers" in title else 200.0
        target_rows=recovery_df[recovery_df["starting_cushion_usd"].astype(float).eq(near_cushion)]
        if "target_label" in target_rows.columns:
            target_rows=target_rows[target_rows["target_label"].astype(str).str.contains("break-even|buffer",case=False,regex=True)]
        if "weekly_activity_eligible" in target_rows.columns:
            target_rows=target_rows[target_rows["weekly_activity_eligible"].astype(bool)]
        if "Tradeify" in title and "microscalping_eligible" in target_rows.columns:
            target_rows=target_rows[target_rows["microscalping_eligible"].astype(bool)]
        viable=target_rows[(target_rows["book"]!="No trade") & (target_rows["ruin_probability"].astype(float)<=0.05) & (target_rows["recovery_probability"].astype(float)>=0.50)]
        if len(viable):
            best=viable.sort_values("recovery_probability",ascending=False).iloc[0]
            recovery_candidate=f'{best["book"]} at USD {float(best["risk_usd_per_book_trade"]):,.2f} risk per book trade: recovery probability {best["recovery_probability"]:.1%}, breach probability {best["ruin_probability"]:.1%}.'
        else:
            active_target=target_rows[target_rows["book"]!="No trade"].copy()
            if len(active_target):
                best_recovery=active_target.sort_values(
                    ["recovery_probability","ruin_probability"],ascending=[False,True]).iloc[0]
                best_survival=active_target.sort_values(
                    ["ruin_probability","recovery_probability"],ascending=[True,False]).iloc[0]
                lowest_exposure=active_target.sort_values(
                    ["risk_usd_per_book_trade","ruin_probability"],ascending=[True,True]).iloc[0]
                detail=(f'Best recovery chance: {best_recovery["book"]} at USD {float(best_recovery["risk_usd_per_book_trade"]):,.2f} risk '
                        f'({float(best_recovery["recovery_probability"]):.1%} recovery; {float(best_recovery["ruin_probability"]):.1%} breach). '
                        f'Lowest-breach active choice: {best_survival["book"]} at USD {float(best_survival["risk_usd_per_book_trade"]):,.2f} risk '
                        f'({float(best_survival["recovery_probability"]):.1%} recovery; {float(best_survival["ruin_probability"]):.1%} breach). '
                        f'Lowest-exposure active choice: {lowest_exposure["book"]} at USD {float(lowest_exposure["risk_usd_per_book_trade"]):,.2f} risk '
                        f'({float(lowest_exposure["recovery_probability"]):.1%} recovery; {float(lowest_exposure["ruin_probability"]):.1%} breach).')
                if "The5ers" in title:
                    non_rbe=active_target[~active_target["book"].astype(str).str.contains(r"Gold ORB \(RBE\)",regex=True)]
                    if len(non_rbe):
                        nr=non_rbe.sort_values(
                            ["recovery_probability","ruin_probability"],ascending=[False,True]).iloc[0]
                        detail += (f' Best RBE-excluded alternative: {nr["book"]} at USD {float(nr["risk_usd_per_book_trade"]):,.2f} risk '
                                   f'({float(nr["recovery_probability"]):.1%} recovery; {float(nr["ruin_probability"]):.1%} breach).')
            else:
                detail="No active candidate passed the eligibility screen."
            if "Tradeify" in title:
                recovery_candidate=("No weekly-eligible active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $200 cushion. "
                                    "No-trade preserves the floor but is not a compliant long-term mode because weekly activity is required. "+detail)
            else:
                recovery_candidate=("No active candidate achieves both at least 50% recovery probability and at most 5% modeled breach probability at the $100 cushion. "
                                    "No-trade preserves the account but cannot recover it to initial balance. "+detail)

    lines=[f"# {title} — book ranking",
           "",
           f"Base comparison risk: USD {base_risk:,.0f} requested total risk per book trade.",
           "",
           "Book selection uses training-only challenge/funded scores. All one-to-four-sleeve combinations are evaluated on the later validation sample; the validation-best row is shown separately as a diagnostic, not selected as the winner.",
           ("The funded-stage book is the highest training-funded-score book among the ten best training challenge books, so it is a book that can realistically reach funding." if funded_pool else ""),
           "",
           "## Challenge candidate"]
    if challenge is not None:
        lines += [f'- **{challenge["book"]}** ({challenge["strategies"]})',
                  f'  - Challenge-to-payout: {float(challenge[payout_col]):.1%}',
                  f'  - {"Reach funded" if "The5ers" in title else "Pass rate"}: {float(challenge[pass_col]):.1%}',
                  f'  - Evaluation hard-breach rate: {float(challenge["evaluation_hard_breach_rate"]):.1%}' if "evaluation_hard_breach_rate" in challenge else "  - Evaluation hard-breach rate: unavailable",
                  f'  - Funded hard-breach rate (conditional on funding): {float(challenge[breach_col]):.1%}']
        for key,label in [
            ("effective_risk_after_micro_sizing_usd","Effective risk after minimum-micro sizing"),
            ("median_days_to_evaluation_pass","Median trading days to eligible evaluation pass"),
            ("median_days_to_phase1","Median trading days to Step 1 pass"),
            ("median_days_to_phase2","Median trading days through all evaluation steps"),
            ("median_days_to_first_payout_from_start","Median trading days to first payout"),
            ("median_days_to_first_reward_from_start","Median trading days to first The5ers payout"),
            ("expected_first_reward_usd","Expected first The5ers payout across all paths"),
            ("median_first_reward_usd_conditional","Median The5ers payout on successful paths"),
        ]:
            if key in challenge.index and pd.notna(challenge[key]):
                lines.append(f'  - {label}: {float(challenge[key]):,.1f}' if "days" in key else f'  - {label}: USD {float(challenge[key]):,.2f}')
    if "The5ers" in title and "train_challenge_score" in base.columns:
        no_rbe=base[~base["strategies"].astype(str).str.contains("Gold ORB (RBE)",regex=False)]
        if len(no_rbe):
            nr=no_rbe.sort_values("train_challenge_score",ascending=False).iloc[0]
            lines += ["","## RBE-excluded challenge sensitivity",
                      f'- **{nr["book"]}** ({nr["strategies"]})',
                      f'  - Challenge-to-first-reward: {float(nr[payout_col]):.1%}',
                      f'  - {"Reach funded" if "The5ers" in title else "Pass both phases"}: {float(nr[pass_col]):.1%}',
                      f'  - Evaluation hard-breach rate: {float(nr["evaluation_hard_breach_rate"]):.1%}',
                      f'  - Funded hard-breach rate (conditional on funding): {float(nr[breach_col]):.1%}']
    validation_best=base.sort_values(payout_col,ascending=False).iloc[0] if len(base) else None
    if validation_best is not None and challenge is not None and validation_best["book"]!=challenge["book"]:
        lines += ["","## Holdout validation leader (diagnostic only)",
                  f'- **{validation_best["book"]}** ({validation_best["strategies"]})',
                  f'  - Challenge-to-payout: {float(validation_best[payout_col]):.1%}',
                  f'  - {"Reach funded" if "The5ers" in title else "Pass rate"}: {float(validation_best[pass_col]):.1%}',
                  f'  - Evaluation hard-breach rate: {float(validation_best["evaluation_hard_breach_rate"]):.1%}' if "evaluation_hard_breach_rate" in validation_best else "  - Evaluation hard-breach rate: unavailable"]
    lines += ["","## Funded candidate"]
    if funded is not None:
        lines += [f'- **{funded["book"]}** ({funded["strategies"]})',
                  f'  - Conditional first-payout rate: {float(funded[conditional_col]):.1%}' if conditional_col in funded else "  - Conditional first-payout rate: unavailable",
                  f'  - Funded hard-breach rate (conditional on funding): {float(funded[breach_col]):.1%}']
        for key,label in [
            ("effective_risk_after_micro_sizing_usd","Effective risk after minimum-micro sizing"),
            ("survival_90d_conditional_approx","Approximate 90-trading-day funded survival"),
            ("first_payout_net_usd_median_conditional","Median first net payout on successful paths"),
            ("first_payout_net_usd_mean","Expected first net payout across all paths"),
            ("total_net_payout_cash_mean","Expected total net payout cash across all paths"),
            ("payout_count_mean","Mean payout count over the horizon"),
            ("median_days_to_first_payout_from_start","Median trading days to first payout"),
            ("median_days_to_first_reward_from_start","Median trading days to first The5ers payout"),
        ]:
            if key in funded.index and pd.notna(funded[key]):
                if "days" in key:
                    lines.append(f'  - {label}: {float(funded[key]):,.1f}')
                elif "survival" in key:
                    lines.append(f'  - {label}: {float(funded[key]):.1%}')
                elif "payout_count" in key:
                    lines.append(f'  - {label}: {float(funded[key]):.2f}')
                else:
                    lines.append(f'  - {label}: USD {float(funded[key]):,.2f}')
    # Show the complete risk ladder for the selected books in the human-readable
    # report. The full Monte Carlo CSV still contains every one-to-four-sleeve
    # combination; these compact tables make the recommended candidates auditable.
    def append_risk_ladder(section_title, selected_row):
        if selected_row is None:
            return
        selected_book = str(selected_row["book"])
        ladder = df[df["book"].astype(str).eq(selected_book)].sort_values(risk_col)
        if ladder.empty:
            return
        effective_col = "effective_risk_after_micro_sizing_usd"
        median_col = ("median_days_to_first_payout_from_start" if "Tradeify" in title
                      else "median_days_to_first_reward_from_start")
        expected_col = ("first_payout_net_usd_mean" if "Tradeify" in title
                        else "expected_first_reward_usd")
        has_survival = "survival_90d_conditional_approx" in ladder.columns
        headers = ["Requested risk", "Effective risk", "Pass", "Evaluation breach",
                   "Challenge-to-payout", "Funded breach"]
        if has_survival:
            headers.append("90-day survival")
        headers += [
            "Median payout days", "Expected first payout",
            "Mean monthly PnL", "P10 monthly PnL", "P90 monthly DD", "P95 252d max DD"
        ]
        lines.extend([
            "", f"### {section_title}",
            "Monthly PnL uses 21-trading-day blocks. P10 is the 10th-percentile month; P90 monthly DD is the 90th-percentile within-month peak-to-trough drawdown. The 252-day DD is the 95th-percentile full-path drawdown.",
            "| " + " | ".join(headers) + " |",
            "| " + " | ".join(["---"] * len(headers)) + " |"
        ])
        for _, row in ladder.iterrows():
            requested = float(row[risk_col])
            effective = (float(row[effective_col]) if effective_col in row.index and pd.notna(row[effective_col])
                         else requested)
            cells = [f"${requested:,.0f}", f"${effective:,.2f}" if effective_col in row.index else f"${effective:,.0f}",
                     f"{float(row[pass_col]):.1%}", f"{float(row['evaluation_hard_breach_rate']):.1%}",
                     f"{float(row[payout_col]):.1%}", f"{float(row[breach_col]):.1%}"]
            if has_survival:
                cells.append(f"{float(row['survival_90d_conditional_approx']):.1%}")
            median_days = row.get(median_col, np.nan)
            cells.append(f"{float(median_days):.0f}" if pd.notna(median_days) else "—")
            expected = row.get(expected_col, np.nan)
            cells.append(f"${float(expected):,.2f}" if pd.notna(expected) else "—")
            for metric in [
                "mean_monthly_strategy_pnl_usd",
                "p10_monthly_strategy_pnl_usd",
                "p90_monthly_peak_to_trough_dd_usd",
                "p95_max_drawdown_252d_usd",
            ]:
                value = row.get(metric, np.nan)
                cells.append(f"${float(value):,.0f}" if pd.notna(value) else "—")
            lines.append("| " + " | ".join(cells) + " |")

    append_risk_ladder("Challenge candidate risk ladder", challenge)
    if funded is not None and (challenge is None or str(funded["book"]) != str(challenge["book"])):
        append_risk_ladder("Funded candidate risk ladder", funded)

    if challenge is not None and funded is not None:
        challenge_pass = float(challenge[pass_col])
        funded_first_rate = float(funded.get(conditional_col, np.nan))
        evaluation_breach = float(challenge.get("evaluation_hard_breach_rate", np.nan))
        funded_breach = float(funded.get(breach_col, np.nan))
        combined_payout_rate = challenge_pass * funded_first_rate
        combined_hard_breach = evaluation_breach + challenge_pass * funded_breach
        if 0 < challenge_pass <= 1 and 0 < funded_first_rate <= 1:
            expected_challenge_accounts = 1.0 / combined_payout_rate
            expected_funded_accounts = 1.0 / funded_first_rate
            expected_failed_evaluation_accounts = max(0.0, expected_challenge_accounts - expected_funded_accounts)
            expected_failed_funded_accounts = max(0.0, expected_funded_accounts - 1.0)
            lines += [
                "", "## Expected account attempts before first payout",
                f"- Challenge pass probability: {challenge_pass:.1%}.",
                f"- First-payout probability after funding with the selected funded book: {funded_first_rate:.1%}.",
                f"- Approximate payout probability per challenge start when switching to the selected funded book: {combined_payout_rate:.1%}.",
                f"- Expected challenge accounts started per first payout: {expected_challenge_accounts:.2f}.",
                f"- Expected failed evaluation accounts before first payout: {expected_failed_evaluation_accounts:.2f}.",
                f"- Expected funded accounts entered per first payout: {expected_funded_accounts:.2f}.",
                f"- Expected failed funded accounts before first payout: {expected_failed_funded_accounts:.2f}.",
                f"- Approximate combined hard-breach probability per challenge start: {combined_hard_breach:.1%}.",
                "These are geometric-repeat estimates. They assume each new account repeats the same probabilities; they are not a guarantee and do not include account fees.",
            ]

    if "Tradeify" in title and "train_funded_score" in base.columns:
        pair_rows = base[base["strategies"].astype(str).str.count(r"\+") == 1].copy()
        if not pair_rows.empty:
            pair = pair_rows.sort_values("train_funded_score", ascending=False).iloc[0]
            lines += ["", "## Lower-risk two-sleeve alternative",
                      f'- **{pair["strategies"]}** (top training-funded-score candidate among eligible two-sleeve books)',
                      f'  - Requested risk: USD {float(pair[risk_col]):,.2f}',
                      f'  - Effective risk after minimum-micro sizing: USD {float(pair["effective_risk_after_micro_sizing_usd"]):,.2f}',
                      f'  - Evaluation pass rate: {float(pair[pass_col]):.1%}',
                      f'  - Evaluation hard-breach rate: {float(pair["evaluation_hard_breach_rate"]):.1%}',
                      f'  - Challenge-to-first-payout rate: {float(pair[payout_col]):.1%}',
                      f'  - Funded first-payout rate conditional on funding: {float(pair[conditional_col]):.1%}',
                      f'  - Funded hard-breach rate (conditional on funding): {float(pair[breach_col]):.1%}',
                      f'  - Expected challenge starts per payout at this same book: {1.0 / float(pair[payout_col]):.2f}',
                      f'  - Expected failed evaluation accounts before payout: {max(0.0, 1.0 / float(pair[payout_col]) - 1.0 / float(pair[conditional_col])):.2f}',
                      f'  - Expected funded accounts per payout: {1.0 / float(pair[conditional_col]):.2f}',
                      f'  - Expected failed funded accounts before payout: {max(0.0, 1.0 / float(pair[conditional_col]) - 1.0):.2f}',
                      f'  - Approximate 90-trading-day funded survival: {float(pair["survival_90d_conditional_approx"]):.1%}',
                      f'  - Median trading days to evaluation pass: {float(pair["median_days_to_evaluation_pass"]):.1f}',
                      f'  - Median trading days to first payout: {float(pair["median_days_to_first_payout_from_start"]):.1f}',
                      f'  - Expected first net payout across all paths: USD {float(pair["first_payout_net_usd_mean"]):,.2f}',
                      f'  - Expected total net payout cash across all paths: USD {float(pair["total_net_payout_cash_mean"]):,.2f}',
                      f'  - Mean monthly strategy PnL before account rules: USD {float(pair["mean_monthly_strategy_pnl_usd"]):,.0f}',
                      f'  - P10 monthly strategy PnL before account rules: USD {float(pair["p10_monthly_strategy_pnl_usd"]):,.0f}',
                      f'  - P90 monthly peak-to-trough drawdown: USD {float(pair["p90_monthly_peak_to_trough_dd_usd"]):,.0f}',
                      "Monthly PnL and drawdown are strategy-stream estimates before account failures, DLL clipping, payout rules or withdrawal resets.",
                      "This is not the overall training-score winner. It is the top funded-score candidate within the eligible two-sleeve subset; its validation results are holdout estimates, not a basis for promoting it over the overall training-selected books."]
            append_risk_ladder("Two-sleeve alternative risk ladder", pair)

    if "Tradeify" in title:
        recovery_scope_note="Recovery outputs are balance-only. The $53,000 target is a balance threshold, not an approved payout; 35% consistency, five $150 winning days and payout processing are not enforced in the recovery path."
    else:
        recovery_scope_note="The5ers recovery is balance-only and targets return to the funded $20,000 initial balance above the static 4% loss floor; the 3% daily pause is modeled as a closed-PnL clip, and payout eligibility is not modeled in recovery paths."
    lines += ["","## Near-floor recovery",recovery_candidate,
              "",recovery_scope_note,
              "","These are simulated candidates, not live-deployment approvals. Use the full risk ladder and rule assumptions in the CSV/JSON reports."]
    (reports/"book_recommendations.md").write_text("\n".join(lines),encoding="utf-8")

def run_platform(platform):
    trades, pairing_quality = load_platform_trades(platform)
    # Freeze the R/$100 sizing proxy using training-period losses only.
    # Apply that fixed calibration to the later validation period.
    trades["risk_unit_full_sample"] = trades["risk_unit"]
    dates = pd.bdate_range(trades["exit_date"].min(), trades["exit_date"].max())
    cut = max(1, min(len(dates)-1, int(len(dates)*0.60)))
    train_end = dates[cut-1]
    for strategy, idx in trades.groupby("strategy").groups.items():
        train_trades = trades.loc[idx]
        train_trades = train_trades[train_trades["exit_date"] <= train_end]
        losses = train_trades["native_pnl"]
        losing = losses[losses < 0]
        unit = abs(float(losing.mean())) if len(losing) else float(losses.abs().median())
        if not np.isfinite(unit) or unit <= 0:
            unit = float(losses.abs().mean()) if len(losses) else 1.0
        if not np.isfinite(unit) or unit <= 0:
            unit = 1.0
        trades.loc[idx, "risk_unit"] = unit
        trades.loc[idx, "r_multiple"] = trades.loc[idx, "native_pnl"] / unit
        trades.loc[idx, "gross_r_multiple"] = trades.loc[idx, "gross_pnl"] / unit
        trades.loc[idx, "live_pnl"] = (trades.loc[idx, "r_multiple"] * 100.0
                                         if platform == "MT5" else trades.loc[idx, "native_pnl"])
        trades.loc[idx, "risk_unit_basis"] = (
            "training-sample mean absolute losing trade PnL per contract"
            if platform == "NT8" else
            "training-sample per-lot mean absolute losing trade PnL; $100 = 1R"
        )
    dates, rmat, gross_rmat, livemat, activemat = make_matrices(trades)
    combo_df, selected, train_idx, val_idx = build_books(rmat,activemat)
    if platform == "MT5":
        # The five Gold X9 exports are one EA at five TradeFrequency settings.
        # Screening them all would let the raw-score ranking shortlist a preset
        # (Very high) that the lot-floor execution study rejects on breach risk.
        # Keep only the standard preset in the prop ladder; the other presets
        # stay registered and appear in the per-sleeve and live reports.
        standard = "Gold X9 (Low)"
        def _keeps_standard(strategies):
            parts = [x.strip() for x in str(strategies).split(" | ")]
            return all((not x.startswith("Gold X9 (")) or x == standard for x in parts)
        combo_df = combo_df[combo_df["strategies"].map(_keeps_standard)].reset_index(drop=True)
        selected = {k: [c for c in v if _keeps_standard(" | ".join(c))]
                    for k, v in selected.items()}
    out = LIVE_ROOT / platform
    (out/"charts"/"individual").mkdir(parents=True,exist_ok=True)
    (out/"charts"/"portfolios").mkdir(parents=True,exist_ok=True)
    (out/"reports").mkdir(parents=True,exist_ok=True)

    strat_rows=[]
    curves={}
    for strategy in sorted(trades["strategy"].unique()):
        t=trades[trades["strategy"]==strategy]
        s=livemat[strategy]
        m=series_metrics(s)
        r=series_metrics(rmat[strategy])
        ms=microscalping_stats(t)
        strat_rows.append({
            "strategy":strategy,"platform":platform,"instrument":"; ".join(sorted(t["instrument"].dropna().astype(str).unique())),
            "trades":len(t),"first_trade":str(t["entry_timestamp"].min()),"last_trade":str(t["exit_timestamp"].max()),
            "mean_loss_risk_proxy":float(t["risk_unit"].iloc[0]),
            "mean_loss_risk_proxy_full_sample":float(t["risk_unit_full_sample"].iloc[0]),
            "risk_unit_basis":str(t["risk_unit_basis"].iloc[0]),
            "expectancy_R":float(t["r_multiple"].mean()),"win_rate":float((t["native_pnl"]>0).mean()),
            "duration_median_seconds":float(t["duration_seconds"].median()),
            "duration_coverage":ms["duration_coverage"],
            "trade_share_over_10s":ms["trade_share_over_10s"],"profit_share_over_10s":ms["profit_share_over_10s"],
            "live_net_pnl":m["net_pnl"],"live_annualized_pnl":m["annualized_pnl"],"live_max_drawdown":m["max_drawdown"],
            "live_daily_pf":m["daily_pf"],"live_daily_sharpe":m["daily_sharpe"],
            "risk_unit_net_R":r["net_pnl"],"risk_unit_maxdd_R":r["max_drawdown"],
            "positive_month_share":m["positive_month_share"],"positive_year_share":m["positive_year_share"],
            "worst_day_live":m["worst_day"],"best_day_share":m["best_day_share"],
        })
        plot_equity(s,f"{platform} | {strategy} | Normalized live",out/"charts"/"individual"/f"{slug(strategy)}.png",
                    "NT8: one contract equivalent. MT5: $100 per trade using mean-loss 1R proxy.")
        curves[strategy]=s

    pd.DataFrame(strat_rows).to_csv(out/"reports"/"strategy_metrics.csv",index=False)
    combo_df.to_csv(out/"reports"/"all_book_combinations.csv",index=False)

    # Live books use the requested operating units: 1 contract per NT8 sleeve,
    # $100 risk per MT5 sleeve. This is deliberately not equal-total-risk sizing.
    book_rows=[]
    all_names=list(rmat.columns)
    live_daily = livemat[all_names].sum(axis=1)
    plot_equity(live_daily,f"{platform} | All sleeves | Normalized live",out/"charts"/"portfolios"/"all_sleeves.png",
                "Unscaled sum: one NT8 contract per sleeve / $100 MT5 risk per sleeve.")
    curves["All sleeves"]=live_daily
    for cat, books in selected.items():
        for j,combo in enumerate(books,1):
            s=livemat[list(combo)].sum(axis=1)
            m=series_metrics(s)
            name=f"{cat.title()} book {j}: " + " + ".join(combo)
            book_rows.append({"category":cat,"rank":j,"book":" + ".join(combo),"size":len(combo),
                              "live_net_pnl":m["net_pnl"],"live_max_drawdown":m["max_drawdown"],
                              "live_daily_pf":m["daily_pf"],"live_daily_sharpe":m["daily_sharpe"],
                              "positive_month_share":m["positive_month_share"],"worst_day":m["worst_day"]})
            plot_equity(s,f"{platform} | {cat.title()} book {j}",out/"charts"/"portfolios"/f"{cat}_book_{j}.png",
                        "Live unit sizing; category selection is based on earlier training data.")
            curves[name]=s
    pd.DataFrame(book_rows).to_csv(out/"reports"/"category_book_metrics.csv",index=False)
    plot_dashboard(curves,f"{platform} | Normalized live equity curves",out/"charts"/"individual"/"strategy_dashboard.png")

    # Trade-level normalized ledger for audit/reproducibility.
    ledger=trades.copy()
    for c in ["entry_timestamp","exit_timestamp","entry_date","exit_date"]:
        ledger[c]=pd.to_datetime(ledger[c],errors="coerce").astype(str)
    ledger.to_csv(out/"reports"/"normalized_trade_ledger.csv",index=False)

    # Live block-bootstrap risk of ruin, expressed in R rather than a fictitious balance.
    mc_candidates={s:(s,) for s in all_names}
    for cat, books in selected.items():
        for j,combo in enumerate(books,1):
            mc_candidates[f"{cat}_book_{j}"]=combo
    mc_rows=[]
    val = val_idx if len(val_idx)>=60 else dates
    for name,combo in mc_candidates.items():
        series=rmat.loc[val,list(combo)].sum(axis=1)/len(combo)
        act=activemat.loc[val,list(combo)].any(axis=1)
        paths, actpaths=sample_block_paths(series.values,act.values,seed=SEED+len(mc_rows),date_index=val)
        mc_rows.append({"book":name,"strategies":" + ".join(combo),**live_bootstrap_summary(paths)})
    pd.DataFrame(mc_rows).to_csv(out/"reports"/"live_bootstrap_risk_of_ruin.csv",index=False)

    # Per-book account simulations use equal risk allocation across sleeves.
    prop_candidates={s:(s,) for s in all_names}
    for cat in ["challenge","funded","live","recovery"]:
        for j,combo in enumerate(selected.get(cat,[]),1):
            prop_candidates[f"{cat}_book_{j}"]=combo
    # Add leading two/three-sleeve combinations so prop selection is not
    # restricted to four-sleeve category books and single strategies.
    existing=set(tuple(v) for v in prop_candidates.values())
    for size in [2,3]:
        for score_col in ["challenge_score","funded_score"]:
            candidates=combo_df[combo_df["size"]==size].sort_values(score_col,ascending=False)
            added=0
            for _,rr in candidates.iterrows():
                combo=tuple(rr["strategies"].split(" | "))
                if combo in existing:
                    continue
                prop_candidates[f"{score_col}_{size}sleeve_candidate_{added+1}"]=combo
                existing.add(combo)
                added+=1
                if added==2:
                    break
    # MT5 Gold ORB (RBE) trade pairing uses FIFO fallback because the Deals
    # export lacks position IDs. Add leading RBE-excluded pairs/triples as a
    # sensitivity for The5ers book selection.
    if platform=="MT5":
        for size in [2,3]:
            for score_col in ["challenge_score","funded_score"]:
                no_rbe=combo_df[(combo_df["size"]==size) &
                                (~combo_df["strategies"].str.contains("Gold ORB (RBE)",regex=False))]
                no_rbe=no_rbe.sort_values(score_col,ascending=False)
                for _,rr in no_rbe.iterrows():
                    combo=tuple(rr["strategies"].split(" | "))
                    if combo not in existing:
                        prop_candidates[f"{score_col}_{size}sleeve_no_rbe"]=combo
                        existing.add(combo)
                        break
    # Add every screened one-to-four-sleeve combination. This gives each
    # possible book a full firm-specific Monte Carlo risk ladder, not just the
    # shortlisted candidates.
    for _, rr in combo_df.iterrows():
        combo=tuple(rr["strategies"].split(" | "))
        if combo not in existing:
            label=str(rr["book"])
            if label in prop_candidates:
                label=f"all_combo_{len(prop_candidates)+1:04d}"
            prop_candidates[label]=combo
            existing.add(combo)
    # Deduplicate identical strategy sets; keep the first category label.
    unique_candidates={}
    seen_combos=set()
    for cname,combo in prop_candidates.items():
        key=tuple(combo)
        if key not in seen_combos:
            unique_candidates[cname]=combo
            seen_combos.add(key)
    prop_candidates=unique_candidates
    train_score_map={}
    for _, rr in combo_df.iterrows():
        combo=tuple(rr["strategies"].split(" | "))
        train_score_map[combo]={
            "train_live_score":float(rr["live_score"]),
            "train_challenge_score":float(rr["challenge_score"]),
            "train_funded_score":float(rr["funded_score"]),
            "train_recovery_score":float(rr["recovery_score"]),
        }
    # Only screened books have cached scores. The standard-preset rule removes
    # the four non-standard X9 presets from combo_df, so their lone entries must
    # leave the prop ladder as well instead of raising a missing-score KeyError.
    prop_candidates={k:v for k,v in prop_candidates.items() if tuple(v) in train_score_map}
    validation_idx=val_idx if len(val_idx)>=60 else dates
    monthly_focus_combos = {
        tuple(combo)
        for category in ("challenge", "funded")
        for combo in selected.get(category, [])
    }
    # Also report the lower-risk Tradeify two-sleeve alternatives. The
    # monthly calculation is only run at the base risk, not for every
    # screened combination and every sensitivity point.
    if platform == "NT8":
        monthly_focus_combos.update(
            tuple(row["strategies"].split(" | "))
            for _, row in combo_df[combo_df["size"] == 2].iterrows()
        )
    the5ers_rows=[]; tradeify_rows=[]; moneta_rows=[]; recovery_rows=[]
    the5ers_dir=PROP_ROOT/"The5ers-20K-Bootcamp"
    tradeify_dir=PROP_ROOT/"Tradeify-50K-Growth-Futures"
    moneta_dir=PROP_ROOT/"Moneta-2Step-10K"
    for _ci,(cname,combo) in enumerate(prop_candidates.items(),1):
        if _ci % 100 == 0:
            print(f"[{platform}] {_ci}/{len(prop_candidates)} candidates", flush=True)
        score_meta=train_score_map[tuple(combo)]
        daily_r=rmat.loc[validation_idx,list(combo)].sum(axis=1)/len(combo)
        active=activemat.loc[validation_idx,list(combo)].any(axis=1)
        paths, actpaths=sample_block_paths(daily_r.values,active.values,seed=SEED+len(the5ers_rows)+100,date_index=validation_idx)
        if platform=="MT5":
            for risk in THE5ERS_RISKS:
                res=simulate_the5ers(paths,actpaths,risk)
                monthly = monthly_path_summary(paths, risk) if (
                    tuple(combo) in monthly_focus_combos and risk == 25.0
                ) else {}
                the5ers_rows.append({"book":cname,"strategies":" + ".join(combo),"risk_per_book_trade_usd":risk,
                                  **score_meta,**res,**monthly})
            for risk in MONETA_RISKS:
                res=simulate_moneta(paths,actpaths,risk)
                monthly = monthly_path_summary(paths, risk) if (
                    tuple(combo) in monthly_focus_combos and risk == 50.0
                ) else {}
                moneta_rows.append({"book":cname,"strategies":" + ".join(combo),"risk_per_book_trade_usd":risk,
                                    **score_meta,**res,**monthly})
        else:
            t=trades[trades["strategy"].isin(combo) &
                     trades["exit_date"].between(validation_idx.min(), validation_idx.max())]
            micro=microscalping_stats(t)
            week_ok=weekly_activity_ok(active)
            # Use common bootstrap blocks across the risk ladder for this book.
            # This removes avoidable Monte Carlo noise when comparing sizes.
            candidate_seed=SEED+300+sum(ord(ch) for ch in cname)
            validation_start = validation_idx.min()
            validation_end = validation_idx.max() + pd.Timedelta(days=1)
            validation_exposure_trades = trades[
                trades["strategy"].isin(combo)
                & (trades["entry_timestamp"] < validation_end)
                & (trades["exit_timestamp"] >= validation_start)
            ]
            for risk in TRADEIFY_RISKS:
                weights,sizes,exposure,scale,compliant=tradeify_position_weights(
                    trades,combo,risk,exposure_trades=validation_exposure_trades)
                effective=sum(weights.values())
                book_daily=weighted_daily_pnl(rmat,validation_idx,combo,weights)
                gross_book_daily=weighted_daily_pnl(gross_rmat,validation_idx,combo,weights)
                paired_daily=np.column_stack([book_daily.values,gross_book_daily.values])
                paired_paths,actpaths_t=sample_block_paths(
                    paired_daily,active.values,seed=candidate_seed,date_index=validation_idx)
                paths_t=paired_paths[:,:,0]
                consistency_paths_t=paired_paths[:,:,1]
                res=simulate_tradeify(paths_t,actpaths_t,1.0,micro["eligible"],week_ok,
                                      position_limit_compliant=compliant,
                                      consistency_paths=consistency_paths_t)
                monthly = monthly_path_summary(paths_t, 1.0) if (
                    tuple(combo) in monthly_focus_combos and risk == 100.0
                ) else {}
                extra={"book":cname,"strategies":" + ".join(combo),**score_meta,
                    "requested_risk_per_book_trade_usd":risk,"effective_risk_after_micro_sizing_usd":effective,
                    "microscalping_trade_share_over_10s":micro["trade_share_over_10s"],
                    "microscalping_profit_share_over_10s":micro["profit_share_over_10s"],
                    "microscalping_duration_coverage":micro["duration_coverage"],
                    "mini_equivalent_per_sleeve":json.dumps(sizes,sort_keys=True),
                    "max_concurrent_mini_equivalent":exposure,"position_limit_scale":scale,
                    "position_limit_compliant":compliant}
                res["position_limit_compliant"]=compliant
                tradeify_rows.append({**extra,**res,**monthly})

    # Recovery mode: compare low-complexity one/two-sleeve books with a no-trade
    # control. Tradeify uses at least one micro per sleeve. The5ers tests a small
    # continuous risk ladder because minimum CFD lot sizes are not enforced.
    singles = combo_df[combo_df["size"] == 1].sort_values("recovery_score",ascending=False)
    pairs = combo_df[combo_df["size"] == 2].sort_values("recovery_score",ascending=False)
    moneta_recovery_rows=[]
    recovery_books=[]
    # Recovery is a separate account state. Screen every positive-training
    # single sleeve and pair, not only the top generic recovery-score finalists.
    # This matters for Tradeify: a lower-risk single sleeve may satisfy weekly
    # activity even when the highest-scoring generic live sleeves do not.
    for source in [singles,pairs]:
        for _, rr in source.iterrows():
            combo=tuple(rr["strategies"].split(" | "))
            if (rr["train_net_R"] > 0 and rr["train_active_days"] >= 30
                    and combo not in recovery_books):
                recovery_books.append(combo)
    # Retain leading prop challenge/funded pairs as a cross-check.
    for cname, combo in prop_candidates.items():
        if len(combo)==2 and cname.startswith(("challenge_score","funded_score")) and combo not in recovery_books:
            recovery_books.append(combo)
    if platform=="MT5":
        for combo in recovery_books:
            weights={s:1.0/len(combo) for s in combo}
            recovery_daily=weighted_daily_pnl(rmat,validation_idx,combo,weights)
            rec_paths,rec_act=sample_block_paths(recovery_daily.values,
                activemat.loc[validation_idx,list(combo)].any(axis=1).values,
                n_sims=N_SIMS,horizon=HORIZON,seed=SEED+999+len(recovery_rows),
                date_index=validation_idx)
            for risk in [5.0,10.0,12.5,25.0]:
                for cushion in [100.0,250.0,500.0,750.0]:
                    res=simulate_recovery(rec_paths,risk,-800.0,cushion,0.0,daily_limit=600.0,daily_limit_mode="soft")
                    recovery_rows.append({"firm":"The5ers","book":" + ".join(combo),"risk_usd_per_book_trade":risk,
                        "state":"static-floor recovery to funded initial balance","floor_equity":-800.0,
                        "starting_cushion_usd":cushion,"target_equity":0.0,**res})
        for cushion in [100.0,250.0,500.0,750.0]:
            recovery_rows.append({"firm":"The5ers","book":"No trade","risk_usd_per_book_trade":0.0,
                "state":"no-trade control","floor_equity":-800.0,"starting_cushion_usd":cushion,
                "target_equity":0.0,"recovery_probability":0.0,"ruin_probability":0.0,
                "median_days_to_target":np.nan,"mean_terminal_equity":-800.0+cushion})
        # Moneta funded recovery: 8% static floor on $10k = USD 800, 4% daily = USD 400.
        for combo in recovery_books:
            weights={s:1.0/len(combo) for s in combo}
            recovery_daily=weighted_daily_pnl(rmat,validation_idx,combo,weights)
            rec_paths,rec_act=sample_block_paths(recovery_daily.values,
                activemat.loc[validation_idx,list(combo)].any(axis=1).values,
                n_sims=N_SIMS,horizon=HORIZON,seed=SEED+1999+len(moneta_recovery_rows),
                date_index=validation_idx)
            for risk in [12.5,25.0,50.0,100.0]:
                for cushion in [150.0,300.0,500.0,750.0]:
                    res=simulate_recovery(rec_paths,risk,-800.0,cushion,0.0,daily_limit=400.0,daily_limit_mode="hard")
                    moneta_recovery_rows.append({"firm":"Moneta","book":" + ".join(combo),
                        "risk_usd_per_book_trade":risk,
                        "state":"static-floor recovery to funded initial balance","floor_equity":-800.0,
                        "starting_cushion_usd":cushion,"target_equity":0.0,**res})
        for cushion in [150.0,300.0,500.0,750.0]:
            moneta_recovery_rows.append({"firm":"Moneta","book":"No trade","risk_usd_per_book_trade":0.0,
                "state":"no-trade control","floor_equity":-800.0,"starting_cushion_usd":cushion,
                "target_equity":0.0,"recovery_probability":0.0,"ruin_probability":0.0,
                "median_days_to_target":np.nan,"mean_terminal_equity":-800.0+cushion})
    else:
        for combo in recovery_books:
            weights={s:0.1*float(trades.loc[trades["strategy"]==s,"risk_unit"].iloc[0]) for s in combo}
            exposure=max_concurrent_mini_equiv(trades,combo,{s:0.1 for s in combo})
            recovery_daily=weighted_daily_pnl(rmat,validation_idx,combo,weights)
            rec_paths,rec_act=sample_block_paths(recovery_daily.values,
                activemat.loc[validation_idx,list(combo)].any(axis=1).values,
                n_sims=N_SIMS,horizon=HORIZON,seed=SEED+999+len(recovery_rows),
                date_index=validation_idx)
            rec_trades=trades[trades["strategy"].isin(combo) &
                              trades["exit_date"].between(validation_idx.min(),validation_idx.max())]
            rec_micro=microscalping_stats(rec_trades)
            rec_weekly=weekly_activity_ok(activemat.loc[validation_idx,list(combo)].any(axis=1))
            for cushion in [200.0,500.0,1000.0,1500.0]:
                for target in [600.0,3000.0]:
                    res=simulate_recovery(rec_paths,1.0,100.0,cushion,target,daily_limit=1250.0,daily_limit_mode="soft")
                    recovery_rows.append({"firm":"Tradeify","book":" + ".join(combo),
                        "risk_usd_per_book_trade":sum(weights.values()),"state":"post-lock recovery",
                        "mini_equivalent_exposure":exposure,"floor_equity":100.0,
                        "starting_cushion_usd":cushion,"target_equity":target,
                        "target_label":"$500 buffer above locked floor" if target==600.0 else "$53,000 balance target (payout eligibility not enforced)",
                        "weekly_activity_eligible":rec_weekly,
                        "microscalping_eligible":rec_micro["eligible"],
                        "microscalping_duration_coverage":rec_micro["duration_coverage"],
                        "payout_eligibility_enforced":False,**res})
        for cushion in [200.0,500.0,1000.0,1500.0]:
            for target in [600.0,3000.0]:
                recovery_rows.append({"firm":"Tradeify","book":"No trade","risk_usd_per_book_trade":0.0,
                    "state":"no-trade control","floor_equity":100.0,"starting_cushion_usd":cushion,
                    "target_equity":target,
                    "target_label":"$500 buffer above locked floor" if target==600.0 else "$53,000 balance target (payout eligibility not enforced)",
                    "weekly_activity_eligible":False,"microscalping_eligible":False,
                    "payout_eligibility_enforced":False,
                    "recovery_probability":float(100.0+cushion >= target),"ruin_probability":0.0,
                    "median_days_to_target":0.0 if 100.0+cushion >= target else np.nan,
                    "mean_terminal_equity":100.0+cushion})

    if platform=="MT5":
        (the5ers_dir/"reports").mkdir(parents=True,exist_ok=True)
        the5ers_df=pd.DataFrame(the5ers_rows)
        the5ers_recovery_df=pd.DataFrame(recovery_rows)
        the5ers_df.to_csv(the5ers_dir/"reports"/"monte_carlo_challenge_payout.csv",index=False)
        the5ers_recovery_df.to_csv(the5ers_dir/"reports"/"recovery_mode.csv",index=False)
        build_prop_outputs(the5ers_dir,the5ers_df,the5ers_recovery_df,
            "risk_per_book_trade_usd",25.0,"pass_both_phases_rate",
            "challenge_to_first_reward_rate","funded_hard_breach_rate_conditional","The5ers $20k Bootcamp",
            funded_pool=10)
        (moneta_dir/"reports").mkdir(parents=True,exist_ok=True)
        moneta_df=pd.DataFrame(moneta_rows)
        moneta_recovery_df=pd.DataFrame(moneta_recovery_rows)
        moneta_df.to_csv(moneta_dir/"reports"/"monte_carlo_challenge_payout.csv",index=False)
        moneta_recovery_df.to_csv(moneta_dir/"reports"/"recovery_mode.csv",index=False)
        build_prop_outputs(moneta_dir,moneta_df,moneta_recovery_df,
            "risk_per_book_trade_usd",50.0,"pass_both_phases_rate",
            "challenge_to_first_payout_rate","funded_hard_breach_rate_conditional",
            "Moneta Funded $10k 2-Step Standard",
            funded_pool=10)
    else:
        (tradeify_dir/"reports").mkdir(parents=True,exist_ok=True)
        tradeify_df=pd.DataFrame(tradeify_rows)
        tradeify_recovery_df=pd.DataFrame(recovery_rows)
        tradeify_df.to_csv(tradeify_dir/"reports"/"monte_carlo_evaluation_funded_payout.csv",index=False)
        tradeify_recovery_df.to_csv(tradeify_dir/"reports"/"recovery_mode.csv",index=False)
        build_prop_outputs(tradeify_dir,tradeify_df,tradeify_recovery_df,
            "requested_risk_per_book_trade_usd",100.0,"evaluation_pass_rate",
            "challenge_to_first_payout_rate","funded_hard_breach_rate_conditional",
            "Tradeify $50k Growth futures",
            eligibility_cols=["position_limit_compliant","microscalping_eligible","weekly_activity_eligible"],
            )

        # Intraday adverse-excursion diagnostic: one micro per sleeve (0.1 mini).
        # Sum of same-entry-day MAEs is a conservative stack, not a synchronized
        # tick-level equity path.
        mae_rows=[]
        for cname,combo in prop_candidates.items():
            daily_mae=pd.Series(0.0,index=validation_idx)
            total_trades=known_mae=0
            trade_maes=[]
            for strategy in combo:
                t=trades[trades["strategy"]==strategy].copy()
                total_trades += len(t)
                known_mae += int(t["mae"].notna().sum())
                scaled=t["mae"]*0.1
                trade_maes.extend(scaled.dropna().tolist())
                grouped=scaled.groupby(t["entry_date"]).sum(min_count=1)
                daily_mae=daily_mae.add(grouped.reindex(validation_idx,fill_value=0.0).fillna(0.0),fill_value=0.0)
            active_mae=daily_mae[daily_mae>0]
            mae_rows.append({
                "book":cname,"strategies":" + ".join(combo),"sleeves":len(combo),
                "sizing":"one micro per sleeve (0.1 mini equivalent)",
                "mae_trade_coverage":known_mae/total_trades if total_trades else 0.0,
                "mean_trade_mae_usd":float(np.mean(trade_maes)) if trade_maes else np.nan,
                "p95_trade_mae_usd":float(np.quantile(trade_maes,.95)) if trade_maes else np.nan,
                "max_trade_mae_usd":float(np.max(trade_maes)) if trade_maes else np.nan,
                "mean_daily_stacked_mae_usd":float(active_mae.mean()) if len(active_mae) else 0.0,
                "p95_daily_stacked_mae_usd":float(active_mae.quantile(.95)) if len(active_mae) else 0.0,
                "max_daily_stacked_mae_usd":float(active_mae.max()) if len(active_mae) else 0.0,
                "active_days_mae_over_1250_share":float((active_mae>1250).mean()) if len(active_mae) else 0.0,
                "active_days_mae_over_2000_share":float((active_mae>2000).mean()) if len(active_mae) else 0.0,
            })
        mae_df=pd.DataFrame(mae_rows)
        mae_df.to_csv(tradeify_dir/"reports"/"mae_soft_dll_stress.csv",index=False)
        top_mae=mae_df.sort_values("p95_daily_stacked_mae_usd",ascending=False).head(10)
        fig,ax=plt.subplots(figsize=(11,6))
        ax.barh(top_mae["book"],top_mae["p95_daily_stacked_mae_usd"])
        ax.axvline(1250,linestyle="--",linewidth=1,label="$1,250 initial daily loss limit")
        ax.axvline(2000,linestyle=":",linewidth=1,label="$2,000 DLL after $53k funded balance")
        ax.set_title("Tradeify | one-micro-per-sleeve p95 stacked MAE",loc="left",fontweight="bold")
        ax.set_xlabel("USD")
        ax.grid(True,axis="x",alpha=.25,linestyle="--")
        ax.legend(fontsize=8)
        fig.tight_layout()
        fig.savefig(tradeify_dir/"charts"/"mae_soft_dll_stress.png",dpi=160,bbox_inches="tight")
        plt.close(fig)

    # Cross-sleeve correlation on normalized daily R, never raw export dollar size.
    rmat.corr(min_periods=30).to_csv(out/"reports"/"risk_unit_correlation_matrix.csv")
    write_json(out/"reports"/"data_quality.json",{
        "platform":platform,"trade_count":int(len(trades)),"strategies":all_names,
        "source_timezone":"Preserved as exported; no conversion performed.",
        "mt5_pairing_quality":pairing_quality,
        "risk_unit":"Mean absolute realized losing-trade PnL calibrated on the first 60% training period, then held fixed for validation. NT8 is converted to one-contract PnL; MT5 cash flows are divided by traded volume to one-lot PnL before the loss unit is computed, which removes balance-based compounding in exports such as Gold X9. This is a reproducible loss-normalization proxy, not guaranteed to equal the strategy's initial stop risk.",
        "risk_unit_full_sample":"Also retained in the trade ledger for comparison; not used for validation sizing.",
        "mt5_standard_deals":"No position ID is present in the standard Deals tables. Entry/exit legs are paired by symbol and opposite side, exact volume match first, FIFO fallback; RBE has overlapping positions and residual pairing uncertainty.",
        "live_sizing":"NT8 = one contract equivalent per strategy. MT5 = $100 per trade at 1R based on the training-sample mean realized loss; that sizing is held fixed across the history.",
        "limitations":["Exported closed trades do not contain a complete intratrade equity path.",
                       "The5ers evaluation has no daily loss limit; the funded 3% daily pause is modeled as a closed-PnL clip, so intraday pause timing and overshoot are not reconstructed.",
                       "Tradeify EOD trailing drawdown is modeled from daily closes. The funded DLL is modeled at $1,250 initially and $2,000 from the next session after the $53,000 balance threshold; closed-PnL clipping is an approximation.",
                       "Tradeify session boundary and The5ers server reset are not timezone-normalized; account rule days use exported dates.",
                       "Tradeify weekly activity applies during evaluation and funded trading; microscalping is an additional funded payout-eligibility screen.",
                       "Tradeify position sizes use whole-micro increments, at least one micro per active sleeve, and a four-mini maximum concurrent exposure cap. Intraday soft-DLL trigger timing and overshoot remain unknown.",
                       "This is an export-based portfolio simulation, not an independent tick-level replay or live execution certification."]
    })
    return {"platform":platform,"strategies":len(all_names),"trades":len(trades),
            "selected_books":{k:[" + ".join(x) for x in v] for k,v in selected.items()},
            "validation_start":str(validation_idx.min().date()),"validation_end":str(validation_idx.max().date())}

def write_rule_docs():
    the5ers_rules={
        "account":"The5ers $20,000 Bootcamp (3-step evaluation, then funded)",
        "step_1_balance_usd":5000,"step_1_profit_target_usd":300,"step_1_max_loss_static_usd":250,
        "step_2_balance_usd":10000,"step_2_profit_target_usd":600,"step_2_max_loss_static_usd":500,
        "step_3_balance_usd":15000,"step_3_profit_target_usd":900,"step_3_max_loss_static_usd":750,
        "profit_target_pct_each_step":0.06,"max_loss_pct_each_step":0.05,
        "evaluation_daily_loss_limit":"None",
        "funded_balance_usd":20000,"funded_max_loss_pct":0.04,"funded_max_loss_static_usd":800,
        "funded_daily_pause_pct":0.03,"funded_daily_pause_usd":600,
        "funded_scale_target_pct":0.05,"funded_scale_target_usd":1000,
        "time_limit":"Unlimited","min_trading_days":"None listed",
        "inactivity_limit_days":30,
        "consistency_rule":"None for Bootcamp",
        "profit_split_start":0.50,"profit_split_max":1.00,
        "payout_cycle_calendar_days":14,"payout_cycle_model_trading_days":10,
        "payout_minimum_gross_usd":300,"payout_minimum_net_usd":150,
        "first_payout":"14 calendar days after the funded account is issued; model uses 10 trading days",
        "leverage":"1:30 FX; 1:25 metals and indices (Bootcamp page)",
        "news":"Allowed, except bracketing around releases",
        "overnight_and_weekend":"Allowed",
        "official_sources":["https://the5ers.com/bootcamp/","https://the5ers.com/challenge-programs-bootcamp-high-stakes-hyper-growth-explained/","https://www.pipster.io/research/firms/the5ers","https://propfirmly.com/prop-firm-challenges/the5ers-bootcamp-20k"],
        "rules_checked_date":"2026-11-22",
        "model_assumptions":["$10/$25/$50/$100 total book risk per trade sensitivity; base comparison $25",
                            "Each book divides risk equally across sleeves",
                            "Each evaluation step starts at its own fixed balance ($5k/$10k/$15k); phase profits are not carried",
                            "5% static max loss per step from that step's starting balance; 4% static funded floor at $19,200",
                            "No daily loss limit during evaluation; funded 3% daily pause modeled as a closed-PnL clip",
                            "Payout every 14 calendar days approximated as 10 trading days; 50% split; balance resets to $20,000 after withdrawal",
                            "A payout is only made when the profit reaches the USD 300 gross minimum (USD 150 to the trader); smaller gains carry forward",
                            "Funded 5% scale-up ladder (balance, max loss and split step-ups) is not modeled",
                            "Floating PnL is absent from the MT5 exports; the close-only model is optimistic for intraday breaches",
                            "Account fees are excluded from the payout estimates"]
    }
    tradeify_rules={
        "account":"Tradeify $50,000 Growth futures",
        "evaluation_profit_target_usd":3000,"evaluation_daily_loss_limit_usd":1250,
        "evaluation_trailing_drawdown_usd":2000,"evaluation_min_trading_days":1,
        "evaluation_consistency_base_case":"None (dedicated Growth account guide)",
        "funded_daily_loss_limit_usd":1250,
        "funded_daily_loss_limit_after_6pct_usd":2000,
        "funded_dll_increase_balance_usd":53000,
        "funded_dll_increase_timing":"Next trading session after reaching 6% profit",
        "funded_trailing_drawdown_usd":2000,"funded_drawdown_lock_balance_usd":52100,
        "funded_locked_floor_usd":50100,"payout_min_balance_usd":53000,
        "funded_drawdown_measurement":"End-of-day trailing until floor locks at $50,100",
        "daily_loss_measurement":"Real-time equity soft pause; simulation clips closed daily PnL at -$1,250 initially and -$2,000 from the next session after balance reaches $53,000. Intraday trigger timing and overshoot are unknown.",
        "payout_consistency":0.35,"payout_profitable_days":5,"payout_day_profit_minimum_usd":150,
        "profit_split":0.90,"payout_minimum_usd":500,"payout_caps_usd":[1500,2000,2500,3000],
        "payout_processing_model_trading_days":2,
        "max_position_size":"4 minis / 40 micros","position_scaling":"No scaling restrictions; full maximum position size available from day one",
        "minimum_activity":"At least 1 trade per week (Monday-Friday); applies to both evaluation and funded accounts",
        "no_hedging_correlated_products":True,"overnight_positions":"Must be flat by daily cutoff",
        "microscalping":"More than 50% of trades and more than 50% of profit from trades longer than 10 seconds",
        "daily_close":"4:45 PM ET regular days; 12:59 PM ET early-close days",
        "news":"Allowed; slippage risk remains",
        "official_sources":["https://help.tradeify.co/en/articles/10495915-growth-evaluation-accounts","https://help.tradeify.co/en/articles/12268167-essential-trading-rules-overview","https://help.tradeify.co/en/articles/10468321-rules-daily-loss-limit","https://help.tradeify.co/en/articles/10468320-rules-consistency-rule","https://help.tradeify.co/en/articles/11083796-growth-funded-account-payout-policy","https://help.tradeify.co/en/articles/10495897-rules-trailing-max-drawdowns"],
        "rules_checked_date":"2026-11-01",
        "model_assumptions":["$100/$250/$500/$750 requested total book risk per trade sensitivity",
                            "Minimum 1 micro per active sleeve; whole-micro sizing rounded down above the minimum",
                            "Each book divides risk equally across sleeves",
                            "Payout processing approximated as 2 trading days; balance must remain at or above $53,000",
                            "Four-mini exposure cap enforced after whole-micro sizing; any remaining noncompliant sizing is flagged",
                            "Current non-legacy Growth evaluation rules apply (accounts purchased on/after September 12, 2025); older legacy accounts require a separate rule model",
                            "Growth evaluation has no consistency rule; funded payout requires 35% consistency, five days above $150 and the $53,000 balance threshold",
                            "At least one trade per complete Monday-Friday week applies during evaluation and funded trading; the model checks complete historical weeks and uses week-aligned bootstrap blocks",
                            "Evaluation pass rate requires weekly activity and position-limit compliance; microscalping is an additional funded payout-eligibility check",
                            "Funded DLL rises from $1,250 to $2,000 from the next session after the $53,000 balance threshold; the model assumes the higher DLL remains after payouts",
                            "Closed-PnL clipping is an approximation and does not reconstruct intraday trigger timing or overshoot",
                            "EOD drawdown updates modeled; real-time floating breaches not fully reconstructable"]
    }
    moneta_rules={
        "account":"Moneta Funded $10,000 2-Step Standard Evaluation",
        "account_size_usd":10000,
        "phase_1_profit_target_pct":0.05,"phase_1_profit_target_usd":500,
        "phase_2_profit_target_pct":0.10,"phase_2_profit_target_usd":1000,
        "daily_loss_pct":0.04,"daily_loss_usd":400,
        "daily_loss_pct_wider_option":0.05,"daily_loss_usd_wider_option":500,
        "max_loss_pct_static":0.08,"max_loss_usd":800,
        "max_loss_pct_static_wider_option":0.10,"max_loss_usd_wider_option":1000,
        "max_loss_measurement":"Static, measured from the account starting balance; not trailing",
        "daily_loss_measurement":"Balance/equity loss within one trading day; a breach fails the account (not a pause)",
        "min_profitable_days":"3 per phase and 3 per payout cycle",
        "profit_day_minimum_pct":0.005,"profit_day_minimum_usd":50,
        "consistency_rule":"None (Phase 1, Phase 2 and funded payouts)",
        "profit_split":0.88,
        "payout_cycle_calendar_days":14,"payout_cycle_model_trading_days":10,
        "payout_minimum_usd":0.0,
        "news_restriction":"No new or held exposure from 5 minutes before to 5 minutes after high-impact releases; applies to evaluation and funded. A position opened at least 2 hours before the event may be closed inside the window.",
        "hedging":"Cross-account hedging prohibited; incidental opposing positions from independent strategies or EAs on the same account are permitted (support clarification 2026-11-21)",
        "overnight_and_weekend":"Allowed",
        "eas":"Own self-developed EAs allowed; grid, news bracketing, HFT/latency and artificial risk offsetting prohibited",
        "vps_and_ip":"Terms restrict multi-IP access; keep the access setup consistent. Not a rule the model can evaluate.",
        "time_limit":"None listed",
        "official_sources":["Moneta Funded support clarification to the account holder, 2026-11-21","Moneta Funded website, Client Dashboard, Help Center/FAQ and Terms & Conditions (authoritative)"],
        "rules_checked_date":"2026-11-23",
        "model_assumptions":["USD 12.50/$25/$50/$75/$100 total book risk per trade sensitivity; base comparison USD 50",
                            "Each book divides risk equally across sleeves",
                            "Phase 1 and Phase 2 each start at the full account balance; phase profits are not carried",
                            "4% daily loss and 8% static maximum loss modeled (the wider 5%/10% option is larger, so results are the conservative case)",
                            "Three profitable days of at least 0.5% net are required before a phase or a payout cycle can complete",
                            "Payout every 14 calendar days approximated as 10 trading days; 88% split; balance resets to the account size after withdrawal",
                            "No minimum payout amount is published; any positive cycle profit that meets the three-day condition is paid",
                            "Floating PnL is absent from the MT5 exports; the close-only model is optimistic for intraday breaches",
                            "The 5-minute news window around high-impact releases is not modeled",
                            "Account fees are excluded from the payout estimates"]
    }
    write_json(PROP_ROOT/"The5ers-20K-Bootcamp"/"reports"/"account_rules.json",the5ers_rules)
    write_json(PROP_ROOT/"Moneta-2Step-10K"/"reports"/"account_rules.json",moneta_rules)
    write_json(PROP_ROOT/"Tradeify-50K-Growth-Futures"/"reports"/"account_rules.json",tradeify_rules)

def write_readmes(summaries):
    LIVE_ROOT.mkdir(exist_ok=True)
    (LIVE_ROOT/"README.md").write_text("""# Normalized live-account research

This directory removes the exported starting balances and normalizes strategy exposure.

- NT8: one contract equivalent per strategy. Trade PnL is divided by exported quantity.
- MT5: fixed $100 risk per trade. Every trade's cash flow is divided by its traded volume first, so 1R is a per-lot realized-loss proxy rather than a balance-scaled dollar amount. That keeps compounding tester runs (Gold X9 grows from ~0.09 to 50+ lots) comparable with fixed-size runs. The export does not provide a complete per-trade initial-stop risk series, so this is explicitly a realized-loss proxy.
- Equity starts at $0. No account balance is added.
- The strategy's native exits and stop behavior are preserved. No protective stops or strategy redesign are introduced.

Each platform has individual strategy curves, all-sleeve curves, category-book curves, normalized trade ledgers, risk-unit correlations, and bootstrap drawdown/ruin estimates. The live book categories are screening candidates, not deployment approval.

## Platform reports

- [NT8 normalized live](NT8/README.md)
- [MT5 normalized live](MT5/README.md)

## Charts

See the platform READMEs for the equity curves at the end of each report.
""",encoding="utf-8")

    (PROP_ROOT/"README.md").write_text("""# Prop-firm portfolio simulations

Separate account-rule simulations using normalized strategy R-multiples and block-bootstrap Monte Carlo.

- [The5ers $20,000 Bootcamp](The5ers-20K-Bootcamp/README.md)
- [Moneta Funded $10,000 2-Step Standard](Moneta-2Step-10K/README.md)
- [Tradeify $50,000 Growth futures](Tradeify-50K-Growth-Futures/README.md)

Results are conditional on historical export distributions and the assumptions in each account folder. They are not guarantees of passing, funding, payout or survival.
""",encoding="utf-8")

    for platform in ["NT8","MT5"]:
        p=LIVE_ROOT/platform
        metric_path=p/"reports"/"strategy_metrics.csv"
        strategy_names=pd.read_csv(metric_path)["strategy"].tolist() if metric_path.exists() else []
        book_path=p/"reports"/"category_book_metrics.csv"
        books=pd.read_csv(book_path) if book_path.exists() else pd.DataFrame()
        individual_links="\n".join([f"![{x}](charts/individual/{slug(x)}.png)" for x in strategy_names])
        combined_links="\n".join([
            f"![{row.category.title()} book {int(row.rank)}](charts/portfolios/{row.category}_book_{int(row.rank)}.png)"
            for row in books.itertuples()
        ])
        (p/"README.md").write_text(f"""# {platform} normalized live research

- [Strategy metrics](reports/strategy_metrics.csv)
- [All book combinations](reports/all_book_combinations.csv)
- [Category book metrics](reports/category_book_metrics.csv)
- [Risk-unit correlation](reports/risk_unit_correlation_matrix.csv)
- [Bootstrap risk of ruin](reports/live_bootstrap_risk_of_ruin.csv)
- [Normalized trade ledger](reports/normalized_trade_ledger.csv)

## Equity curves

### Individual sleeves

{individual_links}

### Combined books

![All sleeves](charts/portfolios/all_sleeves.png)

{combined_links}
""",encoding="utf-8")

    for firm, title, file in [
        ("The5ers-20K-Bootcamp","The5ers $20,000 Bootcamp","monte_carlo_challenge_payout.csv"),
        ("Moneta-2Step-10K","Moneta Funded $10,000 2-Step Standard","monte_carlo_challenge_payout.csv"),
        ("Tradeify-50K-Growth-Futures","Tradeify $50,000 Growth futures","monte_carlo_evaluation_funded_payout.csv"),
    ]:
        d=PROP_ROOT/firm
        # Only advertise the recovery chart when the simulation produced one.
        recovery_chart = ("![Recovery probability](charts/recovery_probability.png)\n\n"
                          if (d/"charts"/"recovery_probability.png").exists() else "")
        extra_links = "- [Book rankings](reports/book_rankings.csv)\n- [Book recommendations](reports/book_recommendations.md)\n- [Recovery-mode scenarios](reports/recovery_mode.csv)"
        if firm.startswith("The5ers"):
            extra_links += (chr(10) + "- [Stage sizing with real lot floors](reports/stage_sizing.md)"
                            + chr(10) + "- [Stage sizing data](reports/stage_sizing.csv)")
        if firm.startswith("Moneta"):
            extra_links += (chr(10) + "- [Stage sizing with real lot floors](reports/stage_sizing.md)"
                            + chr(10) + "- [Stage sizing data](reports/stage_sizing.csv)"
                            + chr(10) + "- [Pre-configured EA set files](../../../set-files/Moneta-2Step-10K/README.md)")
        chart_extra = ""
        if firm=="Tradeify-50K-Growth-Futures":
            extra_links += "\n- [Intraday MAE / soft-DLL stress](reports/mae_soft_dll_stress.csv)"
            extra_links += (chr(10) + "- [Stage sizing in whole contracts](reports/stage_sizing.md)"
                            + chr(10) + "- [Stage sizing data](reports/stage_sizing.csv)")
            sizing_note = "Growth evaluation has no consistency rule. At least one trade per complete Monday-Friday week is required during evaluation and funded trading. Funded payouts require 35% consistency, five winning days above $150, a $53,000 balance and the microscalping test. Whole-micro sizing uses at least one micro per active sleeve and a four-mini concurrent cap; effective risk after minimum sizing is shown."
            sizing_note += (" One micro per sleeve is already about 1% of the $50k account and roughly 4R from the "
                              "$2,000 trail, so size is set by the broker minimum and the drawdown, not by the "
                              "four-mini cap. [Stage sizing in whole contracts](reports/stage_sizing.md) enumerates "
                              "the allocations.")
            daily_limit_note = "The initial $1,250 soft daily-loss limit is modeled as a closed-PnL clip; after the funded balance reaches $53,000, the model applies the official $2,000 DLL from the next session. Intraday trigger timing, overshoot and trade sequence remain unknown. The EOD trailing drawdown is modeled from daily closes; NT8 MAE is a separate diagnostic."
            pairing_note = "NT8 MAE stacks same-entry-day adverse excursions across active sleeves; it is not a synchronized intraday equity replay."
            recovery_note = "Recovery curves are balance-only. The $53,000 target does not enforce payout consistency, five $150 winning days or payout processing."
            chart_extra = "\n![Evaluation drawdown breach probability](charts/evaluation_breach_probability.png)\n![Intraday MAE / soft-DLL stress](charts/mae_soft_dll_stress.png)\n![Recovery to $53,000 balance (payout eligibility not enforced)](charts/recovery_payout_threshold_probability.png)\n"
        elif firm.startswith("Moneta"):
            sizing_note = ("Risk ladder is USD 12.50–100 total book risk per trade, allocated equally across sleeves. "
                "Phase 1 needs +5% and Phase 2 needs +10%, so the ladder is a continuous-sizing idealization; "
                "[stage sizing with real lot floors](reports/stage_sizing.md) resizes every sleeve to a dollar "
                "target in whole 0.01 lots and models the funded switch. Phase 2 is the binding constraint: the "
                "10% target at 4% daily and 8% static maximum loss is a much shorter fuse than a 5% one-step "
                "evaluation.")
            daily_limit_note = "The 4% daily limit is modeled as a hard breach (Moneta fails the account rather than pausing), with an 8% static maximum loss measured from the starting balance. The wider 5%/10% drawdown option is strictly larger, so these results are the conservative case. Intraday trigger timing, floating-loss breaches and the 5-minute news window around high-impact releases are not visible in the exports."
            pairing_note = "MT5 RBE entry/exit legs use exact-volume matching where possible and FIFO fallback because the Deals export has no position IDs."
            recovery_note = "Recovery curves are balance-only; Moneta recovery measures return to the $10,000 funded initial balance above the static 8% floor (USD 800), not payout eligibility."
        else:
            sizing_note = ("Risk ladder is USD 10–100 total book risk per trade, allocated equally across sleeves. "
                "That ladder is a continuous-sizing idealization: it does not enforce broker minimum lots. "
                "At 0.01 lot Gold X9 (Low) already risks about USD 9.90 per trade (0.20% of the $5k Step 1), so the real "
                "stage risk is set by that floor, not by the ladder. [Stage sizing with real lot floors]"
                "(reports/stage_sizing.md) models the book with minimum-lot floors, the mid-account switch to the "
                "funded book, and per-sleeve percent sizing; [underlying CSV](reports/stage_sizing.csv). "
                "MT5 cash flows are divided by traded volume before the R unit is calibrated, so balance-compounding "
                "exports (Gold X9, Tokyo Coil) enter at per-lot risk.")
            daily_limit_note = "Evaluation has no daily loss limit, so only the 5% static per-step maximum loss can fail a step. The funded account adds a 3% daily pause, modeled as a closed-PnL clip: intraday trigger timing and overshoot are not visible in the exports, and the 5% funded scale-up ladder is not modeled."
            pairing_note = "MT5 RBE entry/exit legs use exact-volume matching where possible and FIFO fallback because the Deals export has no position IDs."
            recovery_note = "Recovery curves are balance-only; The5ers recovery measures return to the funded $20,000 initial balance above the static 4% floor, not payout eligibility."
        (d/"README.md").write_text(f"""# {title}

- [Account rules and assumptions](reports/account_rules.json)
- [Monte Carlo results](reports/{file})
- [Methodology](../methodology.md)
{extra_links}

The model uses normalized daily R-multiples and a 5-trading-day block bootstrap aligned to complete Monday-Friday weeks. Each simulation uses {N_SIMS:,} paths over {HORIZON} trading days. {sizing_note}

## Important limits

- The source exports are closed-trade records, not a complete tick-by-tick account equity path.
- {daily_limit_note}
- {pairing_note}
- Timestamps remain as exported. The firm's timezone/session boundaries are not reconstructed.
- Strategy execution, native exits and stop behavior are not changed.
- {recovery_note}
- Treat results as historical scenario estimates, not promises.

## Charts

![Challenge-to-payout probability](charts/challenge_to_payout_probability.png)

![Drawdown breach probability](charts/drawdown_breach_probability.png)

{recovery_chart}{chart_extra}
""",encoding="utf-8")

def main():
    summaries=[]
    for platform in ["NT8","MT5"]:
        summaries.append(run_platform(platform))
    write_rule_docs()
    write_readmes(summaries)
    write_json(PROP_ROOT/"reports"/"build_summary.json",{
        "generated_utc":datetime.now(timezone.utc).isoformat(),
        "monte_carlo_simulations_per_candidate":N_SIMS,
        "horizon_trading_days":HORIZON,"block_length_days":BLOCK,
        "platforms":summaries,
        "global_limitations":["No tick-level replay was run.","All 10 NT8 and 19 MT5 exports are included (Gold X9 is registered at five mutually exclusive TradeFrequency presets); MT5 cash flows are normalized to per-lot PnL before risk-unit calibration.",
                             "Risk units use mean realized loss, not necessarily the initial stop risk.",
                             "Prop firm rule boundaries are approximated from exported timestamps."]
    })
    print(json.dumps(summaries,indent=2))

if __name__=="__main__":
    main()
