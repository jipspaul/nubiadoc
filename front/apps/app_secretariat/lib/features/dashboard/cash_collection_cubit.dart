import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class CashCollectionState extends Equatable {
  const CashCollectionState();
}

class CashCollectionLoading extends CashCollectionState {
  const CashCollectionLoading();

  @override
  List<Object?> get props => [];
}

class CashCollectionError extends CashCollectionState {
  const CashCollectionError({required this.message});

  final String message;

  @override
  List<Object?> get props => [message];
}

class CashCollectionLoaded extends CashCollectionState {
  const CashCollectionLoaded({required this.summary});

  final CashCollectionSummary summary;

  @override
  List<Object?> get props => [summary];
}

/// Carte « Encaissements du jour » (#5382) : encaissé aujourd'hui, reste à
/// encaisser avant la fermeture, impayés du cabinet. Chargement indépendant
/// du `DashboardBloc` — même découpage que `RailBadgesCubit`, la donnée
/// n'a pas de source commune avec l'agenda déjà chargé par le tableau de
/// bord.
class CashCollectionCubit extends Cubit<CashCollectionState>
    with SafeEmitMixin<CashCollectionState> {
  CashCollectionCubit({required GetCashCollectionSummaryUseCase getSummary})
      : _getSummary = getSummary,
        super(const CashCollectionLoading());

  final GetCashCollectionSummaryUseCase _getSummary;

  Future<void> load() async {
    safeEmit(const CashCollectionLoading());
    final result = await _getSummary();
    result.fold(
      (failure) => safeEmit(CashCollectionError(message: failure.message)),
      (summary) => safeEmit(CashCollectionLoaded(summary: summary)),
    );
  }
}
