# Bug Catalog — Nubia Flutter front (`front/`)

**Date:** 2026-06-27 · **Scope:** the three apps + shared packages.
**Detection coverage (honest statement):**

| Layer | Coverage |
|---|---|
| `nubia_core`, `nubia_data` (shared by all 3 apps) | Core files read **in full** |
| `app_patient` (12 blocs / 15 pages) | **Exhaustive** sweep — every bloc + page |
| `app_practicien` (9 blocs / 8 pages) | **Exhaustive** sweep — every bloc + page |
| `app_secretariat` (12 blocs / 13 pages) | **Exhaustive** sweep — every bloc + page |
| Formal verification (TLA+/TLC) | BUG-1 only (modeled, model-checked, reproduced) |

**Verification legend:**
- 🟢 **VERIFIED** — I read the exact code and/or reproduced it (TLC + live test).
- 🟡 **PATTERN-CONFIRMED** — the systemic pattern is verified repo-wide (`grep`), the specific instance comes from the per-app sweep (file:line reported, not all individually re-read).
- 🟠 **SUSPECTED** — plausible from code shape, depends on a runtime path (e.g. realtime receive) not confirmed to exist.

> Severities here are **calibrated** (recalibrated down from the raw sweep output). In Dart, "emit-after-await" raises a `StateError` that the surrounding `catch (_)` usually swallows (logged, not a hard crash); pull-to-refresh false-completion is a UX defect (no data loss). Only **BUG-1** is High and proven.

---

## A. Shared-layer bugs — affect ALL THREE apps

These live in `nubia_core` / `nubia_data`, which every app depends on.

### A1 — 🟢 BUG-1: Concurrent 401s dropped during token refresh  ·  **Severity: High**  ·  **CONFIRMED + REPRODUCED**
- **Location:** `packages/nubia_core/lib/src/network/auth_interceptor.dart:49-52` (in `onError`, 34-99).
- **What:** The refresh lock is a bare `bool _isRefreshing` with no waiter queue. The first 401 refreshes and retries *its own* request; every other request that gets a 401 while the refresh is in flight is completed via `handler.next(err)` and **never retried**, even though the refresh succeeds. N concurrent requests at token expiry → 1 success + (N−1) spurious failures.
- **Trigger:** Access token expires; any screen firing ≥2 parallel requests (dashboard widgets, list+badge, prefetch). All apps do this.
- **Evidence:** TLC `MC_hunt_refresh.cfg` violates `NoLostRetry` (6-step counterexample); real-trace replay confirms; live Dart repro `flutter test` → **Expected 3, Actual 1**.
- **Why all 3 apps:** single lazy-singleton `AuthInterceptor` (`injection.dart:24-27`) shared by every Dio request in every app.
- **Fix:** shared `Completer<void>`/queue — concurrent 401s await the in-flight refresh then retry their own request (standard `dio` refresh-queue). Repro doubles as regression test.
- **Full write-up:** `confirmed-bugs.md` (BUG-1) + `spec/bug-report.md`.

### A2 — 🟢 Offline-cache incoherence (LATENT)  ·  **Severity: Medium (latent; High if enabled)**
- **Location:** `packages/nubia_data/lib/src/cache/drift/{drift_appointments_cache.dart,nubia_database.dart}`, `cache/cached_repository.dart`, `repositories/cached_appointments_repository_impl.dart`.
- **Status:** **Dead code today** — `useCache` defaults `false` and no app passes `true` (`registerData(getIt)` in all three `bootstrap.dart`). Bites the moment the flag is flipped.
- **Sub-findings:**
  - **Namespace alias:** `id` is the sole PRIMARY KEY but list-membership is keyed by nullable `list_key`. `saveOne` (list_key NULL) on an id already in the cached upcoming list flips that row's `list_key` to NULL → it vanishes from `getUpcoming`, yet the list timestamp stays *fresh* → incomplete list served as fresh (≤5 min). Trigger: list → open detail (`getById`→`saveOne`) → back.
  - **Under-invalidation:** `book`/`checkin` `saveOne` but never invalidate the upcoming list → new/changed appointment missing from the cached list ≤5 min.
  - **Dead write:** `cancel`/`modify` do `saveOne(...)` then `clear()` (wipes all rows) → the `saveOne` is pointless.
  - **Success→exception:** `cacheFirst` / decorator `await writeToCache(data)` with no try/catch → a cache-write failure throws out of a *successful* remote op, breaking the `Either` contract callers rely on.
