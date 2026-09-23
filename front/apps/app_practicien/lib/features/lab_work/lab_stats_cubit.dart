import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class LabStatsState extends Equatable {
  const LabStatsState();

  @override
  List<Object?> get props => [];
}

final class LabStatsLoading extends LabStatsState {
  const LabStatsLoading();
}

final class LabStatsError extends LabStatsState {
  final String message;

  const LabStatsError(this.message);

  @override
  List<Object?> get props => [message];
}

final class LabStatsLoaded extends LabStatsState {
  final LabStats stats;

  const LabStatsLoaded(this.stats);

  @override
  List<Object?> get props => [stats];
}

/// Écran « Stats labos » (#7163, DP-F19.c) : coût labo / CA patient / marge
/// agrégés sur le mois courant, par laboratoire et par praticien. Source :
/// `GET /v1/cabinet/lab-stats`.
class LabStatsCubit extends Cubit<LabStatsState> {
  LabStatsCubit({required GetCabinetLabStatsUseCase getLabStats})
      : _getLabStats = getLabStats,
        super(const LabStatsLoading());

  final GetCabinetLabStatsUseCase _getLabStats;

  Future<void> load() async {
    emit(const LabStatsLoading());
    final result = await _getLabStats();
    result.fold(
      (failure) => emit(LabStatsError(failure.message)),
      (stats) => emit(LabStatsLoaded(stats)),
    );
  }
}
