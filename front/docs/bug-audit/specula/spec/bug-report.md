# Bug Report — Nubia Flutter front, Bug Family 1

## BUG-1: Concurrent 401s are dropped (not retried) during token refresh

**Severity**: High (production-reachable in all 3 apps) · **Confidence**: Confirmed (exhaustive MC + real-trace replay)

**Location**: `front/packages/nubia_core/lib/src/network/auth_interceptor.dart:49-52` (within `onError`, lines 34-99).

**Invariant violated**: `NoLostRetry` — *if the in-flight refresh succeeds, no 401'd request is dropped*.

### Counterexample (MC_hunt_refresh.cfg, MaxRefreshFail=0, 6 steps)
| # | Action | `reqPhase` | `refreshing` | `refreshDone` |
|---|--------|-----------|------|------|
| 1 | init | r1,r2,r3 = inflight | F | none |
| 2 | Recv401(r1) | r1=got401 | F | none |
| 3 | Recv401(r2) | r2=got401 | F | none |
| 4 | BeginRefresh(r1) | r1=refreshing | **T** | none |
| 5 | DropWhileRefreshing(r2) | r2=**dropped** | T | none |
| 6 | RefreshSucceed(r1) | r1=retried_ok, r2=**dropped** | F | **ok** |

At step 6 the refresh has succeeded (`refreshDone=ok`) yet r2 was already failed at step 5 → `NoLostRetry` violated. The same violation is reproduced by replaying the real recorded trace `traces/refresh.ndjson` (3 concurrent requests) against the converged spec (final state `r1=retried_ok, r2=dropped, r3=dropped`).

### Root cause (code)
```dart
// auth_interceptor.dart
49    if (_isRefreshing) {
50      handler.next(err);   // <-- sibling 401 FAILS here, never queued/retried
51      return;
52    }
53
54    _isRefreshing = true;  // first 401 owns the single refresh
...
91    final retryResponse = await retryDio.fetch<dynamic>(retryOptions); // only the WINNER retries
92    handler.resolve(retryResponse);
```
The refresh lock is a binary flag with no waiter queue. Only `err.requestOptions` (the request that won the lock) is retried; every other request that hits a 401 during the refresh window is completed with the original 401 error, even though the refresh that would have fixed them succeeds milliseconds later.

### Trigger (real)
At access-token expiry, any screen that fires ≥2 requests in parallel (dashboard, list+badge, prefetch) has all-but-one request fail spuriously. User sees partial/empty data or error widgets on a screen that should have loaded fully; pull-to-refresh or navigation usually "fixes" it (a fresh request now carries the refreshed token) — the hallmark intermittent-after-idle symptom.

### Why it's not a false positive
- Single lazy-singleton `AuthInterceptor` shared by all requests (`injection.dart:24-27`) — the flag is genuinely shared.
- `SingleRefreshInFlight` holds in MC, so the mutual-exclusion intent is correct; the defect is the *drop* of the losers, not a refresh race.
- Confirmed independently by exhaustive model checking and by replaying an event-loop-ordered real trace.

### Fix direction
Replace the bool with a shared `Completer<void>`/queue: the first 401 performs the refresh; concurrent 401s `await` the in-flight refresh and then retry their own request under the new token (fail only if the refresh itself fails). This is the standard Dio refresh-queue pattern.

## State-space coverage
| Config | Result | Distinct states | Depth |
|--------|--------|-----------------|-------|
| MC.cfg (convergence) | no violation; `SingleRefreshInFlight` holds | 30 | 8 |
| MC_hunt_refresh.cfg | **NoLostRetry violated** | 17 (to first violation) | 8 |
| Trace structural (real trace) | PASS, `TraceMatched` | 8 | 8 |
| Trace + NoLostRetry (real trace) | **NoLostRetry violated** | — | 8 |

Diameter ≤ 25 but the state space is complete (BFS exhausted, 0 states left on queue) at these bounds — no simulation follow-up needed. Families 2 & 3 not modeled this pass (see brief-coverage.md).
