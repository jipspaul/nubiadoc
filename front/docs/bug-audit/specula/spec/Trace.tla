------------------------------- MODULE Trace -------------------------------
(***************************************************************************)
(* Trace-validation spec for Bug Family 1.                                 *)
(*                                                                          *)
(* Although requests interleave at `await` points, the Dart event loop is  *)
(* single-threaded: every AuthInterceptor callback runs to its next await   *)
(* as one microtask, so the *observable* sequence of interceptor events is  *)
(* a single total order. We therefore use the Category-A single-cursor      *)
(* trace pattern: the harness logs one NDJSON event per base-spec action,   *)
(* in event-loop order, and this spec replays them against base.tla.        *)
(*                                                                          *)
(* Each event: { tag, action, req, refreshing, refreshDone, phase }        *)
(*   action      : Recv401 | BeginRefresh | DropWhileRefreshing |           *)
(*                 RefreshSucceed | RefreshFail | RetryAfterRefresh         *)
(*   req         : request id string                                       *)
(*   refreshing  : interceptor _isRefreshing AFTER the step                 *)
(*   refreshDone : "none" | "ok" | "fail" AFTER the step                    *)
(*   phase       : reqPhase[req] AFTER the step                             *)
(***************************************************************************)
EXTENDS base, Sequences, TLC, Json, IOUtils, Naturals

\* Trace file: default sibling traces/ dir; override per-run with -DJSON.
JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/refresh.ndjson"

TraceLog == ndJsonDeserialize(JsonFile)

VARIABLE l            \* cursor into TraceLog (1-based)
TraceVars == <<vars, l>>

logline == TraceLog[l]

\* ------- Event helpers -------
IsAction(name) == l <= Len(TraceLog) /\ logline.action = name
EventReq       == logline.req

\* ------- Post-state validation (MANDATORY) -------
\* After firing the base action, the spec's post-state must equal what the
\* implementation logged. We validate every field the harness captures.
ValidatePostState ==
    /\ reqPhase'[EventReq] = logline.phase
    /\ refreshing'         = logline.refreshing
    /\ refreshDone'        = logline.refreshDone

\* ------- Action wrappers: match event -> base action -> validate -> advance
W_Recv401 ==
    /\ IsAction("Recv401")
    /\ Recv401(EventReq)
    /\ ValidatePostState
    /\ l' = l + 1

W_BeginRefresh ==
    /\ IsAction("BeginRefresh")
    /\ BeginRefresh(EventReq)
    /\ ValidatePostState
    /\ l' = l + 1

W_DropWhileRefreshing ==
    /\ IsAction("DropWhileRefreshing")
    /\ DropWhileRefreshing(EventReq)
    /\ ValidatePostState
    /\ l' = l + 1

W_RefreshSucceed ==
    /\ IsAction("RefreshSucceed")
    /\ RefreshSucceed(EventReq)
    /\ ValidatePostState
    /\ l' = l + 1

W_RefreshFail ==
    /\ IsAction("RefreshFail")
    /\ RefreshFail(EventReq)
    /\ ValidatePostState
    /\ l' = l + 1

W_RetryAfterRefresh ==
    /\ IsAction("RetryAfterRefresh")
    /\ RetryAfterRefresh(EventReq)
    /\ ValidatePostState
    /\ l' = l + 1

TraceInit ==
    /\ Init
    /\ l = 1

TraceNext ==
    \/ W_Recv401
    \/ W_BeginRefresh
    \/ W_DropWhileRefreshing
    \/ W_RefreshSucceed
    \/ W_RefreshFail
    \/ W_RetryAfterRefresh
    \* terminal stutter once the whole trace is consumed
    \/ /\ l > Len(TraceLog)
       /\ UNCHANGED TraceVars

TraceSpec == TraceInit /\ [][TraceNext]_TraceVars

\* The entire trace must be consumed — guards against silent no-progress.
TraceMatched == <>(l > Len(TraceLog))

=============================================================================
