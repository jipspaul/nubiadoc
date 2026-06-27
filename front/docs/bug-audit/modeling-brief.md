# Modeling Brief — Nubia Flutter front (`front/`)

## 1. System Overview

- **System**: Nubia Flutter monorepo (`front/`) — 3 apps (patient / praticien / secrétariat) + 7 shared packages. ~487 Dart files (non-generated). Core logic analyzed: `nubia_core` (network/auth/router, 14 files) + `nubia_data` (repos + offline cache, 86 files) + per-app BLoCs.
- **Category**: **Category B (Concurrent / Runtime)**. Dart is a single-threaded event loop, but every `await` is an interleaving point: in-flight Dio requests, BLoC event handlers, and the auth/refresh flow interleave at suspension points. No isolates/locks; correctness rests on careful ordering across `await` boundaries.
- **Protocol implemented**: token-bearer HTTP client with **JWT 401→refresh→retry** (a refresh-lock protocol), a **cache-then-network** offline layer (write-through + staleness), and **event-sourced UI state** (BLoC/Cubit).
- **Key architectural choices**: hexagonal layering (domain ports / data adapters); GetIt hand-wired singletons; `dartz` `Either<Failure,T>` for error propagation (errors are values, not exceptions, at the repo boundary).
- **Concurrency model**: single-threaded microtask/event loop; concurrency = async interleaving only.

## 2. Bug Families

### Family 1: Concurrent-401 refresh drops in-flight requests (no wait-queue)
**Mechanism**: The refresh-lock is a binary `_isRefreshing` flag; concurrent 401s that arrive while a refresh is in progress are **failed immediately** instead of being queued and retried after the refresh succeeds.

**Evidence**:
- Code: `packages/nubia_core/lib/src/network/auth_interceptor.dart:49-52` — `if (_isRefreshing) { handler.next(err); return; }`. The first 401 (line 54) does the refresh; every other concurrent 401 returns the raw error.
- Code: `auth_interceptor.dart:34-99` — only `err.requestOptions` (the *first* request) is retried (line 91); the losers are never re-driven with the new token.

**Affected code paths**: `AuthInterceptor.onError`.

**Suggested modeling approach**:
- Variables: `tokenEpoch` (monotonic), `refreshing` (bool), per-request `{state: inflight|got401|retried|failed|resolved, tokenSeen}`, a `waiters` set.
- Actions: `Send`, `Recv401`, `BeginRefresh`, `RefreshOk`/`RefreshFail`, `Retry`, `DrainWaiter`. Split refresh into begin/complete (await window).
- Granularity: model N≥2 concurrent requests sharing one interceptor; the refresh await must be its own action so other requests interleave on `got401`.

**Priority**: **High** — production-reachable (interceptor wired in all 3 apps), canonical concurrent protocol, directly TLA+-suitable.

---

### Family 2: Offline-cache incoherence (single-PK namespace collision + inconsistent write-through invalidation) — **LATENT**
**Mechanism**: The Drift cache keys list-membership by a nullable `list_key` column but uses `id` as the **sole PRIMARY KEY**, so the "upcoming list" namespace (`list_key='upcoming'`) and the "single entry" namespace (`list_key=NULL`) **alias** on the same id; combined with write paths that invalidate the list inconsistently, the cached list silently diverges from truth while still reported *fresh*.

**Evidence**:
- Schema: `packages/nubia_data/lib/src/cache/drift/nubia_database.dart:31-37` — `id TEXT NOT NULL PRIMARY KEY`.
- `drift_appointments_cache.dart:80-86` — `saveOne` does `INSERT OR REPLACE ... list_key=NULL`. For an id already in the cached upcoming list, this **flips that row's `list_key` to NULL**, removing it from `getUpcoming` (`WHERE list_key='upcoming'`, line 28-32) — yet `cache_timestamps['upcoming']` stays fresh ⇒ an *incomplete* list is served as fresh (≤5 min).
  - Trigger: load upcoming (cached) → open one appointment → `getById` → on remote success `saveOne` → that appointment vanishes from the cached list on return.
- `cached_appointments_repository_impl.dart:48-59,90-98` — `book`/`checkin` `saveOne` but **never invalidate the upcoming list** ⇒ a just-booked appointment is missing from the cached list for ≤5 min.
- `cached_appointments_repository_impl.dart:61-88` — `cancel`/`modify` do `saveOne(...)` **then** `clear()` (drift `clear` deletes *all* rows, line 97-100) ⇒ the `saveOne` is dead work; net over-invalidation (safe but inconsistent with book/checkin).
- `cached_repository.dart:27-33` + decorator write paths: on remote **success**, `writeToCache(data)` is `await`ed with **no try/catch** ⇒ a cache-write failure throws out of a successful network op, turning success into an exception the BLoC layer never expects (`Either` contract violated).

