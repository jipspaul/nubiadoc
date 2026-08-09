import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cabinet_stats_event.dart';
import 'cabinet_stats_state.dart';

/// Pilotage/statistiques du cabinet (#4153) : KPI de facturation (CA, taux de
/// transformation) + activité par praticien
/// (`GET /v1/cabinet/stats/billing` + `GET /v1/cabinet/stats/activity`).
class CabinetStatsBloc extends Bloc<CabinetStatsEvent, CabinetStatsState>
    with SafeEmitMixin<CabinetStatsState> {
  CabinetStatsBloc({
    required GetCabinetActivityStatsUseCase getActivityStats,
    required GetCabinetBillingStatsUseCase getBillingStats,
  })  : _getActivityStats = getActivityStats,
        _getBillingStats = getBillingStats,
        super(const CabinetStatsLoading()) {
    on<CabinetStatsLoadRequested>(_onLoad);
  }

  final GetCabinetActivityStatsUseCase _getActivityStats;
  final GetCabinetBillingStatsUseCase _getBillingStats;

  Future<void> _onLoad(
    CabinetStatsLoadRequested event,
    Emitter<CabinetStatsState> emit,
  ) async {
    emit(const CabinetStatsLoading());
    final results = await (_getActivityStats(), _getBillingStats()).wait;
    final (activityResult, billingResult) = results;

    // stats/activity est réservé aux praticiens (RBAC #4592) : un 403 y est
    // attendu pour le secrétariat et ne doit pas masquer les KPI de
    // facturation (stats/billing), eux bien accessibles à ce rôle.
    billingResult.fold(
      (failure) => safeEmit(CabinetStatsError(failure.message)),
      (billing) => safeEmit(
        CabinetStatsLoaded(activityResult.getOrElse(() => const []), billing),
      ),
    );
  }
}
