# Spec changelog — Bug Family 1 (concurrent-401 refresh-lock)

## Round 1 — Model Checking (convergence, MC.cfg)
- [fix-spec] base: first MC.cfg run deadlocked — leftover `got401` requests had no enabled transition after a `RefreshFail`. Added `CleanupAfterFail` (models interceptor.dart:56-61, null refresh token after clear) + a `TerminalStutter` self-loop. Also split the bug outcome into a distinct `dropped` phase (vs. legitimate `failed`) so `NoLostRetry` precisely targets lost retries.
- [fix-spec] MC: added `EXTENDS … TLC` (Permutations) and wired `MCCleanupAfterFail` / `MCTerminalStutter` into `MCNext`.
- Result: MC.cfg passes — 30 distinct states, depth 8, `SingleRefreshInFlight` holds (the `_isRefreshing` check-then-set is atomic in Dart; no `await` between lines 49 and 54).

## Round 1 — Trace Validation
- [fix-spec] Trace.cfg: `Requests` declared as JSON strings `{"r1","r2","r3"}` (trace `req` fields are strings; MC keeps model values for symmetry).
- Trace `refresh.ndjson` (7 events, the 3-concurrent-request scenario): structural validation PASSES — all events consumed, `TraceMatched` satisfied. Spec faithfully reproduces the real execution (spec ⊇ system).

## Convergence
Converged in 1 round (Phase 2 spec changes did not break Phase 1). Spec trusted.

## Bug Hunting
- [bug] DropWhileRefreshing: `MC_hunt_refresh.cfg` (MaxRefreshFail=0) violates `NoLostRetry` in a 6-step counterexample. Same violation reproduced by replaying the real trace `refresh.ndjson` against the converged spec.

## Result
Converged in 1 round. Bug hunting: 1 bug found (Family 1 / brief MC1) — confirmed by both exhaustive MC and real-trace replay.
