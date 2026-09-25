import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'mes_conges_event.dart';
import 'mes_conges_state.dart';

/// Mes demandes de congé (#7143/#7144) : demande depuis le téléphone,
/// suivi du statut (`pending`/`approved`/`rejected`/`cancelled`),
/// annulation tant que la demande n'est pas décidée définitivement.
class MesCongesBloc extends Bloc<MesCongesEvent, MesCongesState>
    with SafeEmitMixin<MesCongesState> {
  MesCongesBloc({
    required ListLeaveRequestsUseCase listLeaveRequests,
    required CreateLeaveRequestUseCase createLeaveRequest,
    required CancelLeaveRequestUseCase cancelLeaveRequest,
  })  : _listLeaveRequests = listLeaveRequests,
        _createLeaveRequest = createLeaveRequest,
        _cancelLeaveRequest = cancelLeaveRequest,
        super(const MesCongesLoading()) {
    on<MesCongesLoadRequested>(_onLoad);
    on<MesCongesCreateRequested>(_onCreate);
    on<MesCongesCancelRequested>(_onCancel);
  }

  final ListLeaveRequestsUseCase _listLeaveRequests;
  final CreateLeaveRequestUseCase _createLeaveRequest;
  final CancelLeaveRequestUseCase _cancelLeaveRequest;

  Future<void> _onLoad(
    MesCongesLoadRequested event,
    Emitter<MesCongesState> emit,
  ) async {
    emit(const MesCongesLoading());
    final result = await _listLeaveRequests(
      userId: event.userId,
      status: event.status,
    );
    result.fold(
      (failure) => safeEmit(MesCongesError(failure.message)),
      (requests) => safeEmit(MesCongesLoaded(
        requests: requests,
        userId: event.userId,
        status: event.status,
      )),
    );
  }

  Future<void> _onCreate(
    MesCongesCreateRequested event,
    Emitter<MesCongesState> emit,
  ) async {
    final current = state;
    if (current is! MesCongesLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _createLeaveRequest(
      startsAt: event.startsAt,
      endsAt: event.endsAt,
      kind: event.kind,
    );
    result.fold(
      (failure) => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => add(MesCongesLoadRequested(
        userId: current.userId,
        status: current.status,
      )),
    );
  }

  Future<void> _onCancel(
    MesCongesCancelRequested event,
    Emitter<MesCongesState> emit,
  ) async {
    final current = state;
    if (current is! MesCongesLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _cancelLeaveRequest(event.leaveRequestId);
    result.fold(
      (failure) => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => add(MesCongesLoadRequested(
        userId: current.userId,
        status: current.status,
      )),
    );
  }
}
