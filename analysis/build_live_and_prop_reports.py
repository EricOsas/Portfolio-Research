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
LIVE_ROOT = ROOT / "Normalized-Live"
PROP_ROOT = ROOT / "Prop-Firms"
N_SIMS = 5000
HORIZON = 252
BLOCK = 5
SEED = 20261101
FTMO_RISKS = [25.0, 50.0, 75.0, 100.0]
TRADEIFY_RISKS = [100.0, 250.0, 500.0, 750.0]

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
    path = ROOT / platform / "reports" / "normalized_event_ledger.csv"
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
            out.loc[idx, "risk_unit_basis"] = "mean absolute losing trade PnL proxy; $100 = 1R"
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
    rmat, livemat, activemat = {}, {}, {}
    for s in strategies:
        t = trades[trades["strategy"] == s]
        rmat[s] = daily_series(t, "r_multiple", dates)
        livemat[s] = daily_series(t, "live_pnl", dates)
        a = t.groupby("entry_date").size()
        activemat[s] = a.reindex(dates, fill_value=0).gt(0)
    return dates, pd.DataFrame(rmat, index=dates), pd.DataFrame(livemat, index=dates), pd.DataFrame(activemat, index=dates)

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

def sample_block_paths(values, active, n_sims=N_SIMS, horizon=HORIZON, block=BLOCK, seed=SEED):
    values = np.asarray(values, dtype=float)
    active = np.asarray(active, dtype=bool)
    if len(values) == 0:
        raise ValueError("No daily observations for bootstrap.")
    rng = np.random.default_rng(seed)
    block = max(1, min(block, len(values)))
    nblocks = int(math.ceil(horizon / block))
    starts = rng.integers(0, len(values), size=(n_sims, nblocks))
    offsets = np.arange(block)
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

