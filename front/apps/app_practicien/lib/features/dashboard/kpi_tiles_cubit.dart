import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

sealed class KpiTilesState extends Equatable {
  const KpiTilesState();

  @override
  List<Object?> get props => [];
}

final class KpiTilesLoading extends KpiTilesState {
  const KpiTilesLoading();
}

final class KpiTilesError extends KpiTilesState {
  final String message;

  const KpiTilesError(this.message);

  @override
  List<Object?> get props => [message];
}

final class KpiTilesLoaded extends KpiTilesState {
  final PractitionerKpis kpis;

  /// `null` = vue agrégée « tous les cabinets ». Sinon, id d'un cabinet de
  /// [PractitionerKpis.byCabinet] dont les compteurs sont affichés seuls.
  final String? selectedCabinetId;

  const KpiTilesLoaded({required this.kpis, this.selectedCabinetId});

  /// Compteurs à afficher : agrégat global, ou tranche d'un seul cabinet si
  /// [selectedCabinetId] pointe vers une entrée de [PractitionerKpis.byCabinet].
  CabinetKpiSummary get displayed {
    final selected = selectedCabinetId;
    if (selected == null) {
      return CabinetKpiSummary(
        cabinetId: '',
        today: kpis.today,
        month: kpis.month,
        appointmentsToday: kpis.appointmentsToday,
        pendingReminders: kpis.pendingReminders,
        occupancyRate: kpis.occupancyRate,
        objectiveTargetCents: kpis.objectiveTargetCents,
        objectiveAchievedPct: kpis.objectiveAchievedPct,
      );
    }
    return kpis.byCabinet.firstWhere(
      (c) => c.cabinetId == selected,
      orElse: () => kpis.byCabinet.first,
    );
  }

  KpiTilesLoaded copyWith({String? selectedCabinetId, bool clearSelection = false}) =>
      KpiTilesLoaded(
        kpis: kpis,
        selectedCabinetId:
            clearSelection ? null : (selectedCabinetId ?? this.selectedCabinetId),
      );

  @override
  List<Object?> get props => [kpis, selectedCabinetId];
}

// ---------------------------------------------------------------------------
// Cubit
// ---------------------------------------------------------------------------

/// Tuiles KPI du dashboard praticien (#7188, DP-F10.c) : CA du mois vs
/// objectif, RDV du jour, rappels en attente, taux d'occupation
/// (`GET /v1/me/kpis`, #7189). [selectCabinet] bascule l'affichage entre
/// l'agrégat de tous les cabinets et un cabinet précis pour les praticiens
/// multi-cabinet ([PractitionerKpis.byCabinet]).
class KpiTilesCubit extends Cubit<KpiTilesState> {
  KpiTilesCubit({required GetMyKpisUseCase getMyKpis})
      : _getMyKpis = getMyKpis,
        super(const KpiTilesLoading());

  final GetMyKpisUseCase _getMyKpis;

  Future<void> load() async {
    emit(const KpiTilesLoading());
    final result = await _getMyKpis();
    result.fold(
      (failure) => emit(KpiTilesError(failure.message)),
      (kpis) => emit(KpiTilesLoaded(kpis: kpis)),
    );
  }

  void selectCabinet(String? cabinetId) {
    final current = state;
    if (current is! KpiTilesLoaded) return;
    emit(cabinetId == null
        ? current.copyWith(clearSelection: true)
        : current.copyWith(selectedCabinetId: cabinetId));
  }
}
