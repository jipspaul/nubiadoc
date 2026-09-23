import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class LabMarginState extends Equatable {
  const LabMarginState();

  @override
  List<Object?> get props => [];
}

final class LabMarginLoading extends LabMarginState {
  const LabMarginLoading();
}

final class LabMarginError extends LabMarginState {
  final String message;

  const LabMarginError(this.message);

  @override
  List<Object?> get props => [message];
}

final class LabMarginLoaded extends LabMarginState {
  /// `LabStatActItem.labWorkOrderId` → coût/CA/marge du bon, pour le mois
  /// courant (`GET /v1/cabinet/lab-stats`). Un bon absent de la map (hors
  /// mois courant, ou envoyé un autre mois) n'affiche simplement pas de
  /// marge sur sa carte — ce n'est pas une erreur.
  final Map<String, LabStatActItem> byOrderId;

  const LabMarginLoaded(this.byOrderId);

  @override
  List<Object?> get props => [byOrderId];
}

/// Coût / CA patient / marge par bon de travail, mois courant (#7163,
/// DP-F19.c) — chargé indépendamment de `LabWorkOrdersBloc` (liste des bons)
/// pour ne pas coupler la latence/l'échec de `GET /v1/cabinet/lab-stats` au
/// premier affichage de la liste (#5067) : un échec ici masque juste la
/// marge, sans `NubiaErrorWidget` ni snackbar.
class LabMarginCubit extends Cubit<LabMarginState> {
  LabMarginCubit({required GetCabinetLabStatsUseCase getLabStats})
      : _getLabStats = getLabStats,
        super(const LabMarginLoading());

  final GetCabinetLabStatsUseCase _getLabStats;

  Future<void> load() async {
    emit(const LabMarginLoading());
    final result = await _getLabStats();
    result.fold(
      (failure) => emit(LabMarginError(failure.message)),
      (stats) => emit(LabMarginLoaded({
        for (final item in stats.byAct) item.labWorkOrderId: item,
      })),
    );
  }
}
