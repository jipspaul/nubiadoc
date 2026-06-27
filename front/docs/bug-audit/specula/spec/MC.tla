--------------------------------- MODULE MC ---------------------------------
(***************************************************************************)
(* Model-checking wrapper for base (Bug Family 1).                          *)
(*                                                                          *)
(* The only "fault" to bound is RefreshFail — the non-deterministic         *)
(* outcome of the refresh POST (DioException / missing tokens). Everything  *)
(* else is reactive request/interceptor stepping and is left unbounded;     *)
(* the request set itself is the natural finite bound. Symmetry over        *)
(* Requests keeps the state space small.                                    *)
(***************************************************************************)
EXTENDS base, TLC

CONSTANTS MaxRefreshFail

VARIABLES faultVars   \* [ refreshFailCnt |-> Nat ]

MCvars == <<vars, faultVars>>

MCInit ==
    /\ Init
    /\ faultVars = [refreshFailCnt |-> 0]

\* Bounded fault: refresh may fail at most MaxRefreshFail times.
MCRefreshFail(r) ==
    /\ faultVars.refreshFailCnt < MaxRefreshFail
    /\ RefreshFail(r)
    /\ faultVars' = [faultVars EXCEPT !.refreshFailCnt = @ + 1]

\* Reactive / deterministic steps pass through unchanged.
MCRecv401(r)             == Recv401(r)             /\ UNCHANGED faultVars
MCBeginRefresh(r)        == BeginRefresh(r)        /\ UNCHANGED faultVars
MCDropWhileRefreshing(r) == DropWhileRefreshing(r) /\ UNCHANGED faultVars
MCRefreshSucceed(r)      == RefreshSucceed(r)      /\ UNCHANGED faultVars
MCRetryAfterRefresh(r)   == RetryAfterRefresh(r)   /\ UNCHANGED faultVars
MCCleanupAfterFail(r)    == CleanupAfterFail(r)    /\ UNCHANGED faultVars
MCTerminalStutter        == TerminalStutter        /\ UNCHANGED faultVars

MCNext ==
    \/ \E r \in Requests :
        \/ MCRecv401(r)
        \/ MCBeginRefresh(r)
        \/ MCDropWhileRefreshing(r)
        \/ MCRefreshSucceed(r)
        \/ MCRefreshFail(r)
        \/ MCRetryAfterRefresh(r)
        \/ MCCleanupAfterFail(r)
    \/ MCTerminalStutter

MCSpec == MCInit /\ [][MCNext]_MCvars /\ WF_MCvars(MCNext)

\* Symmetry: requests are interchangeable.
Symmetry == Permutations(Requests)

\* Exclude the fault counter from the liveness/footprint view.
View == vars

=============================================================================
