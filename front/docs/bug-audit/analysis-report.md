# Analysis Report — Nubia Flutter front (`front/`)

Audit trail for `modeling-brief.md`. Scope (per user): `front/` only (3 Flutter apps + 7 packages).

## Coverage statistics
- Git bug-fix commits touching `front/`: **118** (keyword scan: fix/bug/race/crash/leak/corrupt/wrong/inconsist/deadlock/BUG/corrige/répare/fuite/concurr). Recent clusters: (a) DTO↔real-API alignment ("BUG-01"), (b) repository/bloc/screen error-nets ("BUG-01a" try/catch), (c) auth/routing splash fixes. No prior commit touches the refresh-lock or cache-coherence mechanisms below.
- Core files read in full (14): `nubia_core` → `network/auth_interceptor.dart`, `network/api_client.dart`, `auth/auth_session.dart`, `storage/token_storage.dart`, `di/injection.dart`, `router/router_notifier.dart`, `router/auth_guard.dart`; `nubia_data` → `cache/cached_repository.dart`, `cache/cached_data.dart`, `cache/appointments_cache.dart`, `cache/drift/drift_appointments_cache.dart`, `cache/drift/nubia_database.dart`, `di/data_registration.dart`, `repositories/{auth_repository_impl, cached_appointments_repository_impl}.dart`; plus `apps/app_patient/lib/{app.dart, session/auth_cubit.dart, features/appointments/appointments_bloc.dart, features/mes_rdv/mes_rdv_page.dart}`.
- Parallel deep-analysis: 2 `Explore` subagents (auth lifecycle; BLoC layer). Every subagent finding re-verified against exact source lines before inclusion.
- Findings excluded as false positives after re-reading: **4** (below).

## System classification
**Category B (Concurrent / Runtime).** Single-threaded Dart event loop; concurrency arises only from async interleaving at `await` points. The bug-dense surfaces are the protocol-shaped ones: the JWT refresh lock, the offline cache state machine, and BLoC event handling — not UI widgets.

## Topology facts that shaped severity
- `TokenStorage`, `AuthInterceptor`, `ApiClient` are **lazy singletons** (`injection.dart:24-27`) ⇒ one interceptor instance/app ⇒ `_isRefreshing` is a valid intra-instance guard; no cross-instance refresh-token rotation race.
- `useCache` defaults **false** (`data_registration.dart:78`) and **no** app passes `true` (`app_*/lib/bootstrap.dart`) ⇒ the entire Drift cache + `CachedAppointmentsRepositoryImpl` are **dead code today**; Family 2 is latent.
- No `EventTransformer` and no `isClosed`/`emit.isDone` guard anywhere (`grep` over `apps/*/lib` → 0 hits each).

## Confirmed findings (detail)

### F1 — Concurrent-401 refresh drops in-flight requests (Family 1)
`auth_interceptor.dart:49-52`. First 401 sets `_isRefreshing=true` (line 54) and `await`s the refresh POST (67); during that await, sibling 401s hit the guard and `handler.next(err)` — they fail with the raw 401 and are **never retried** with the refreshed token (only `err.requestOptions` of the winner is retried, line 87-92). Check-then-set is race-free in Dart (no await between 49 and 54), so this is a *design* gap (no waiter queue), not a TOCTOU. User impact: at token-expiry, a screen firing several parallel calls shows spurious errors for all but one. **Reachable in all 3 apps.**

### F2 — Cache namespace alias + inconsistent invalidation (Family 2, latent)
- PK alias: `nubia_database.dart:34` (`id … PRIMARY KEY`) + `drift_appointments_cache.dart:80-86` (`saveOne` `INSERT OR REPLACE`, `list_key=NULL`). For an id already cached via `saveUpcoming` (`list_key='upcoming'`, line 60-77), `saveOne` rewrites that row's `list_key` to NULL ⇒ it disappears from `getUpcoming` (`WHERE list_key='upcoming'`) while `cache_timestamps['upcoming']` stays fresh ⇒ incomplete list served as fresh ≤maxAge. Concrete trigger: list→detail (`getById`→`saveOne`)→back.
- Under-invalidation: `book`/`checkin` (`cached_appointments_repository_impl.dart:48-59,90-98`) `saveOne` but never touch the list cache ⇒ new/changed appt missing from cached list ≤maxAge.
- Dead write: `cancel`/`modify` (61-88) `saveOne(...)` then `clear()` (drift `clear` wipes all rows, 97-100) ⇒ `saveOne` is pointless.
- Success→exception: `cached_repository.dart:27-33` and decorator write paths `await writeToCache(data)`/`_cache.saveOne(...)` with no try/catch ⇒ a cache-write failure throws out of a *successful* remote op, breaking the `Either` contract callers rely on.

### F3 — BLoC out-of-order handlers (Family 3)
`appointments_bloc.dart:23,30-52`: search-as-you-type, no transformer; concurrent handler resolution lets a slow older query `emit` after a fast newer one. Generalizes to all async search/list/pagination blocs (0 transformers in repo).

### Lower-severity confirmed (code-review)
- emit-after-`await` with no `isClosed` guard — systematic; `StateError` on dispose-during-await, frequently swallowed by `catch (_)`.
- Pull-to-refresh false completion — `mes_rdv_page.dart:157-160` returns `Future.delayed(Duration.zero)`; `onRefresh: () async => …add(...)` variants (financial/reviews/waiting_room/agenda/waiting_list) complete before reload ⇒ violates AGENTS.md Completer pattern.
- `registerOnLogin` fire-and-forget (`auth_cubit.dart:74`) — errors swallowed.

## Exclusions (false positives — re-read to confirm)
1. **Logout never clears tokens** (claimed: `unregisterFcmToken` throws → `clearTokens` skipped). EXCLUDED: `unregisterFcmToken` returns `Either<Failure,void>` (`notification_repository.dart:23`); it does not throw and the result is intentionally discarded (best-effort). `clearTokens` (`auth_repository_impl.dart:92`) always runs.
2. **Multi-Dio refresh-token rotation race**. EXCLUDED: single lazy-singleton `AuthInterceptor`/`ApiClient` (`injection.dart:24-27`); only one refresh path exists.
3. **Splash hangs forever** (claimed: `restore()` not awaited at `app.dart:38`). EXCLUDED: `restore()` always emits a terminal state including in `catch` (`auth_cubit.dart:50-65`) → stream listener → `mark*` → `notifyListeners` → guard re-eval; `isResolved` correctly gates the splash redirect (`auth_guard.dart:29-32`).
4. **`refreshAuth` stale-token desync** (`router_notifier.dart:25-32`). EXCLUDED: `refreshAuth` is **never called** (apps drive the notifier via the cubit stream); dead code. (Listed as CR6 cleanup.)

## Notes for next phase
- Best TLA+ value: Family 1 (production, canonical) and Family 2 (rich coherence state machine; flag it as latent until `useCache` is enabled). Family 3 is a clean interleaving model.
- Closed historical bugs (DTO alignment, error-nets) are bug-prone-mechanism *evidence* only — not modeling targets.
