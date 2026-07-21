//! Cubit de l'écran de saisie du bilan parodontal (#4106).
//!
//! Quoi : charge le dernier bilan (`GET .../periodontal-chart`), permet des
//! modifications locales (profondeurs de sondage par dent, indices libres),
//! et les persiste d'un coup via `save()` — le PUT crée toujours un nouveau
//! bilan côté API (`api/src/periodontal_chart.rs`, pas d'upsert, voir #4105),
//! donc sauvegarder à chaque frappe créerait un historique inutilisable.
//!
//! Modes d'échec : erreur de chargement → `PeriodontalChartError` (bouton
//! réessayer). Erreur de sauvegarde → `saveError` sur l'état `Loaded` (les
//! modifications locales restent visibles, pas de perte de saisie).

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class PeriodontalChartState extends Equatable {
  const PeriodontalChartState();

  @override
  List<Object?> get props => [];
}

class PeriodontalChartLoading extends PeriodontalChartState {
  const PeriodontalChartLoading();
}

class PeriodontalChartError extends PeriodontalChartState {
  const PeriodontalChartError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

class PeriodontalChartLoaded extends PeriodontalChartState {
  const PeriodontalChartLoaded({
    required this.sites,
    required this.indices,
    this.dirty = false,
    this.saving = false,
    this.saveError,
  });

  final Map<String, ToothSiteDepths> sites;
  final Map<String, double> indices;
  final bool dirty;
  final bool saving;
  final String? saveError;

  PeriodontalChartLoaded copyWith({
    Map<String, ToothSiteDepths>? sites,
    Map<String, double>? indices,
    bool? dirty,
    bool? saving,
    String? saveError,
    bool clearSaveError = false,
  }) =>
      PeriodontalChartLoaded(
        sites: sites ?? this.sites,
        indices: indices ?? this.indices,
        dirty: dirty ?? this.dirty,
        saving: saving ?? this.saving,
        saveError: clearSaveError ? null : (saveError ?? this.saveError),
      );

  @override
  List<Object?> get props => [sites, indices, dirty, saving, saveError];
}

class PeriodontalChartCubit extends Cubit<PeriodontalChartState> {
  PeriodontalChartCubit({
    required this.patientId,
    required GetPeriodontalChartUseCase getPeriodontalChart,
    required PutPeriodontalChartUseCase putPeriodontalChart,
  })  : _get = getPeriodontalChart,
        _put = putPeriodontalChart,
        super(const PeriodontalChartLoading()) {
    load();
  }

  final String patientId;
  final GetPeriodontalChartUseCase _get;
  final PutPeriodontalChartUseCase _put;

  Future<void> load() async {
    emit(const PeriodontalChartLoading());
    final result = await _get(patientId);
    result.fold(
      (failure) => emit(PeriodontalChartError(failure.message)),
      (chart) => emit(
        PeriodontalChartLoaded(sites: chart.sites, indices: chart.indices),
      ),
    );
  }

  /// Modification locale (pas de PUT immédiat — voir doc de module).
  void setToothSite(String toothCode, ToothSiteDepths depths) {
    final current = state;
    if (current is! PeriodontalChartLoaded) return;
    final updated = Map<String, ToothSiteDepths>.from(current.sites);
    updated[toothCode] = depths;
    emit(current.copyWith(sites: updated, dirty: true, clearSaveError: true));
  }

  void setIndex(String name, double value) {
    final current = state;
    if (current is! PeriodontalChartLoaded) return;
    final updated = Map<String, double>.from(current.indices);
    updated[name] = value;
    emit(
      current.copyWith(indices: updated, dirty: true, clearSaveError: true),
    );
  }

  void removeIndex(String name) {
    final current = state;
    if (current is! PeriodontalChartLoaded) return;
    final updated = Map<String, double>.from(current.indices)..remove(name);
    emit(
      current.copyWith(indices: updated, dirty: true, clearSaveError: true),
    );
  }

  Future<void> save() async {
    final current = state;
    if (current is! PeriodontalChartLoaded) return;
    emit(current.copyWith(saving: true, clearSaveError: true));
    final result = await _put(patientId, current.sites, current.indices);
    result.fold(
      (failure) => emit(
        current.copyWith(saving: false, saveError: failure.message),
      ),
      (chart) => emit(
        PeriodontalChartLoaded(sites: chart.sites, indices: chart.indices),
      ),
    );
  }
}
