# Vault Break validation

Current sources: `../VaultBreakNT8.cs`; model and inputs: `../MODEL.md`; active deterministic checks: `../tests/`.

## Current repair — 2026-10-08

- ETH M1 uses the selected chart/Analyzer date range, without the former 60,000-bar cap. Provider availability and the model's ATR/session warmup still apply. Load at least 45 calendar days before the period you intend to compare, allowing more for sparse history; filter the export to the comparison period. This is a data-loading correction, not a change to trading rules.
- Ownership ID 91008010 is internal. Existing default state/order naming remains compatible. One Vault instance is supported per account/instrument; do not use old nondefault-ID state to recover exposure without reconciliation. Foreign positions/orders remain untouched.
- The supplied 2026 CSV is preserved. `VAULT_MT5_COMPARISON.md` compares it with saved frozen MT5 evidence and records the incompatible settings and coverage. No new 2026 backtest or tuning was performed.
- Focused model, sizing, ownership, exposure, source-recovery and visual checks are under tests. Current compilation receipt is `BUILD_RECEIPT.txt`.

Old repair notes, large native logs and superseded compile receipts were preserved outside the NinjaTrader compile tree at `C:/Users/Administrator/Documents/StrategyValidationArchive/2026-10-08/VaultBreak_NT`. The archive's SHA-256 manifest records retained files. Historical receipts describe their original source revisions and are not current certification.

Native Analyzer confirmation after reloading the corrected build, matched MT5/NT8 source/settings reconciliation, chart/reconnect and broker lifecycle testing remain separate gates. Test success does not establish profitability or live readiness.

## NNQ execution context repair — 2026-10-09

The NNQ chart's panel could report `Signals NQ | Orders NQ` during an NQ-source callback. Runtime reads of the unqualified callback Instrument also affected point value, tick rounding, commission scope, exposure keys and exact-instrument foreign-order checks. Execution metadata now always comes from the primary order contract, while native orders continue to use the configured execution series. The routing validation checks that NNQ's execution series matches that primary contract. The panel shows separate contracts only when a fallback actually splits signal and execution sources.

`tests/test_execution_context.py` executes production rounding, cash-cost and commission-scope helpers with different NQ/NNQ specifications and primary/source/execution callbacks. The old source failed the NNQ-rounding assertion; corrected sources pass independently for each model. Static checks cover exposure/ownership contract reads and execution-series submissions. Prior NNQ sizing/results must be revalidated; this test is not a broker fill or VPS runtime test. Native NQ/MNQ sources retain the same order-contract specifications.
