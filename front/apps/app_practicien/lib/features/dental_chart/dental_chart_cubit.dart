//! Cubit de l'écran de schéma dentaire interactif (#4047).
//!
//! Quoi : charge l'odontogramme (`GET .../dental-chart`), permet des
//! modifications locales dent-par-dent (`setToothStatus`), et les persiste
//! d'un coup via `save()` — le PUT est un remplacement atomique de
//! `teeth_status` côté API (`api/src/dental_chart.rs`), pas un patch dent
//! par dent : sauvegarder à chaque tap multiplierait les PUT complets pour
//! rien et risquerait des écrasements concurrents entre onglets.
//!
//! Modes d'échec : erreur de chargement → `DentalChartError` (bouton
//! réessayer). Erreur de sauvegarde → `saveError` sur l'état `Loaded`
//! (les modifications locales restent visibles, pas de perte de saisie).

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class DentalChartState extends Equatable {
  const DentalChartState();

  @override
  List<Object?> get props => [];
}

class DentalChartLoading extends DentalChartState {
  const DentalChartLoading();
}

class DentalChartError extends DentalChartState {
  const DentalChartError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

class DentalChartLoaded extends DentalChartState {
  const DentalChartLoaded({
    required this.teeth,
    this.dirty = false,
    this.saving = false,
    this.saveError,
  });

  final Map<String, ToothState> teeth;
  final bool dirty;
  final bool saving;
  final String? saveError;

  DentalChartLoaded copyWith({
    Map<String, ToothState>? teeth,
    bool? dirty,
    bool? saving,
    String? saveError,
    bool clearSaveError = false,
  }) =>
      DentalChartLoaded(
        teeth: teeth ?? this.teeth,
        dirty: dirty ?? this.dirty,
        saving: saving ?? this.saving,
        saveError: clearSaveError ? null : (saveError ?? this.saveError),
      );

  @override
  List<Object?> get props => [teeth, dirty, saving, saveError];
}

class DentalChartCubit extends Cubit<DentalChartState> {
  DentalChartCubit({
    required this.patientId,
    required GetDentalChartUseCase getDentalChart,
    required PutDentalChartUseCase putDentalChart,
  })  : _get = getDentalChart,
        _put = putDentalChart,
        super(const DentalChartLoading()) {
    load();
  }

  final String patientId;
  final GetDentalChartUseCase _get;
  final PutDentalChartUseCase _put;

  Future<void> load() async {
    emit(const DentalChartLoading());
    final result = await _get(patientId);
    result.fold(
      (failure) => emit(DentalChartError(failure.message)),
      (chart) => emit(DentalChartLoaded(teeth: chart.teeth)),
    );
  }

  /// Modification locale (pas de PUT immédiat — voir doc de module).
  void setToothStatus(String toothCode, String status) {
    final current = state;
    if (current is! DentalChartLoaded) return;
    final updated = Map<String, ToothState>.from(current.teeth);
    updated[toothCode] = ToothState(status: status);
    emit(current.copyWith(teeth: updated, dirty: true, clearSaveError: true));
  }

  Future<void> save() async {
    final current = state;
    if (current is! DentalChartLoaded) return;
    emit(current.copyWith(saving: true, clearSaveError: true));
    final result = await _put(patientId, current.teeth);
    result.fold(
      (failure) => emit(
        current.copyWith(saving: false, saveError: failure.message),
      ),
      (chart) => emit(DentalChartLoaded(teeth: chart.teeth)),
    );
  }
}