def simulate_ftmo(paths, active, risk):
    n, h = paths.shape
    phase = np.ones(n, dtype=np.int8)  # 1=Challenge, 2=Verification, 3=Funded, 4=Failed
    eq = np.zeros(n)
    active_days = np.zeros(n, dtype=int)
    p1_day = np.full(n, -1, dtype=int)
    p2_day = np.full(n, -1, dtype=int)
    funded_age = np.zeros(n, dtype=int)
    first_funded_trade_day = np.full(n, -1, dtype=int)
    reward_request_day = np.full(n, -1, dtype=int)
    reward_request_amount = np.zeros(n)
    reward_day = np.full(n, -1, dtype=int)
    reward = np.zeros(n)
    fail_daily = np.zeros(n, dtype=bool)
    fail_max = np.zeros(n, dtype=bool)
    fail_daily_challenge = np.zeros(n, dtype=bool)
    fail_max_challenge = np.zeros(n, dtype=bool)
    fail_daily_verification = np.zeros(n, dtype=bool)
    fail_max_verification = np.zeros(n, dtype=bool)
    fail_daily_funded = np.zeros(n, dtype=bool)
    fail_max_funded = np.zeros(n, dtype=bool)

    for d in range(h):
        start_phase = phase.copy()
        daily = paths[:, d] * risk
        act = active[:, d]

        eval_mask = (start_phase == 1) | (start_phase == 2)
        if eval_mask.any():
            eq[eval_mask] += daily[eval_mask]
            active_days[eval_mask] += act[eval_mask].astype(int)
            daily_bad = eval_mask & (daily < -500.0)
            max_bad = eval_mask & (eq <= -1000.0)
            challenge_mask = start_phase == 1
            verification_mask = start_phase == 2
            fail_daily |= daily_bad
            fail_max |= max_bad
            fail_daily_challenge |= daily_bad & challenge_mask
            fail_max_challenge |= max_bad & challenge_mask
            fail_daily_verification |= daily_bad & verification_mask
            fail_max_verification |= max_bad & verification_mask
            phase[daily_bad | max_bad] = 4

            p1 = (start_phase == 1) & (phase != 4) & (eq >= 1000.0) & (active_days >= 4)
            if p1.any():
                p1_day[p1] = d
                phase[p1] = 2
                eq[p1] = 0.0
                active_days[p1] = 0

            p2 = (start_phase == 2) & (phase != 4) & (eq >= 500.0) & (active_days >= 4)
            if p2.any():
                p2_day[p2] = d
                phase[p2] = 3
                eq[p2] = 0.0
                active_days[p2] = 0
                funded_age[p2] = 0
                first_funded_trade_day[p2] = -1

        funded_mask = (start_phase == 3) & (phase == 3)
        if funded_mask.any():
            eq[funded_mask] += daily[funded_mask]
            first_trade = funded_mask & act & (first_funded_trade_day < 0)
            first_funded_trade_day[first_trade] = d
            has_first_trade = funded_mask & (first_funded_trade_day >= 0)
            funded_age[has_first_trade] = d - first_funded_trade_day[has_first_trade] + 1

            daily_bad = funded_mask & (daily < -500.0)
            max_bad = funded_mask & (eq <= -1000.0)
            fail_daily |= daily_bad
            fail_max |= max_bad
            fail_daily_funded |= daily_bad
            fail_max_funded |= max_bad
            phase[daily_bad | max_bad] = 4

            # Reward request is available after 10 trading days from the first
            # funded trade (approximation of FTMO's 14 calendar days). Count it
            # only if four-business-day processing fits inside the horizon.
            claim = (funded_mask & (phase == 3) & (funded_age >= 10) &
                     (eq >= 20.0) & (reward_request_day < 0) & ((d + 4) < h))
            if claim.any():
                reward_request_day[claim] = d
                reward_request_amount[claim] = 0.80 * eq[claim]

        # Reward is approved only if the funded account remains active through
        # the modeled four-business-day processing period.
        pending_reward = ((reward_request_day >= 0) & (reward_day < 0) &
                          (d >= reward_request_day + 4))
        approved = pending_reward & (phase == 3)
        if approved.any():
            reward_day[approved] = d
            reward[approved] = reward_request_amount[approved]

    reached_funded = p2_day >= 0
    first_payout = reward_day >= 0
    funded_hard_breach = fail_daily_funded | fail_max_funded
    return {
        "pass_phase1_rate": float((p1_day >= 0).mean()),
        "pass_verification_conditional_rate": float((p2_day >= 0).sum() / max(1, (p1_day >= 0).sum())),
        "pass_both_phases_rate": float(reached_funded.mean()),
        "funded_first_reward_rate_conditional": float(first_payout[reached_funded].mean()) if reached_funded.any() else 0.0,
        "challenge_to_first_reward_rate": float(first_payout.mean()),
        "fail_daily_loss_rate": float(fail_daily.mean()),
        "fail_max_loss_rate": float(fail_max.mean()),
        "challenge_daily_loss_breach_rate": float(fail_daily_challenge.mean()),
        "challenge_max_loss_breach_rate": float(fail_max_challenge.mean()),
        "verification_daily_loss_breach_rate": float(fail_daily_verification.mean()),
        "verification_max_loss_breach_rate": float(fail_max_verification.mean()),
        "funded_daily_loss_breach_rate_conditional": float(fail_daily_funded[reached_funded].mean()) if reached_funded.any() else 0.0,
        "funded_max_loss_breach_rate_conditional": float(fail_max_funded[reached_funded].mean()) if reached_funded.any() else 0.0,
        "funded_hard_breach_rate_conditional": float(funded_hard_breach[reached_funded].mean()) if reached_funded.any() else 0.0,
        "median_days_to_phase1": float(np.median(p1_day[p1_day >= 0]) + 1) if (p1_day >= 0).any() else np.nan,
        "median_days_to_phase2": float(np.median(p2_day[p2_day >= 0]) + 1) if reached_funded.any() else np.nan,
        "median_days_to_first_reward_from_start": float(np.median(reward_day[first_payout]) + 1) if first_payout.any() else np.nan,
        "expected_first_reward_usd": float(reward.mean()),
        "median_first_reward_usd_conditional": float(np.median(reward[first_payout])) if first_payout.any() else 0.0,
        "simulations": int(n), "horizon_trading_days": int(h),
        "note": "Daily closed-PnL model; $20 minimum closed profit assumed for bank transfer; four-business-day review/processing approximation; reward is counted only if the account remains funded through approval; floating-loss breaches are not visible in exports.",
    }

