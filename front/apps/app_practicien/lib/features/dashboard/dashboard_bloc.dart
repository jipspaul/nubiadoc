import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'dashboard_event.dart';
import 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final GetProDashboardSummaryUseCase _getSummary;
  final StartConsultationUseCase _startConsultation;
  final String? _practitionerId;

  DashboardBloc({
    required GetProDashboardSummaryUseCase getSummary,
    required StartConsultationUseCase startConsultation,
    String? practitionerId,
  })  : _getSummary = getSummary,
        _startConsultation = startConsultation,
        _practitionerId = practitionerId,
        super(const DashboardInitial()) {
    on<DashboardLoadRequested>(_onLoad);
    on<DashboardConsultationStartRequested>(_onStartConsultation);
    on<DashboardStartedConsultationConsumed>((event, emit) {
      final current = state;
      if (current is DashboardLoaded) {
        emit(current.copyWith(clearStartedConsultation: true));
      }
    });
  }

  Future<void> _onLoad(
    DashboardLoadRequested event,
    Emitter<DashboardState> emit,
  ) async {
    emit(const DashboardLoading());
    try {
      final result = await _getSummary(practitionerId: _practitionerId);
      result.fold(
        (failure) => emit(DashboardError(failure.message)),
        (summary) => emit(DashboardLoaded(summary)),
      );
    } catch (_) {
      emit(const DashboardError('Erreur de chargement.'));
    }
  }

  Future<void> _onStartConsultation(
    DashboardConsultationStartRequested event,
    Emitter<DashboardState> emit,
  ) async {
    final current = state;
    if (current is! DashboardLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _startConsultation(event.appointmentId);
      result.fold(
        (failure) => emit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        // La session démarrée est propagée au state : la page navigue vers
        // /consultation?id=… (#6241, même correctif que #3367 côté agenda).
        (session) => emit(current.copyWith(
          actionInProgress: false,
          startedConsultationId: session.id,
        )),
      );
    } catch (_) {
      emit(current.copyWith(
        actionInProgress: false,
        actionError: 'Erreur inattendue.',
      ));
    }
  }
}
