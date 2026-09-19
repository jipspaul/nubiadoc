import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class CorrespondentStatsState extends Equatable {
  const CorrespondentStatsState();
}

class CorrespondentStatsLoading extends CorrespondentStatsState {
  const CorrespondentStatsLoading();

  @override
  List<Object?> get props => [];
}

class CorrespondentStatsError extends CorrespondentStatsState {
  const CorrespondentStatsError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class CorrespondentStatsLoaded extends CorrespondentStatsState {
  const CorrespondentStatsLoaded({required this.stats});

  final CorrespondentStats stats;

  @override
  List<Object?> get props => [stats];
}

/// Stats d'un correspondant (#7193), affichées dans sa fiche —
/// chargement indépendant de [CorrespondentsBloc], même découpage que
/// `CashCollectionCubit` (dashboard) : la donnée n'a pas de source commune
/// avec la liste déjà chargée.
class CorrespondentStatsCubit extends Cubit<CorrespondentStatsState>
    with SafeEmitMixin<CorrespondentStatsState> {
  CorrespondentStatsCubit({required GetCorrespondentStatsUseCase getStats})
      : _getStats = getStats,
        super(const CorrespondentStatsLoading());

  final GetCorrespondentStatsUseCase _getStats;

  Future<void> load(String correspondentId) async {
    safeEmit(const CorrespondentStatsLoading());
    final result = await _getStats(correspondentId);
    result.fold(
      (failure) => safeEmit(CorrespondentStatsError(message: failure.message)),
      (stats) => safeEmit(CorrespondentStatsLoaded(stats: stats)),
    );
  }
}