def simulate_tradeify(paths, active, risk, microscalp_ok, weekly_activity_ok):
    n, h = paths.shape
    phase = np.zeros(n, dtype=np.int8)  # 0=Evaluation, 1=Funded, 2=Failed
    eval_eq = np.zeros(n); eval_hwm = np.zeros(n); eval_floor = np.full(n,-2000.0)
    funded_eq = np.zeros(n); funded_hwm = np.zeros(n); funded_floor = np.full(n,-2000.0)
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
        # Growth DLL is a soft stop, not a hard account failure. With only
        # completed-trade daily PnL available, approximate the stop by clipping
        # the day's closed loss at the $1,250 DLL. Intraday overshoot is unknown.
        daily = np.maximum(raw_daily, -1250.0)
        act = active[:,d]

        ev = start_phase == 0
        if ev.any():
            eval_eq[ev] += daily[ev]
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
            funded_eq[fu] += daily[fu]
            funded_age[fu] += 1
            dll_hits[fu & (raw_daily <= -1250.0)] += 1
            cycle_profit[fu] += daily[fu]
            best_cycle_day[fu] = np.maximum(best_cycle_day[fu], daily[fu])
            win_days[fu] += (daily[fu] > 150.0).astype(int)

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
            if not microscalp_ok or not weekly_activity_ok:
                payout_ok[:] = False
            cap_idx = np.minimum(payout_count,3)
            caps = np.array([1500.0,2000.0,2500.0,3000.0])
            cap = caps[cap_idx]
            available = np.maximum(0.0, funded_eq - funded_floor)
            amount = np.minimum(cap, available)
            request = no_pending & payout_ok & (amount >= 500.0)
            pending_amount[request] = amount[request]
            pending_days[request] = 2

    reached_funded = eval_pass_day >= 0
    first_payout = first_payout_day >= 0
    survived_90 = []
    for i in np.where(reached_funded)[0]:
        pass_day = eval_pass_day[i]
        end_day = pass_day + 90
        if end_day < h:
            survived_90.append(fail_funded_day[i] < 0 or fail_funded_day[i] > end_day)
    return {
        "evaluation_pass_rate": float(reached_funded.mean()),
        "funded_first_payout_rate_conditional": float(first_payout[reached_funded].mean()) if reached_funded.any() else 0.0,
        "challenge_to_first_payout_rate": float(first_payout.mean()),
        "funded_hard_breach_rate": float(fail_funded.mean()),
        "funded_hard_breach_rate_conditional": float(fail_funded[reached_funded].mean()) if reached_funded.any() else 0.0,
        "evaluation_hard_breach_rate": float(fail_eval.mean()),
        "evaluation_soft_dll_hit_days_mean": float(eval_dll_hits.mean()),
        "daily_loss_soft_breach_days_mean": float(dll_hits.mean()),
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
        "note": "EOD trailing updates are modeled. Growth soft DLL is approximated by clipping each closed-PnL daily loss at -$1,250; intraday trigger timing, overshoot, floating equity and slippage are not reconstructable from closed-trade exports.",
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
    weekly = active.astype(int).resample("W-FRI").sum()
    weekly = weekly[weekly.index <= active.index.max()]
    return bool(len(weekly) and (weekly > 0).all())

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

def tradeify_position_weights(trades, combo, requested_total_risk):
    """One micro minimum, whole-micro sizing, four-mini account cap."""
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
            t = trades[trades["strategy"] == strategy]
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
                       eligibility_cols=None, stress_filter=None):
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
    if base.empty:
        base=df[df[risk_col].astype(float).eq(float(base_risk))].copy()
    conditional_col=("funded_first_payout_rate_conditional" if "funded_first_payout_rate_conditional" in base.columns
                     else "funded_first_reward_rate_conditional")
    ranking=base.sort_values(payout_col,ascending=False).copy()
    ranking["funded_score"]=ranking[conditional_col].astype(float)*(1.0-ranking[breach_col].astype(float)) if conditional_col in ranking.columns else 0.0
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
        rec=recovery_df[recovery_df["book"]!="No trade"].copy()
        if not rec.empty:
            chosen=rec.sort_values("recovery_probability",ascending=False).iloc[0]["book"]
            g=rec[rec["book"]==chosen]
            fig,ax=plt.subplots(figsize=(10.5,5.8))
            for label,part in g.groupby(target_col):
                part=part.sort_values("starting_cushion_usd")
                ax.plot(part["starting_cushion_usd"],part["recovery_probability"],marker="o",label=str(label))
            ax.set_title(f"{title}: recovery probability | {chosen}",loc="left",fontweight="bold")
            ax.set_xlabel("Starting cushion above breach floor (USD)")
            ax.set_ylabel("Probability of reaching target")
            ax.set_ylim(0,1)
            ax.grid(True,alpha=.25,linestyle="--")
            ax.legend(fontsize=7,loc="best")
            fig.tight_layout()
            fig.savefig(charts/"recovery_probability.png",dpi=160,bbox_inches="tight")
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
    funded=base.assign(funded_score=base[conditional_col].astype(float)*(1.0-base[breach_col].astype(float))).sort_values("funded_score",ascending=False).iloc[0] if len(base) and conditional_col in base.columns else challenge
    recovery_candidate="No active book met the near-floor recovery threshold; preserve the account rather than force trades."
    if not recovery_df.empty:
        near_cushion=100.0 if "FTMO" in title else 200.0
        target_rows=recovery_df[recovery_df["starting_cushion_usd"].astype(float).eq(near_cushion)]
        if "target_label" in target_rows.columns:
            target_rows=target_rows[target_rows["target_label"].astype(str).str.contains("break-even|buffer",case=False,regex=True)]
        viable=target_rows[(target_rows["book"]!="No trade") & (target_rows["ruin_probability"].astype(float)<=0.05) & (target_rows["recovery_probability"].astype(float)>=0.50)]
        if len(viable):
            best=viable.sort_values("recovery_probability",ascending=False).iloc[0]
            recovery_candidate=f'{best["book"]}: recovery probability {best["recovery_probability"]:.1%}, breach probability {best["ruin_probability"]:.1%}.'
        else:
            recovery_candidate="No-trade is the safest near-floor control; none of the active candidates stayed within a 5% modeled breach probability."

    lines=[f"# {title} — book ranking",
           "",
           f"Base comparison risk: USD {base_risk:,.0f} requested total risk per book trade.",
           "",
           "## Challenge candidate"]
    if challenge is not None:
        lines += [f'- **{challenge["book"]}** ({challenge["strategies"]})',
                  f'  - Challenge-to-payout: {float(challenge[payout_col]):.1%}',
                  f'  - Pass rate: {float(challenge[pass_col]):.1%}',
                  f'  - Breach rate: {float(challenge[breach_col]):.1%}']
    lines += ["","## Funded candidate"]
    if funded is not None:
        lines += [f'- **{funded["book"]}** ({funded["strategies"]})',
                  f'  - Conditional first-payout rate: {float(funded[conditional_col]):.1%}' if conditional_col in funded else "  - Conditional first-payout rate: unavailable",
                  f'  - Breach rate: {float(funded[breach_col]):.1%}']
    lines += ["","## Near-floor recovery",recovery_candidate,
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
        trades.loc[idx, "live_pnl"] = (trades.loc[idx, "r_multiple"] * 100.0
                                         if platform == "MT5" else trades.loc[idx, "native_pnl"])
        trades.loc[idx, "risk_unit_basis"] = (
            "training-sample mean absolute losing trade PnL per contract"
            if platform == "NT8" else
            "training-sample mean absolute losing trade PnL proxy; $100 = 1R"
        )
    dates, rmat, livemat, activemat = make_matrices(trades)
    combo_df, selected, train_idx, val_idx = build_books(rmat,activemat)
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
        paths, actpaths=sample_block_paths(series.values,act.values,seed=SEED+len(mc_rows))
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
    # Deduplicate identical strategy sets; keep the first category label.
    unique_candidates={}
    seen_combos=set()
    for cname,combo in prop_candidates.items():
        key=tuple(combo)
        if key not in seen_combos:
            unique_candidates[cname]=combo
            seen_combos.add(key)
    prop_candidates=unique_candidates
    validation_idx=val_idx if len(val_idx)>=60 else dates
    ftmo_rows=[]; tradeify_rows=[]; recovery_rows=[]
    ftmo_dir=PROP_ROOT/"FTMO-10K-2Step-CFD"
    tradeify_dir=PROP_ROOT/"Tradeify-50K-Growth-Futures"
    for cname,combo in prop_candidates.items():
        daily_r=rmat.loc[validation_idx,list(combo)].sum(axis=1)/len(combo)
        active=activemat.loc[validation_idx,list(combo)].any(axis=1)
        paths, actpaths=sample_block_paths(daily_r.values,active.values,seed=SEED+len(ftmo_rows)+100)
        if platform=="MT5":
            for risk in FTMO_RISKS:
                res=simulate_ftmo(paths,actpaths,risk)
                ftmo_rows.append({"book":cname,"strategies":" + ".join(combo),"risk_per_book_trade_usd":risk,**res})
        else:
            t=trades[trades["strategy"].isin(combo) &
                     trades["exit_date"].between(validation_idx.min(), validation_idx.max())]
            micro=microscalping_stats(t)
            week_ok=weekly_activity_ok(active)
            for risk in TRADEIFY_RISKS:
                weights,sizes,exposure,scale,compliant=tradeify_position_weights(trades,combo,risk)
                effective=sum(weights.values())
                book_daily=weighted_daily_pnl(rmat,validation_idx,combo,weights)
                paths_t,actpaths_t=sample_block_paths(book_daily.values,active.values,seed=SEED+len(tradeify_rows)+300)
                res=simulate_tradeify(paths_t,actpaths_t,1.0,micro["eligible"],week_ok)
                extra={"book":cname,"strategies":" + ".join(combo),
                    "requested_risk_per_book_trade_usd":risk,"effective_risk_after_micro_sizing_usd":effective,
                    "microscalping_trade_share_over_10s":micro["trade_share_over_10s"],
                    "microscalping_profit_share_over_10s":micro["profit_share_over_10s"],
                    "microscalping_duration_coverage":micro["duration_coverage"],
                    "mini_equivalent_per_sleeve":json.dumps(sizes,sort_keys=True),
                    "max_concurrent_mini_equivalent":exposure,"position_limit_scale":scale,
                    "position_limit_compliant":compliant}
                res["position_limit_compliant"]=compliant
                tradeify_rows.append({**extra,**res})

    # Recovery mode: compare low-complexity one/two-sleeve books with a no-trade
    # control. Tradeify uses at least one micro per sleeve; FTMO uses $12.50 risk
    # per book as a conservative recovery setting.
    singles = combo_df[combo_df["size"] == 1].sort_values("recovery_score",ascending=False)
    pairs = combo_df[combo_df["size"] == 2].sort_values("recovery_score",ascending=False)
    recovery_books=[]
    for source, limit in [(singles,3),(pairs,3)]:
        added=0
        for _, rr in source.iterrows():
            combo=tuple(rr["strategies"].split(" | "))
            if rr["train_net_R"] > 0 and combo not in recovery_books:
                recovery_books.append(combo)
                added += 1
            if added==limit: break
    if platform=="MT5":
        for combo in recovery_books:
            weights={s:12.5/len(combo) for s in combo}
            recovery_daily=weighted_daily_pnl(rmat,validation_idx,combo,weights)
            rec_paths,rec_act=sample_block_paths(recovery_daily.values,
                activemat.loc[validation_idx,list(combo)].any(axis=1).values,
                n_sims=N_SIMS,horizon=HORIZON,seed=SEED+999+len(recovery_rows))
            for cushion in [100.0,250.0,500.0,750.0]:
                res=simulate_recovery(rec_paths,1.0,-1000.0,cushion,0.0,daily_limit=500.0)
                recovery_rows.append({"firm":"FTMO","book":" + ".join(combo),"risk_usd_per_book_trade":12.5,
                    "state":"static-floor recovery to initial balance","floor_equity":-1000.0,
                    "starting_cushion_usd":cushion,"target_equity":0.0,**res})
        for cushion in [100.0,250.0,500.0,750.0]:
            recovery_rows.append({"firm":"FTMO","book":"No trade","risk_usd_per_book_trade":0.0,
                "state":"no-trade control","floor_equity":-1000.0,"starting_cushion_usd":cushion,
                "target_equity":0.0,"recovery_probability":0.0,"ruin_probability":0.0,
                "median_days_to_target":np.nan,"mean_terminal_equity":-1000.0+cushion})
    else:
        for combo in recovery_books:
            weights={s:0.1*float(trades.loc[trades["strategy"]==s,"risk_unit"].iloc[0]) for s in combo}
            exposure=max_concurrent_mini_equiv(trades,combo,{s:0.1 for s in combo})
            recovery_daily=weighted_daily_pnl(rmat,validation_idx,combo,weights)
            rec_paths,rec_act=sample_block_paths(recovery_daily.values,
                activemat.loc[validation_idx,list(combo)].any(axis=1).values,
                n_sims=N_SIMS,horizon=HORIZON,seed=SEED+999+len(recovery_rows))
            for cushion in [200.0,500.0,1000.0,1500.0]:
                for target in [600.0,3000.0]:
                    res=simulate_recovery(rec_paths,1.0,100.0,cushion,target,daily_limit=1250.0,daily_limit_mode="soft")
                    recovery_rows.append({"firm":"Tradeify","book":" + ".join(combo),
                        "risk_usd_per_book_trade":sum(weights.values()),"state":"post-lock recovery",
                        "mini_equivalent_exposure":exposure,"floor_equity":100.0,
                        "starting_cushion_usd":cushion,"target_equity":target,
                        "target_label":"$500 buffer above locked floor" if target==600.0 else "$53,000 first-payout balance",**res})
        for cushion in [200.0,500.0,1000.0,1500.0]:
            for target in [600.0,3000.0]:
                recovery_rows.append({"firm":"Tradeify","book":"No trade","risk_usd_per_book_trade":0.0,
                    "state":"no-trade control","floor_equity":100.0,"starting_cushion_usd":cushion,
                    "target_equity":target,
                    "target_label":"$500 buffer above locked floor" if target==600.0 else "$53,000 first-payout balance",
                    "recovery_probability":float(100.0+cushion >= target),"ruin_probability":0.0,
                    "median_days_to_target":0.0 if 100.0+cushion >= target else np.nan,
                    "mean_terminal_equity":100.0+cushion})

    if platform=="MT5":
        (ftmo_dir/"reports").mkdir(parents=True,exist_ok=True)
        ftmo_df=pd.DataFrame(ftmo_rows)
        ftmo_recovery_df=pd.DataFrame(recovery_rows)
        ftmo_df.to_csv(ftmo_dir/"reports"/"monte_carlo_challenge_payout.csv",index=False)
        ftmo_recovery_df.to_csv(ftmo_dir/"reports"/"recovery_mode.csv",index=False)
        build_prop_outputs(ftmo_dir,ftmo_df,ftmo_recovery_df,
            "risk_per_book_trade_usd",50.0,"pass_both_phases_rate",
            "challenge_to_first_reward_rate","funded_hard_breach_rate_conditional","FTMO $10k 2-Step CFD")
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
        ax.axvline(1250,linestyle="--",linewidth=1,label="$1,250 daily loss limit")
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
        "risk_unit":"Mean absolute realized losing-trade PnL calibrated on the first 60% training period, then held fixed for validation. NT8 is first converted to one-contract PnL; MT5 uses exported position-level PnL. This is a reproducible loss-normalization proxy, not guaranteed to equal the strategy's initial stop risk.",
        "risk_unit_full_sample":"Also retained in the trade ledger for comparison; not used for validation sizing.",
        "mt5_standard_deals":"No position ID is present in the standard Deals tables. Entry/exit legs are paired by symbol and opposite side, exact volume match first, FIFO fallback; RBE has overlapping positions and residual pairing uncertainty.",
        "live_sizing":"NT8 = one contract equivalent per strategy. MT5 = $100 per trade at 1R based on the training-sample mean realized loss; that sizing is held fixed across the history.",
        "limitations":["Exported closed trades do not contain a complete intratrade equity path.",
                       "FTMO daily/max loss is equity-based; MT5 simulations use closed-PnL paths and are optimistic for floating-loss breaches.",
                       "Tradeify EOD trailing drawdown is modeled from daily closes. The $1,250 soft DLL is approximated by clipping closed daily losses; NT8 MAE is a separate stress diagnostic.",
                       "Tradeify session boundary and FTMO server reset are not timezone-normalized; account rule days use exported dates.",
                       "Tradeify position sizes use whole-micro increments, at least one micro per active sleeve, and a four-mini maximum concurrent exposure cap. Soft DLL losses are clipped at $1,250/day in Monte Carlo.",
                       "This is an export-based portfolio simulation, not an independent tick-level replay or live execution certification."]
    })
    return {"platform":platform,"strategies":len(all_names),"trades":len(trades),
            "selected_books":{k:[" + ".join(x) for x in v] for k,v in selected.items()},
            "validation_start":str(validation_idx.min().date()),"validation_end":str(validation_idx.max().date())}

