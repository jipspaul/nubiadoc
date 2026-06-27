# Instrumentation Spec — Bug Family 1 (concurrent-401 refresh-lock)

Target file: `front/packages/nubia_core/lib/src/network/auth_interceptor.dart`.
Goal: emit one NDJSON event per base-spec action, in event-loop order, so
`Trace.tla` can replay a real (or scenario) execution.

## Event schema (one JSON object per line)
```json
{ "tag": "refresh", "action": "<ActionName>", "req": "<id>",
  "refreshing": <bool>, "refreshDone": "none|ok|fail", "phase": "<phase>" }
```
- `req`: a stable per-request id. Use `RequestOptions.extra['traceId']` set when the request is built (or `hashCode` of `RequestOptions`).
- All of `refreshing`/`refreshDone`/`phase` are captured **after** the step's state mutation, matching `ValidatePostState` in `Trace.tla`.
- Emit via a test-only sink (e.g. an injected `void Function(Map)` logger), NOT `print` (AGENTS.md rule 7: zero PII / no `print` in prod). Tokens MUST NOT be logged.

## Action → code mapping

| Spec action | Code location | Trigger point | Fields to capture |
|---|---|---|---|
| `Recv401` | `auth_interceptor.dart:39-46` | on entry to `onError` when `response?.statusCode == 401 && path != _refreshPath` (just before the refresh-guard check) | action=Recv401, req, refreshing(current), refreshDone(current), phase="got401" |
| `BeginRefresh` | `auth_interceptor.dart:49,54` | immediately after `_isRefreshing = true` (line 54), in the `!_isRefreshing` branch | action=BeginRefresh, req, refreshing=true, refreshDone="none", phase="refreshing" |
| `DropWhileRefreshing` | `auth_interceptor.dart:49-52` | inside `if (_isRefreshing) { handler.next(err); ... }`, before `return` | action=DropWhileRefreshing, req, refreshing=true, refreshDone(current), phase="failed" |
| `RefreshSucceed` | `auth_interceptor.dart:81-92,97` | after `handler.resolve(retryResponse)` succeeds, in `finally` after `_isRefreshing=false` | action=RefreshSucceed, req, refreshing=false, refreshDone="ok", phase="retried_ok" |
| `RefreshFail` | `auth_interceptor.dart:75-79 / 93-95,97` | both the "missing tokens" branch (75) and the `on DioException` catch (93), after `clearTokens` + `handler.next(err)` and `finally` | action=RefreshFail, req, refreshing=false, refreshDone="fail", phase="failed" |
| `RetryAfterRefresh` | (favorable model step) | a request that received 401 after a prior successful refresh and is retried by a fresh `onError` cycle; emit when such a request resolves OK without itself driving a failing refresh | action=RetryAfterRefresh, req, refreshing=false, refreshDone="ok", phase="retried_ok" |

## Scenario to exercise (reproduces MC1)
1. Seed `TokenStorage` with an **expired** access token + a **valid** refresh token (stub the refresh endpoint to return 200 with fresh tokens).
2. Fire **3 concurrent** requests through the shared singleton `ApiClient.dio` (e.g. `Future.wait([api.a(), api.b(), api.c()])`).
3. The stubbed server returns 401 for all three (expired bearer), 200 on the refresh, and 200 on the retried original.
4. Expected real trace: `Recv401(r1) · BeginRefresh(r1) · Recv401(r2) · DropWhileRefreshing(r2) · Recv401(r3) · DropWhileRefreshing(r3) · RefreshSucceed(r1)`.
5. `NoLostRetry` is violated at `RefreshSucceed(r1)` (r2,r3 already "failed" while refreshDone="ok") — trace validation flags the exact bug.

## Notes for the harness author
- A single shared `HttpClientAdapter` fake (already supported via `AuthInterceptor.setDio`) lets you script per-call responses deterministically — no live backend.
- Keep the emit synchronous with the state mutation (same microtask) so event order equals event-loop order.
- This scenario is also the basis for unit test T-family (brief §6.2): assert that r2 and r3 resolve successfully (the *fixed* behavior) once a wait-queue is added.
