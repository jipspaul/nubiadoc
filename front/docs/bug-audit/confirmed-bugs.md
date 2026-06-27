# Confirmed Bugs — Nubia Flutter front

## BUG-1 — Concurrent 401s dropped (not retried) during token refresh

- **Source**: MC (counterexample from `MC_hunt_refresh.cfg`, `NoLostRetry` violated) + real-trace replay (`traces/refresh.ndjson`)
- **Status**: **REPRODUCED** (escalation Level 0 — pure black-box)
- **Severity**: **High** — production-reachable in all 3 apps; intermittent data-load failures at token expiry
- **Location**: `front/packages/nubia_core/lib/src/network/auth_interceptor.dart:49-52` (inside `onError`, 34-99)

### Description
The interceptor serializes refresh with a bare `bool _isRefreshing`. The first 401 owns the refresh and retries *its own* request; every other request that receives a 401 while the refresh is in flight is completed via `handler.next(err)` and **never retried**, even though the refresh succeeds. There is no waiter queue, so N concurrent requests at token expiry yield 1 success + (N−1) spurious failures.

### Trigger scenario (Phase 1, reachable in normal use)
Access token expires; a screen issues ≥2 requests in parallel (dashboard widgets, list+badge, prefetch). All carry the stale bearer → all get 401. One wins the lock and refreshes successfully; the others are dropped. User sees partial/empty data or error widgets; a later navigation/pull-to-refresh "fixes" it (fresh request carries the new token) — classic intermittent-after-idle.

### Developer-intent investigation (Phase 1, Step 2)
- Single squashed commit `918c439b initFront` — no PR/commit discussion to mine.
- **No existing test** exercises `AuthInterceptor` concurrency (so current behaviour is not asserted-as-intended).
- Code comments state the intent: class contract *"Handles 401 → token refresh → retry (once)"* (line 4-5) and *"Guard against re-entrant refresh (concurrent 401s)"* (line 11). The developer meant to (a) prevent duplicate refreshes **and** (b) retry the request. The drop delivers the retry to only one of N requests → violates the code's **own stated contract**. No comment accepts dropping as a trade-off. → real bug by the code's own standard (engineering principle: documented retry contract not honoured; lost-update on the recovery path).
- Precedent re-check: finding cites no external precedent (skip). The fix is the well-known Dio refresh-queue pattern.

### Reproduction (Phase 2)
- Test: `repro/test_bug1_concurrent_401.dart` — Level 0, drives the **real** `AuthInterceptor` through Dio's public API with a scripted `HttpClientAdapter` (expired bearer → 401, `/auth/refresh` → 200 with new tokens, retry with new bearer → 200) and an in-memory `TokenStorage` fake. No code modification, no timing hacks.
- Command: `flutter test test/auth_interceptor_concurrent_401_repro_test.dart` (run from `packages/nubia_core`, file placed there temporarily then removed; repo left clean).
- **Output (copy-paste):**
  ```
  REPRO BUG-1: 1/3 concurrent requests succeeded after refresh (correct = 3; bug drops the siblings that raced the refresh).
  00:00 +0 -1: concurrent 401s should all be retried after a successful refresh [E]
    Expected: <3>
      Actual: <1>
    concurrent 401s were dropped instead of retried (auth_interceptor.dart:49-52)
  ```
- Bug-match check: 1 success + 2 failures = MC counterexample (r1 `retried_ok`, r2/r3 `dropped` while `refreshDone=ok`). Same actions, same order, same invariant (`NoLostRetry`), same code path. ✅ right bug.

### Not a false positive
- Single lazy-singleton `AuthInterceptor` shared by all requests (`injection.dart:24-27`) — the flag is genuinely shared; no per-request safeguard exists.
- `SingleRefreshInFlight` holds in MC, so the mutual-exclusion *intent* is correct — the defect is specifically the dropped losers, not a refresh race.
- Deterministic Level-0 reproduction (no state injection, no failpoints).

### Recommendation
Replace `_isRefreshing` with a shared `Completer<void>` (or request queue): the first 401 performs the refresh; concurrent 401s `await` the in-flight refresh, then retry their own request with the new token; all fail only if the refresh itself fails. Add the repro as a regression test. (Standard `dio` interceptor refresh-queue pattern.)

---

### Not carried into this confirmation pass
- **Family 2 (cache namespace alias)** — latent/dead code (`useCache=false` everywhere); no production trigger today → not reproduced. Recorded in modeling-brief §6.2 as test-verifiable (T1/T2) for when the flag is enabled.
- **Family 3 (BLoC out-of-order handlers)** — code-review-only; mechanical fix (`restartable()`); not model-checked this pass.