def write_rule_docs():
    ftmo_rules={
        "account":"FTMO $10,000 2-Step CFD; Standard assumed",
        "phase_1_profit_target_usd":1000,"verification_profit_target_usd":500,
        "max_daily_loss_usd":500,"max_loss_static_usd":1000,
        "daily_loss_basis":"Equity-based; daily limit resets at 00:00 CE(S)T from that day's starting balance",
        "maximum_loss_basis":"Static 10% of initial simulated capital",
        "min_trading_days_each_phase":4,"time_limit":"Unlimited",
        "consistency_rule":"None for 2-Step; FTMO Best Day Rule applies to 1-Step only",
        "funded_reward_split_default":0.80,"first_reward_request":"Day 14 or later after first funded trade; model uses 10 trading days",
        "minimum_closed_profit_usd_bank_transfer":20,"minimum_closed_profit_usd_crypto":50,
        "reward_processing_model_business_days":4,
        "daily_reset":"00:00 CE(S)T; based on current-day 00:00 balance",
        "official_sources":["https://ftmo.com/en/trading-objectives/","https://ftmo.com/en/2-step-challenge/","https://ftmo.com/en/faq/how-do-i-withdraw-my-profits/","https://ftmo.com/en/faq/can-i-trade-news/","https://ftmo.com/en/faq/do-i-have-to-close-my-positions-overnight-or-before-the-weekend/"],
        "rules_checked_date":"2026-11-01",
        "news":"Standard funded account: selected events have a 2-minute pre/post execution restriction; not applicable during evaluation",
        "model_assumptions":["$25/$50/$75/$100 total book risk per trade sensitivity",
                            "Each book divides risk equally across sleeves",
                            "10 trading days used as an approximation for the 14-calendar-day first reward request date",
                            "No intraday floating PnL in MT5 exports; close-only rule model is optimistic"]
    }
    tradeify_rules={
        "account":"Tradeify $50,000 Growth futures",
        "evaluation_profit_target_usd":3000,"evaluation_daily_loss_limit_usd":1250,
        "evaluation_trailing_drawdown_usd":2000,"evaluation_min_trading_days":1,
        "evaluation_consistency_base_case":"None (dedicated Growth account guide)",
        "funded_daily_loss_limit_usd":1250,
        "funded_trailing_drawdown_usd":2000,"funded_drawdown_lock_balance_usd":52100,
        "funded_locked_floor_usd":50100,"payout_min_balance_usd":53000,
        "funded_drawdown_measurement":"End-of-day trailing until floor locks at $50,100",
        "daily_loss_measurement":"Real-time equity soft pause; simulation clips closed daily PnL at -$1,250 as an approximation. Intraday overshoot is unknown.",
        "payout_consistency":0.35,"payout_profitable_days":5,"payout_day_profit_minimum_usd":150,
        "profit_split":0.90,"payout_minimum_usd":500,"payout_caps_usd":[1500,2000,2500,3000],
        "payout_processing_model_trading_days":2,
        "max_position_size":"4 minis / 40 micros","position_scaling":"No scaling restrictions; full maximum position size available from day one",
        "minimum_activity":"At least 1 trade per week (Monday-Friday)",
        "no_hedging_correlated_products":True,"overnight_positions":"Must be flat by daily cutoff",
        "microscalping":"More than 50% of trades and more than 50% of profit from trades longer than 10 seconds",
        "daily_close":"4:45 PM ET regular days; 12:59 PM ET early-close days",
        "news":"Allowed; slippage risk remains",
        "official_sources":["https://help.tradeify.co/en/articles/10495915-growth-evaluation-accounts","https://help.tradeify.co/en/articles/12268167-essential-trading-rules-overview","https://help.tradeify.co/en/articles/10468320-rules-consistency-rule","https://help.tradeify.co/en/articles/11083796-growth-funded-account-payout-policy","https://help.tradeify.co/en/articles/10495897-rules-trailing-max-drawdowns"],
        "rules_checked_date":"2026-11-01",
        "model_assumptions":["$100/$250/$500/$750 requested total book risk per trade sensitivity",
                            "Minimum 1 micro per active sleeve; whole-micro sizing rounded down above the minimum",
                            "Each book divides risk equally across sleeves",
                            "Payout processing approximated as 2 trading days; balance must remain at or above $53,000",
                            "Four-mini exposure cap enforced after whole-micro sizing; any remaining noncompliant sizing is flagged",
                            "Growth evaluation has no consistency rule; funded payout requires 35% consistency and five days above $150",
                            "Soft DLL is approximated by clipping closed daily PnL losses at -$1,250; intraday overshoot is unknown",
                            "EOD drawdown updates modeled; real-time floating breaches not fully reconstructable"]
    }
    write_json(PROP_ROOT/"FTMO-10K-2Step-CFD"/"reports"/"account_rules.json",ftmo_rules)
    write_json(PROP_ROOT/"Tradeify-50K-Growth-Futures"/"reports"/"account_rules.json",tradeify_rules)