- **Fix:** composite key `(id, list_key)` or separate tables; invalidate the list on every write; wrap cache writes so a cache failure never fails a successful remote op. (Test-verifiable now — brief §6.2 T1/T2.)

### A3 — 🟢 Auth lifecycle notes (lower severity)
- **`signIn` fire-and-forget** (`apps/*/lib/session/auth_cubit.dart:74`): `_deviceRegistration.registerOnLogin(...)` not awaited; errors swallowed → FCM registration can silently fail. **Severity: Low.**
- **Dead code:** `RouterNotifier.refreshAuth()` (`router/router_notifier.dart:25-32`) is never called. Cleanup, not a bug.
- **Excluded false positives (re-verified):** logout-never-clears-tokens (unregister returns `Either`, doesn't throw); multi-Dio rotation race (single singleton); splash infinite-hang (`restore()` always emits a terminal state; `isResolved` gates correctly).

---

## B. Systemic UI-layer patterns — present in ALL THREE apps

Verified repo-wide: `grep isClosed|emit.isDone` → **0 hits**; `grep restartable|droppable|sequential|EventTransformer|transformer:` → **0 hits**.

### B1 — 🟡 emit-after-await without `isClosed` guard  ·  **Severity: Medium (systemic)**
Every async `on<…>` / cubit handler awaits a repo call then `emit(...)` with no `if (isClosed) return;`. If the bloc is disposed during the await (user navigates away), `emit` throws `StateError`; often swallowed by `catch (_)` (logged), occasionally surfaces as an unhandled async error. Highest-impact instances (action handlers that emit on the success path after an await):

| App | Instance (file:line) |
|---|---|
| app_patient | `mes_rdv_bloc.dart:53-93` (`_onCancel`/`_onCheckin`); all load handlers (appointments, dashboard, documents, financial, home, messaging, notifications, profile, reviews) |
| app_practicien | `consultation_clinique_bloc.dart:59-68,82-86`; `agenda_bloc.dart:85-96,110-121`; `patients_bloc.dart:65-72`; `cabinet_messaging_bloc.dart:77-87,99-104`; `waiting_room_bloc.dart:45-52` |
| app_secretariat | `waiting_list_bloc.dart:37-53`; `waiting_room_bloc.dart:37-50`; `cabinet_messaging_bloc.dart:68-91`; plus all load handlers |

**Fix:** add `if (isClosed) return;` after each `await` before `emit`. (Or a small base-bloc `safeEmit`.)

### B2 — 🟡 Out-of-order events (no `EventTransformer`)  ·  **Severity: Medium**
No bloc declares a transformer, so the default concurrent processing lets a slow older handler `emit` after a fast newer one. Worst where rapid/overlapping events occur:

| App | Instance |
|---|---|
| app_patient | `appointments_bloc.dart:30-52` (🟢 search-as-you-type lost-update — verified) |
| app_practicien | `agenda_bloc.dart` rapid week prev/next; `cabinet_messaging_bloc.dart` rapid sends |
| app_secretariat | `appointments_bloc.dart` (create/confirm/reschedule on one handler); `agenda_bloc.dart`; `waiting_list_bloc.dart` |

**Fix:** `restartable()` for search/load (latest wins); `droppable()` for action buttons (ignore rapid double-fire).

### B3 — 🟡 Pull-to-refresh false completion  ·  **Severity: Low (UX)**
`onRefresh` returns before the reload finishes → spinner dismisses early. Violates the project's own AGENTS.md Completer-in-BlocListener pattern.

| App | Instance |
|---|---|
| app_patient | 🟢 `mes_rdv_page.dart:157-160` (`return Future.delayed(Duration.zero)` — verified); `financial_page.dart:70`; `reviews_page.dart:80`. (Note: `documents_page.dart:141` correctly awaits `bloc.stream.firstWhere`.) |
| app_practicien | `waiting_room_page.dart:116-118` |
| app_secretariat | `waiting_list_page.dart:59`; `agenda_page.dart:162`; `admin_secretariats_page.dart:74`; `cabinet_messaging_page.dart:119` |

**Fix:** apply the documented Completer-in-`BlocListener` pattern (resolve on both Loaded and Error).

---

## C. App-specific notable bugs

### C1 — 🟡 app_practicien: prescription double-sign  ·  **Severity: Medium**
`ordonnances_bloc.dart:40-54` `_onSign` emits `Loading` with no in-progress guard, and `ordonnances_page.dart:157` does not disable the "Signer" button during signing → rapid double-tap can queue two sign requests (duplicate signature if backend not idempotent). **Fix:** guard on in-progress state + disable button.

### C2 — 🟠 Messaging: incoming message dropped during send  ·  **Severity: Medium (SUSPECTED)**
`messaging_bloc.dart` (patient `_onSend`, practicien/secretariat `cabinet_messaging_bloc.dart`): `current.messages` is snapshotted before `await _sendMessage`, then the new message is appended to the *stale* list. If a concurrent receive/refresh updates the thread during the send, those messages are lost on emit. **Depends on a concurrent receive path existing** (realtime/polling) — not confirmed; if messaging is pure request/response on user action, the window is narrow. **Fix:** re-read `state` after the await, or guard with `isClosed`.

### C3 — 🟡 app_secretariat: create-slot has no success state  ·  **Severity: Low (UX)**
`bookable_slots_bloc.dart:37-56`: on create success it calls `add(LoadRequested())` (→ Loading) without a success emit → user sees a spinner instead of confirmation. **Fix:** emit a transient success state / snackbar.

### C4 — 🟡 app_patient: profile toggle silent failure  ·  **Severity: Low**
`profile_bloc.dart:48-98`: biometric/notification toggles emit the optimistic state, and `catch (_)` swallows a save failure → user believes the setting saved when it didn't. **Fix:** revert + surface an error on failure.

---

## D. Per-app coverage matrix

### app_patient — features swept
appointments 🐛(B2,B1-style) · booking (stub, clean) · dashboard (B1) · documents (B1; refresh OK) · financial 🐛(B3,B1, stale-state) · home (B1) · login (stateless, clean) · mes_rdv 🐛(B3 verified,B1) · messaging 🐛(C2,B1) · notifications (B1) · oubliettes (clean) · profile 🐛(C4,B1) · reviews 🐛(B3,B1) · prepare_rdv/detail_rdv (use `mounted`, clean)

### app_practicien — features swept
agenda 🐛(B1×2,B2) · cabinet_messaging 🐛(B1×2,C2,B2) · consultation_clinique 🐛(B1×2) · dashboard (clean) · login (clean) · ordonnances 🐛(C1) · patients 🐛(B1) · waiting_room 🐛(B3,B1)

### app_secretariat — features swept
admin_membres (clean) · admin_secretariats 🐛(B3) · agenda 🐛(B3,B2) · appointments 🐛(B2) · bookable_slots 🐛(C3) · cabinet_messaging 🐛(B3,B1,C2) · dashboard (clean) · devis (clean) · login (clean) · patients (clean) · waiting_list 🐛(B1,B2,B3) · waiting_room 🐛(B1,B2)
**Cloisonnement clinique: PASS** — no `ConsultationRepository`/`PrescriptionRepository` imported; role hardcoded `secretary`, `includeClinical:false`; no clinical UI/route registered.

---

## E. Priority for fixing

1. **A1 / BUG-1 (High, proven)** — interceptor refresh queue. Affects all apps, intermittent real failures. *Fix first.*
2. **B1 emit-after-await (Medium, systemic)** — one base-bloc `safeEmit`/guard removes a whole class repo-wide.
3. **B2 EventTransformer (Medium)** — `restartable` on search/load, `droppable` on action buttons.
4. **C1 double-sign (Medium)** — clinical correctness; quick button-disable + guard.
5. **A2 cache (Medium, latent)** — fix before anyone sets `useCache:true`; add the T1/T2 tests now.
6. **B3 / C3 / C4 (Low, UX)** — refresh Completer pattern, success states, toggle error surfacing.

## F. Artifacts
- Formal proof + repro of A1: `spec/`, `traces/refresh.ndjson`, `repro/test_bug1_concurrent_401.dart`, `confirmed-bugs.md`.
- Upstream analysis: `modeling-brief.md`, `analysis-report.md`.
