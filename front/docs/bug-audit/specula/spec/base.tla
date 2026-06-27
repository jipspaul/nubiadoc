-------------------------------- MODULE base --------------------------------
(***************************************************************************)
(* Base spec for Nubia Flutter front — Bug Family 1:                        *)
(* "Concurrent-401 refresh drops in-flight requests (no wait-queue)".       *)
(*                                                                          *)
(* Models AuthInterceptor.onError                                          *)
(*   front/packages/nubia_core/lib/src/network/auth_interceptor.dart:34-99 *)
(*                                                                          *)
(* Category B (concurrent / runtime). Dart is single-threaded but every    *)
(* `await` is an interleaving point. Several Dio requests share ONE         *)
(* singleton AuthInterceptor (DI: injection.dart:24-27). The interceptor    *)
(* serializes refresh with a bare bool `_isRefreshing`; sibling 401s that   *)
(* arrive while a refresh is in flight are failed outright instead of being *)
(* queued and retried under the refreshed token.                           *)
(*                                                                          *)
(* The modeled interleaving window is the `await refreshDio.post(...)`      *)
(* between `_isRefreshing = true` (line 54) and the finally reset (line 97).*)
(* Actions are split exactly at that await so TLC explores every order      *)
(* across it (base-spec-methodology "Granularity for Concurrent Specs").    *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Requests        \* set of model request ids, e.g. {r1, r2, r3}

VARIABLES
    reqPhase,       \* [Requests -> Phase]  per-request progress
    refreshing,     \* BOOLEAN — the interceptor's _isRefreshing flag (line 12)
    refreshDone     \* {"none","ok","fail"} — outcome of the current refresh cycle

vars == <<reqPhase, refreshing, refreshDone>>

(***************************************************************************)
(* Request phases.                                                         *)
(*   inflight   : sent with the (expired) access token, awaiting response  *)
(*   got401     : server returned 401 (onError entered, line 35)           *)
(*   refreshing : this request won the guard and drives the refresh POST   *)
(*   retried_ok : request resolved via handler.resolve after refresh (92)  *)
(*   dropped    : *** BUG outcome *** failed via the _isRefreshing guard    *)
(*                (handler.next(err), lines 49-52) without waiting for the  *)
(*                in-flight refresh                                         *)
(*   failed     : legitimately failed (refresh genuinely failed / no token)*)
(***************************************************************************)
TerminalPhases == {"retried_ok", "dropped", "failed"}
Phase == {"inflight", "got401", "refreshing"} \union TerminalPhases

TypeOK ==
    /\ reqPhase \in [Requests -> Phase]
    /\ refreshing \in BOOLEAN
    /\ refreshDone \in {"none", "ok", "fail"}

Init ==
    /\ reqPhase = [r \in Requests |-> "inflight"]
    /\ refreshing = FALSE
    /\ refreshDone = "none"

(***************************************************************************)
(* Recv401(r): request sent with the expired token → server replies 401.  *)
(* Entry into onError with statusCode == 401 on a non-refresh path         *)
(* (auth_interceptor.dart:39-46).                                          *)
(***************************************************************************)
Recv401(r) ==
    /\ reqPhase[r] = "inflight"
    /\ reqPhase' = [reqPhase EXCEPT ![r] = "got401"]
    /\ UNCHANGED <<refreshing, refreshDone>>

(***************************************************************************)
(* BeginRefresh(r): the first 401 finds `_isRefreshing == false`          *)
(* (line 49 false), sets it true (line 54), starts the refresh POST (67).  *)
(* Single refresh cycle: guard refreshDone = "none".                       *)
(***************************************************************************)
BeginRefresh(r) ==
    /\ reqPhase[r] = "got401"
    /\ ~refreshing                       \* line 49: if (_isRefreshing) ... skipped
    /\ refreshDone = "none"
    /\ refreshing' = TRUE                 \* line 54: _isRefreshing = true
    /\ reqPhase' = [reqPhase EXCEPT ![r] = "refreshing"]
    /\ UNCHANGED refreshDone

(***************************************************************************)
(* DropWhileRefreshing(r): a sibling 401 arrives while `_isRefreshing` is  *)
(* true → handler.next(err); return (lines 49-52). *** THE BUG *** the     *)
(* request fails and is never retried under the refreshed token.           *)
(***************************************************************************)
DropWhileRefreshing(r) ==
    /\ reqPhase[r] = "got401"
    /\ refreshing                        \* line 49: if (_isRefreshing) true
    /\ reqPhase' = [reqPhase EXCEPT ![r] = "dropped"]  \* line 50: handler.next(err)
    /\ UNCHANGED <<refreshing, refreshDone>>

(***************************************************************************)
(* RefreshSucceed(r): await completes 200 with both tokens. saveTokens     *)
(* (81), retry with new bearer + handler.resolve (87-92), finally reset    *)
(* _isRefreshing (97).                                                     *)
(***************************************************************************)
RefreshSucceed(r) ==
    /\ reqPhase[r] = "refreshing"
    /\ refreshDone = "none"
    /\ refreshDone' = "ok"
    /\ refreshing' = FALSE                \* line 97: finally _isRefreshing = false
    /\ reqPhase' = [reqPhase EXCEPT ![r] = "retried_ok"]

(***************************************************************************)
(* RefreshFail(r): refresh POST throws (DioException) or returns without   *)
(* tokens (75). clearTokens + handler.next(err) (75-79 / 93-95), finally   *)
(* reset (97).                                                             *)
(***************************************************************************)
RefreshFail(r) ==
    /\ reqPhase[r] = "refreshing"
    /\ refreshDone = "none"
    /\ refreshDone' = "fail"
    /\ refreshing' = FALSE
    /\ reqPhase' = [reqPhase EXCEPT ![r] = "failed"]

(***************************************************************************)
(* RetryAfterRefresh(r): a request still holding a 401 after the refresh   *)
(* SUCCEEDED and the flag is clear again. A later onError finds            *)
(* ~refreshing and recovers — modeled as favorable resolution.            *)
(***************************************************************************)
RetryAfterRefresh(r) ==
    /\ reqPhase[r] = "got401"
    /\ ~refreshing
    /\ refreshDone = "ok"
    /\ reqPhase' = [reqPhase EXCEPT ![r] = "retried_ok"]
    /\ UNCHANGED <<refreshing, refreshDone>>

(***************************************************************************)
(* CleanupAfterFail(r): the refresh failed and cleared the tokens. A       *)
(* leftover 401 re-enters onError, BeginRefresh path, getRefreshToken()    *)
(* == null (lines 56-57) → clearTokens + handler.next(err) → fails         *)
(* legitimately (it would fail regardless of the lost-retry bug).          *)
(***************************************************************************)
CleanupAfterFail(r) ==
    /\ reqPhase[r] = "got401"
    /\ ~refreshing
    /\ refreshDone = "fail"
    /\ reqPhase' = [reqPhase EXCEPT ![r] = "failed"]
    /\ UNCHANGED <<refreshing, refreshDone>>

\* Terminal self-loop: once every request reached a terminal phase, allow a
\* stutter so TLC does not report a spurious deadlock on the (legitimate) end.
Terminated == \A r \in Requests : reqPhase[r] \in TerminalPhases
TerminalStutter == Terminated /\ UNCHANGED vars

Next ==
    \/ \E r \in Requests :
        \/ Recv401(r)
        \/ BeginRefresh(r)
        \/ DropWhileRefreshing(r)
        \/ RefreshSucceed(r)
        \/ RefreshFail(r)
        \/ RetryAfterRefresh(r)
        \/ CleanupAfterFail(r)
    \/ TerminalStutter

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

(***************************************************************************)
(* Invariants                                                              *)
(***************************************************************************)

\* Structural: the _isRefreshing guard must give mutual exclusion — at most
\* one request in the refresh critical section. EXPECTED TO HOLD (no `await`
\* between the check on line 49 and the set on line 54, so check-then-set is
\* atomic in Dart).
SingleRefreshInFlight ==
    Cardinality({r \in Requests : reqPhase[r] = "refreshing"}) <= 1

\* Bug-family invariant (brief §5 NoLostRetry). If the in-flight refresh
\* SUCCEEDED, then no request was dropped: each 401'd request should have
\* been retried under the new token. EXPECTED TO FAIL — DropWhileRefreshing
\* drops siblings while the racing refresh later succeeds.
NoLostRetry ==
    (refreshDone = "ok") => (\A r \in Requests : reqPhase[r] # "dropped")

\* Liveness: every request eventually leaves the inflight/got401 limbo.
EventuallyDone == <>Terminated

=============================================================================
