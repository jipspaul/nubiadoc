# Brief Coverage Self-Audit (Phase 2.5)

Scope of this spec set: **Bug Family 1 only** (concurrent-401 refresh-lock). Families 2 and 3 are explicitly deferred — rationale below — so this audit reports them as *out-of-scope-by-decision*, not as gaps.

## §2 Families → targeting hunt cfg

| Brief §2 family | Modeled? | Hunt cfg | Note |
|---|---|---|---|
| Family 1 — concurrent-401 refresh drop | ✅ | `MC_hunt_refresh.cfg` | Full base + MC + hunt |
| Family 2 — cache namespace alias (LATENT) | ⛔ deferred | — | `useCache=false` everywhere → dead code today; model when the flag is enabled. Pure data-structure coherence; better served by unit tests T1/T2 in the interim. |
| Family 3 — BLoC out-of-order handlers | ⛔ deferred | — | Mechanism already understood (no `EventTransformer`); fix is mechanical (`restartable()`). Low marginal info from MC. |

## §5 Safety invariants → enabled in ≥1 cfg

| Invariant | Defined in | Enabled in | Status |
|---|---|---|---|
| NoLostRetry (Family 1) | base.tla | `MC_hunt_refresh.cfg` | ✅ enabled (target) |
| SingleRefreshInFlight (Family 1, structural) | base.tla | `base.cfg`, `MC.cfg`, `MC_hunt_refresh.cfg` | ✅ enabled |
| CacheListComplete / CacheNoAlias / SuccessNotThrown (Family 2) | — | — | deferred (Family 2 not modeled) |
| LatestResultWins (Family 3) | — | — | deferred (Family 3 not modeled) |

No invariant is *defined but never enabled* within the modeled scope. ✅

## §6.1 Model-checkable findings → reachable hunt setup

| ID | Reachable? | How |
|---|---|---|
| MC1 (Family 1) | ✅ | `MC_hunt_refresh.cfg`: 3 requests, `MaxRefreshFail=0` (refresh always succeeds) makes the success-path drop reachable; `NoLostRetry` enabled. |
| MC2 (Family 2) | deferred | needs CacheStore extension (not written) |
| MC3 (Family 3) | deferred | needs HandlerGen extension (not written) |

## Output-value litmus (MC1)
Predicted Phase-4 conclusion: **a real, externally-observable defect** — at token expiry, sibling requests fail spuriously even though the refresh succeeds; user sees errors on a screen that fired parallel calls. Not "hardening / no observable consequence / deliberate intent." MC1 passes the litmus → worth checking. ✅

## Honest gaps
- Families 2 & 3 are deferred by decision, not covered. If the next iteration wants them, add `CacheStore` and `HandlerGen` extensions to `base.tla` and matching hunt cfgs.
- `EventuallyDone` (liveness) is written but left commented in `MC.cfg`; the safety bug is the priority for this pass.