def write_readmes(summaries):
    LIVE_ROOT.mkdir(exist_ok=True)
    (LIVE_ROOT/"README.md").write_text("""# Normalized live-account research

This directory removes the exported starting balances and normalizes strategy exposure.

- NT8: one contract equivalent per strategy. Trade PnL is divided by exported quantity.
- MT5: fixed $100 risk per trade. 1R is proxied by each strategy's mean absolute realized losing-trade PnL. The export does not provide a complete per-trade initial-stop risk series, so this is explicitly a realized-loss proxy.
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

- [FTMO $10,000 2-Step CFD](FTMO-10K-2Step-CFD/README.md)
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
        ("FTMO-10K-2Step-CFD","FTMO $10,000 2-Step CFD","monte_carlo_challenge_payout.csv"),
        ("Tradeify-50K-Growth-Futures","Tradeify $50,000 Growth futures","monte_carlo_evaluation_funded_payout.csv"),
    ]:
        d=PROP_ROOT/firm
        extra_links = "- [Book rankings](reports/book_rankings.csv)\n- [Book recommendations](reports/book_recommendations.md)\n- [Recovery-mode scenarios](reports/recovery_mode.csv)"
        chart_extra = ""
        if firm=="Tradeify-50K-Growth-Futures":
            extra_links += "\n- [Intraday MAE / soft-DLL stress](reports/mae_soft_dll_stress.csv)"
            sizing_note = "Growth evaluation has no consistency rule; funded payouts require 35% consistency and five winning days above $150. Whole-micro sizing uses at least one micro per active sleeve and a four-mini concurrent cap; full size is available from day one. Effective risk after minimum sizing is shown in the results."
            daily_limit_note = "Tradeify EOD trailing drawdown is modeled from daily closes. The $1,250 soft daily-loss limit is approximated by clipping closed daily losses at -$1,250; intraday trigger timing and overshoot remain unknown. NT8 MAE is a separate diagnostic."
            pairing_note = "NT8 MAE is available for the separate soft-DLL stress diagnostic."
            chart_extra = "\n![Evaluation drawdown breach probability](charts/evaluation_breach_probability.png)\n![Intraday MAE / soft-DLL stress](charts/mae_soft_dll_stress.png)\n"
        else:
            sizing_note = "Risk ladder is USD 25–100 total book risk per trade, allocated equally across sleeves. Sizing is continuous; instrument-specific minimum lots are not enforced."
            daily_limit_note = "FTMO equity-based daily and maximum loss limits can be breached by floating losses not visible in closed-trade exports."
            pairing_note = "MT5 RBE entry/exit legs use exact-volume matching where possible and FIFO fallback because the Deals export has no position IDs."
        (d/"README.md").write_text(f"""# {title}

- [Account rules and assumptions](reports/account_rules.json)
- [Monte Carlo results](reports/{file})
- [Methodology](../methodology.md)
{extra_links}

The model uses normalized daily R-multiples and a 5-trading-day circular block bootstrap. Each simulation uses {N_SIMS:,} paths over {HORIZON} trading days. {sizing_note}

## Important limits

- The source exports are closed-trade records, not a complete tick-by-tick account equity path.
- {daily_limit_note}
- {pairing_note}
- Timestamps remain as exported. The firm's timezone/session boundaries are not reconstructed.
- Strategy execution, native exits and stop behavior are not changed.
- Treat results as historical scenario estimates, not promises.

## Charts

![Challenge-to-payout probability](charts/challenge_to_payout_probability.png)

![Drawdown breach probability](charts/drawdown_breach_probability.png)

![Recovery probability](charts/recovery_probability.png)

{chart_extra}
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
        "global_limitations":["No tick-level replay was run.","MT5 RBE is now included; Gold X9 remains missing.",
                             "Risk units use mean realized loss, not necessarily the initial stop risk.",
                             "Prop firm rule boundaries are approximated from exported timestamps."]
    })
    print(json.dumps(summaries,indent=2))

if __name__=="__main__":
    main()