**Affected code paths**: `DriftAppointmentsCache.{saveOne,saveUpcoming,getUpcoming,clear}`, `CachedAppointmentsRepositoryImpl.{getById,book,cancel,modify,checkin}`, `CachedXRepository.cacheFirst`.

**Suggested modeling approach**:
- Variables: `cache` as a map keyed by `(id)` carrying `{listKey, data}`, `listTimestamp`, `truth` (server set), `now`/`maxAge`.
- Actions: `LoadList`, `LoadOne`, `Book`, `Cancel`, `Modify`, `Checkin`, `Expire`. Model `saveOne`/`saveUpcoming` as map writes that *share the id key* (this is what reproduces the alias).
- Invariant: served-fresh list ⊆/⊇ truth (see §5 `CacheListComplete`).

**Priority**: **Medium** — code is **dead today** (`useCache` defaults `false`; every `registerData` call site omits it). Becomes High the instant `useCache: true` is flipped. Excellent cache-coherence TLA+ target.

---

### Family 3: BLoC event-ordering races (no `EventTransformer`, lost-update)
**Mechanism**: No BLoC anywhere uses an `EventTransformer` (`restartable`/`droppable`/`sequential`); bloc's default processes events **concurrently**, so for the same logical screen a slow older handler can `emit` after a fast newer one, clobbering fresh UI state with stale data.

**Evidence**:
- Code: `apps/app_patient/lib/features/appointments/appointments_bloc.dart:23,30-52` — `on<AppointmentsSearchChanged>(_onSearchChanged)` with no transformer; search-as-you-type fires one event/keystroke; `await _searchProviders(query)` then `emit(...Loaded(query))`. Response order ≠ keystroke order ⇒ stale query results win.
- Verified absence: `grep restartable|droppable|EventTransformer|transformer:` over `apps/*/lib` → **0 hits**; same handler shape recurs across search/load/pagination blocs.

**Affected code paths**: all async `on<…>` handlers driving search/list/pagination (appointments, patients, messaging, search…).

**Suggested modeling approach**:
- Variables: per-bloc `state`, an event queue, per-handler `{query, gen}` with a monotonic `gen`.
- Actions: `AddEvent`, `StartHandler`, `HandlerResolve(gen)` (interleavable), `Emit`. Model 2 events with swapped resolution order.
- Invariant: `state` reflects the **latest accepted** event's result (see §5 `LatestResultWins`).

**Priority**: **Medium** — production-reachable, user-visible (search), cleanly TLA+-modelable as handler interleaving.

## 3. Modeling Recommendations

### 3.1 Model
- **Refresh-lock with N concurrent requests** (Family 1) — *why*: the `_isRefreshing` fast-fail drops losers; *how*: split-action refresh + waiter set, invariant "every request that saw a recoverable 401 is eventually retried under a valid token or fails only because refresh failed".
- **Cache namespace + write-through invalidation** (Family 2) — *why*: PK alias + inconsistent invalidate; *how*: id-keyed cache map with shared keys across list/single namespaces; freshness vs completeness invariant.
- **Handler interleaving / latest-wins** (Family 3) — *why*: no transformer; *how*: generation-tagged handlers, monotone-accepted-result invariant.

### 3.2 Do Not Model
- **emit-after-`await` without `isClosed` guard** (systematic; `grep isClosed|emit.isDone` → 0 hits) — runtime `StateError` on dispose-during-await, often swallowed by the handlers' `catch (_)`. Implementation/lifecycle detail, not a protocol property ⇒ code-review/test.
- **Pull-to-refresh false completion** (`mes_rdv_page.dart:157-160` returns `Future.delayed(Duration.zero)`; several `onRefresh: () async => …add(...)` variants) — UX/widget-lifecycle, no state-machine content.
- **Clinical cloisonnement (secretariat)** — enforced by DI/nav/runtime/tests defense-in-depth; an access-control config property, not a concurrency target here.
- **`registerOnLogin` fire-and-forget** (`auth_cubit.dart:74`) — robustness gap, swallowed errors; review-only.

## 4. Proposed Extensions

