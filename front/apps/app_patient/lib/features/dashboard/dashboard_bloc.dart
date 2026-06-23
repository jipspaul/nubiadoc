import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'dashboard_event.dart';
import 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final GetDashboardSummaryUseCase _getSummary;

  DashboardBloc({required GetDashboardSummaryUseCase getDashboardSummary})
      : _getSummary = getDashboardSummary,
        super(const DashboardInitial()) {
    on<DashboardLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    DashboardLoadRequested event,
    Emitter<DashboardState> emit,
  ) async {
    emit(const DashboardLoading());
    try {
      final result = await _getSummary();
      result.fold(
        (failure) => emit(DashboardError(failure.message)),
        (summary) => emit(DashboardLoaded(summary)),
      );
    } catch (_) {
      emit(const DashboardError('Erreur de chargement.'));
    }
  }
}
