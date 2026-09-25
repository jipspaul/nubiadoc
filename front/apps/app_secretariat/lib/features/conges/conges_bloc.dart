import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'conges_event.dart';
import 'conges_state.dart';

/// Validation des demandes de congé du cabinet (#7143/#7144) : file
/// d'attente, approbation/refus. `decide` est réservé admin/manager côté
/// back — un 403 (secrétaire simple) est affiché en erreur d'action plutôt
/// que de bloquer tout l'écran (la liste elle-même reste consultable par
/// tout rôle pro).
class CongesBloc extends Bloc<CongesEvent, CongesState>
    with SafeEmitMixin<CongesState> {
  CongesBloc({
    required ListLeaveRequestsUseCase listLeaveRequests,
    required DecideLeaveRequestUseCase decideLeaveRequest,
  })  : _listLeaveRequests = listLeaveRequests,
        _decideLeaveRequest = decideLeaveRequest,
        super(const CongesLoading()) {
    on<CongesLoadRequested>(_onLoad);
    on<CongesDecideRequested>(_onDecide);
  }

  final ListLeaveRequestsUseCase _listLeaveRequests;
  final DecideLeaveRequestUseCase _decideLeaveRequest;

  Future<void> _onLoad(
    CongesLoadRequested event,
    Emitter<CongesState> emit,
  ) async {
    emit(const CongesLoading());
    final result = await _listLeaveRequests(status: event.status);
    result.fold(
      (failure) => safeEmit(CongesError(failure.message)),
      (requests) => safeEmit(CongesLoaded(
        requests: requests,
        status: event.status,
      )),
    );
  }

  Future<void> _onDecide(
    CongesDecideRequested event,
    Emitter<CongesState> emit,
  ) async {
    final current = state;
    if (current is! CongesLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _decideLeaveRequest(
      id: event.leaveRequestId,
      approve: event.approve,
    );
    result.fold(
      (failure) => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => add(CongesLoadRequested(status: current.status)),
    );
  }
}
