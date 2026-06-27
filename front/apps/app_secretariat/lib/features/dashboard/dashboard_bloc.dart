import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';

import 'dashboard_event.dart';
import 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState>
    with SafeEmitMixin<DashboardState> {
  DashboardBloc() : super(const DashboardInitial()) {
    on<DashboardLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    DashboardLoadRequested event,
    Emitter<DashboardState> emit,
  ) async {
    emit(const DashboardLoading());
    try {
      emit(
        const DashboardLoaded(
          todayCount: 0,
          pendingCount: 0,
          waitingCount: 0,
        ),
      );
    } catch (_) {
      emit(
        const DashboardError(
          message: 'Impossible de charger le tableau de bord.',
        ),
      );
    }
  }
}
