# TokyoCoil

## Deployable files

Recompilation requires exactly `TokyoCoil.mq5` and `StrategyEngine.mqh`, `ExecutionRuntime.mqh`, `ChartVisuals.mqh`, all in this folder. Platform trade-library code is embedded locally; no custom or standard include file outside this root is needed. No external visual/ADX EX5 is required. Once compiled, the EA EX5 runs alone.

Layout matches VaultBreak/VWAPPullback/OBRB: the `.mq5` is only a compile entry point; `StrategyEngine.mqh` owns inputs, shared model state, signals and lifecycle orchestration (including the embedded platform trade SDK); `ExecutionRuntime.mqh` owns sizing, broker execution and owned recovery; `ChartVisuals.mqh` owns chart replay/drawing and the panel. All three headers are root-local. News and clock helpers are embedded into these modules; no separate helper header is needed.

MT5 native file APIs cannot write into the Experts source folder. Generated file logs and optional historical-news CSVs therefore use the terminal Common/Files sandbox, with flat strategy-specific names; terminal GlobalVariables retain recovery state. These platform data stores are the unavoidable exception to source-root placement. No DLL filesystem workaround is introduced.

Historical-news files: `Common/Files/TokyoCoil_<CalendarFile>` and its `.coverage.csv` sidecar. Default: `TokyoCoil_asiancoil_usd_events.csv`. This replaces the former `TokyoCoil/calendar` subfolder. News OFF requires neither file.

Use **TokyoCoil.ex5** in MT5 Strategy Tester. Its defaults are the frozen model:
C1, appendix entries/median, 1% source risk, 20-trade brake at −4R or worse, news
OFF, no trailing/BE, IC NY-close clock, NY DST conversion, panel and ranges ON.
No preset is required. The news lead remains configurable and defaults to five
minutes if news is enabled. Historical calendar files/coverage are required
only for tester runs with news enabled; live news uses Forex Factory directly.

Inputs use numbered sections with blank separators. The panel fits its longest
row, uses the chart's symbol, and has one NY date plus a smaller server clock.
Ranges and execution drawings retain only today’s NY session and the previous
two. See docs/VISUALS_AND_DEPLOYMENT.md and results/visuals-scroll-preview.png.

Live/VPS deployment needs only **TokyoCoil.ex5**, including when news is enabled.
MQH code is compiled into it. Live news needs internet access and the MT5
WebRequest allowlist entry `https://nfs.faireconomy.media`; no calendar/cache
file is required, and no shared feed or shared cache is used.

For recompilation, copy these four files directly into the strategy root:
TokyoCoil.mq5, StrategyEngine.mqh, ChartVisuals.mqh and ExecutionRuntime.mqh.
StrategyEngine.mqh bundles the existing MetaQuotes trade library with its original
copyright notices. All source includes resolve inside this root; there are no
parent-folder, subfolder or external standard-library source dependencies.
An isolated compilation containing only these four source files passed with
zero errors/warnings. Historical tester news remains an optional, separate
dataset under Common/Files/TokyoCoil/calendar with audited coverage.

The brake now supports tester and live hedging accounts. It reconstructs owned
trade risk from opening deals / order history on restart and refuses to assume
full risk if history cannot be reconstructed. No live-money run was performed;
the completed research does not establish production readiness. There is no
fully validated TokyoCoil NT8 strategy yet. The three-file port candidate is in
Documents/NinjaTrader 8/bin/Custom/Strategies/TokyoCoil_NT. It exposes only used controls and
use the same frozen defaults, with broker-specific spot/futures sizing.

UseBrake is the existing ON/OFF toggle. Halve at the inclusive threshold
last20 price-R <= -4; recover above it. RiskMoney >0 selects fixed cash risk
(e.g. 500 becomes 250 under the brake); RiskMoney=0 uses RiskPct of balance.
R uses each trade's initial risk, including half-risk trades. The panel shows
the applied percentage after the brake. Live trade logs append to an account
specific filename; large research quote tapes are written only in the tester.

The 31-cell BE/trailing screen and native BE2 checks are complete. BE2 reduced
development intraday drawdown but increased it in retrospective confirmation;
it failed the protection gate. Original exits remain the frozen defaults.
See docs/EXIT_EXTENSION.md for the results and limits.

Removed from the active input list: C3 enable/magic and the discarded median /
raw-edge comparison switches. Their constants retain source parity internally.
Clock controls are internal, with automatic selection for verified broker
conventions. Unknown tester clocks fail safely. Optional news controls remain.

- `docs/`: frozen decision, final report and Growth 6J SOP.
- `results/`: trade/excursion CSVs and detailed research JSON evidence.
- `validation/`: reproducible analysis/build/test helpers and default smoke test.
- `calendar/`: optional-news fixtures and coverage data.
- `archive/`: original PDF appendix source, discarded builds, old presets/logs,
  historical comparison evidence and document rendering QA.

The Growth SOP is research-only. Its 21-session payout estimates are for a
fresh funded account, not the joint probability of passing then being paid.
No dependable minimum payout, waiting time or live account recommendation is
supported. USDJPY spot on a suitable separate FX connection is another route.

Old evidence-manifest paths reflect the pre-cleanup layout. Files were moved,
not discarded. Ordered large tapes remain in MT5 Common/Files.

## Recovery

2026-10-23 request-boundary safeguards: every embedded trade request checks a durable account/server/symbol/magic broker-restriction marker. A liquidation-only, close-only or disabled-server rejection pauses further requests across restart and retains broker protection. Reconnection alone does not clear a broker permission restriction. The EA reports the broker response; account permission recovery needs separate verification.

Close/stop requests require exact position identifier, verified opening magic/symbol and matching remaining entry/exit volume. Close intent is flushed before submission; pending and ambiguous acknowledgements block duplicate closes. Exact owned close history can hydrate a lost acknowledgement. A native exclusive executor lock prevents duplicate charts from managing the same strategy identity. Native terminal GlobalVariables and flat Common/Files lock storage are platform-managed exceptions to source-root packaging; the compiled EX5 still runs alone.

Proof: `3. TokyoCoil/validation/test_request_boundary.py` from the Experts root executes the production ownership, restriction and close-settlement predicates for both families. Both EAs compiled with zero errors/warnings. Source fixtures and compilation do not establish VPS/broker restart acceptance.

The EA keeps a disappeared position's saved identifier until exact-symbol/position opening ownership and complete entry/exit volume are available from broker history. Empty, entry-only and partial exit snapshots retry through the normal driver. Broker/manual exit deals may use another magic; ownership is established by the exact position's opening deals. Netting reversal/mixed opening ownership does not qualify.

This prevents zero-price exits, fabricated R and premature ownership clearing. Existing stop restoration/close-intent handling remains in the EA. Runtime deployment requires only the rebuilt `TokyoCoil.ex5`; source rebuild dependencies remain local to this strategy root.

Proof: `validation/test_exit_hydration.py` executes the actual reconciliation function; MetaEditor native compilation is separate from broker/VPS disconnect/restart acceptance. See `../CODING_RECOVERY.md` for the coding contract.
