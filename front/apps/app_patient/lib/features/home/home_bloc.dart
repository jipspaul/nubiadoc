import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'home_event.dart';
import 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState>
    with SafeEmitMixin<HomeState> {
  final GetDashboardSummaryUseCase _getDashboardSummary;

  HomeBloc({required GetDashboardSummaryUseCase getDashboardSummary})
      : _getDashboardSummary = getDashboardSummary,
        super(const HomeInitial()) {
    on<HomeLoadRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
    HomeLoadRequested event,
    Emitter<HomeState> emit,
  ) async {
    emit(const HomeLoading());
    try {
      final result = await _getDashboardSummary();
      result.fold(
        (failure) => safeEmit(HomeError(failure.message)),
        (summary) => safeEmit(HomeLoaded(summary)),
      );
    } catch (_) {
      safeEmit(const HomeError('Erreur de chargement.'));
    }
  }
}