| Extension | Variables | Purpose | Bug Family |
|-----------|-----------|---------|------------|
| RefreshLock | `refreshing`, `tokenEpoch`, `req[*].{phase,seen}`, `waiters` | Model concurrent 401 handling + retry/drain | Family 1 |
| CacheStore | `cache[id].{listKey,data}`, `listTs`, `truth`, `clock` | Alias collision + write-through invalidation | Family 2 |
| HandlerGen | `state`, `handlers[*].{key,gen,phase}`, `acceptedGen` | Out-of-order handler resolution | Family 3 |

## 5. Proposed Invariants

| Invariant | Type | Description | Targets |
|-----------|------|-------------|---------|
| NoLostRetry | Safety | Every request that received a 401 and a subsequent successful refresh is retried under the new token (not failed) | Family 1 |
| SingleRefreshInFlight | Safety | At most one refresh POST is in flight per interceptor | Family 1 |
| CacheListComplete | Safety | If `getUpcoming` returns data marked fresh, its membership equals the last server list minus locally-applied mutations | Family 2 |
| CacheNoAlias | Safety | A single id is not simultaneously claimed by both the list and single-entry namespaces with divergent data | Family 2 |
| SuccessNotThrown | Safety | A successful remote op never surfaces as an exception due to a cache-write failure | Family 2 |
| LatestResultWins | Safety | Final `state` corresponds to the most recently accepted event's result | Family 3 |

## 6. Findings Pending Verification

### 6.1 Model-Checkable
| ID | Description | Expected invariant violation | Bug Family |
|----|-------------|------------------------------|------------|
| MC1 | With ≥2 requests sharing one interceptor, does a concurrent 401 get dropped (failed) even though the refresh it raced succeeds? | NoLostRetry | 1 |
| MC2 | Can `saveOne(id)` on an id present in the cached upcoming list make `getUpcoming` serve an incomplete list while still reported fresh? | CacheListComplete / CacheNoAlias | 2 |
| MC3 | With out-of-order handler resolution, can a stale search result become the terminal state? | LatestResultWins | 3 |

### 6.2 Test-Verifiable
| ID | Description | Suggested test approach |
|----|-------------|-------------------------|
| T1 | `cacheFirst`/decorator: cache-write throws on a successful remote → call surfaces a thrown exception instead of `Right` | Unit test with a throwing `AppointmentsCache` fake; assert `Right` returned |
| T2 | `book`/`checkin` leave a stale upcoming list (new appt missing ≤maxAge) | Integration test over `CachedAppointmentsRepositoryImpl` + in-memory Drift |
| T3 | emit-after-close: dispose bloc during in-flight handler `await` | `blocTest` closing the bloc mid-future; assert no unhandled `StateError` |

### 6.3 Code-Review-Only
| ID | Description | Suggested action |
|----|-------------|------------------|
| CR1 | No `EventTransformer` on any search/load bloc | Add `restartable()` to search-as-you-type handlers |
| CR2 | No `isClosed`/`emit.isDone` guard in any async handler | Add guard after `await` before `emit` |
| CR3 | Pull-to-refresh returns immediately (false spinner) — violates AGENTS.md Completer pattern | Apply the documented Completer-in-BlocListener pattern |
| CR4 | `cancel`/`modify` do `saveOne` then `clear` (dead write) | Drop the `saveOne`, or invalidate list only |
| CR5 | `registerOnLogin` fire-and-forget swallows errors | Await + surface/log failure |
| CR6 | `RouterNotifier.refreshAuth` is dead code (never called) | Remove or wire intentionally |

## 7. Reference Pointers
- Full analysis: `analysis-report.md` (same dir).
- Refresh lock: `packages/nubia_core/lib/src/network/auth_interceptor.dart:34-99`.
- Cache: `packages/nubia_data/lib/src/cache/drift/{drift_appointments_cache.dart,nubia_database.dart}`, `cache/cached_repository.dart`, `repositories/cached_appointments_repository_impl.dart`.
- Wiring/topology: `packages/nubia_core/lib/src/di/injection.dart` (lazy singletons), `packages/nubia_data/lib/src/di/data_registration.dart:74-116` (`useCache` default false).
- Blocs: `apps/app_patient/lib/features/appointments/appointments_bloc.dart`.
- Excluded (false positives), see analysis-report §Exclusions: logout-token-clear, multi-Dio rotation, splash infinite-hang, `refreshAuth` stale-token.

**Coverage**: git bug-fix commits touching `front/` = 118 (recent cluster: DTO/API alignment + repository error-nets "BUG-01a"); core files read in full: 14 (`nubia_core` net/auth/router + `nubia_data` cache/decorator/DI/auth-repo); 2 parallel deep-analysis subagents over auth-lifecycle and BLoC layers; 4 reported findings excluded as false positives after re-reading the exact lines.
