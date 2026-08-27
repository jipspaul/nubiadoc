//! Cubit de l'écran plans de traitement (#4051).
//!
//! Quoi : charge les plans d'un patient (avec leurs phases imbriquées,
//! `GET .../treatment-plans`), permet d'en créer un (`createPlan`) et
//! d'ajouter une phase à un plan existant (`createPhase`). Chaque création
//! recharge la liste complète depuis le serveur plutôt que de fusionner
//! localement — la réponse `GET` fait déjà autorité côté tri (phases par
//! `position`), pas la peine de dupliquer cette logique côté client.
//!
//! Modes d'échec : erreur de chargement → `TreatmentPlansError` (bouton
//! réessayer). Erreur de création (plan/phase) → `actionError` sur l'état
//! `Loaded`, la liste déjà chargée reste affichée.

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class TreatmentPlansState extends Equatable {
  const TreatmentPlansState();

  @override
  List<Object?> get props => [];
}

class TreatmentPlansLoading extends TreatmentPlansState {
  const TreatmentPlansLoading();
}

class TreatmentPlansError extends TreatmentPlansState {
  const TreatmentPlansError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

class TreatmentPlansLoaded extends TreatmentPlansState {
  const TreatmentPlansLoaded({
    required this.plans,
    this.busy = false,
    this.actionError,
  });

  final List<TreatmentPlan> plans;
  final bool busy;
  final String? actionError;

  TreatmentPlansLoaded copyWith({
    List<TreatmentPlan>? plans,
    bool? busy,
    String? actionError,
    bool clearActionError = false,
  }) =>
      TreatmentPlansLoaded(
        plans: plans ?? this.plans,
        busy: busy ?? this.busy,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  @override
  List<Object?> get props => [plans, busy, actionError];
}

class TreatmentPlansCubit extends Cubit<TreatmentPlansState> {
  TreatmentPlansCubit({
    required this.patientId,
    required ListTreatmentPlansUseCase listPlans,
    required CreateTreatmentPlanUseCase createPlan,
    required CreateTreatmentPhaseUseCase createPhase,
  })  : _list = listPlans,
        _create = createPlan,
        _createPhase = createPhase,
        super(const TreatmentPlansLoading()) {
    load();
  }

  final String patientId;
  final ListTreatmentPlansUseCase _list;
  final CreateTreatmentPlanUseCase _create;
  final CreateTreatmentPhaseUseCase _createPhase;

  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner) emit(const TreatmentPlansLoading());
    final result = await _list(patientId);
    result.fold(
      (failure) => emit(TreatmentPlansError(failure.message)),
      (plans) => emit(TreatmentPlansLoaded(plans: plans)),
    );
  }

  Future<void> createPlan(String title) async {
    final current = state;
    if (current is! TreatmentPlansLoaded) return;
    emit(current.copyWith(busy: true, clearActionError: true));
    final result = await _create(patientId, title);
    await result.fold(
      (failure) async =>
          emit(current.copyWith(busy: false, actionError: failure.message)),
      (_) => load(showSpinner: false),
    );
  }

  Future<void> createPhase(String planId, String title, int position) async {
    final current = state;
    if (current is! TreatmentPlansLoaded) return;
    emit(current.copyWith(busy: true, clearActionError: true));
    final result = await _createPhase(planId, title, position);
    await result.fold(
      (failure) async =>
          emit(current.copyWith(busy: false, actionError: failure.message)),
      (_) => load(showSpinner: false),
    );
  }
}
