import 'package:bloc/bloc.dart';

import 'dashboard_event.dart';
import 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  DashboardBloc() : super(const DashboardInitial()) {
    on<DashboardLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    DashboardLoadRequested event,
    Emitter<DashboardState> emit,
  ) async {
    emit(const DashboardLoading());
    // Stub counts — will be wired to API (agenda/appointments/waiting-list) in a future iteration
    emit(const DashboardLoaded(todayCount: 0, pendingCount: 0, waitingCount: 0));
  }
}
