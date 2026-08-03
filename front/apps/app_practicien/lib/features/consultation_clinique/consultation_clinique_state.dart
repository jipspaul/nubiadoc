import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class ConsultationCliniqueState extends Equatable {
  const ConsultationCliniqueState();

  @override
  List<Object?> get props => [];
}

class ConsultationCliniqueInitial extends ConsultationCliniqueState {
  const ConsultationCliniqueInitial();
}

class ConsultationCliniqueLoading extends ConsultationCliniqueState {
  const ConsultationCliniqueLoading();
}

/// Dernier acte ajouté avec succès portant une dent — porté par l'état pour
/// que le module dentaire puisse PROPOSER (jamais imposer) la mise à jour de
/// l'état de la dent sur l'odontogramme. Consommé après affichage.
class AddedToothAct extends Equatable {
  final String ccamCode;
  final String label;
  final String tooth;

  const AddedToothAct({
    required this.ccamCode,
    required this.label,
    required this.tooth,
  });

  @override
  List<Object?> get props => [ccamCode, label, tooth];
}

class ConsultationCliniqueLoaded extends ConsultationCliniqueState {
  final ClinicalSession session;
  final bool actionInProgress;

  /// Message d'erreur transitoire d'une action (ex. 403 sur ajout d'acte —
  /// #3403). Affiché via snackbar puis consommé, sans quitter l'écran.
  final String? actionError;

  /// Alerte clinique bloquante (#4057/#4058) — distincte de [actionError] :
  /// affichée via un dialogue bloquant (pas un snackbar), l'acte n'a PAS été
  /// enregistré (le back a refusé la requête, 409 clinical_risk_warning).
  final String? clinicalRiskWarning;

  /// Dent sélectionnée pour le prochain acte (#4048) — odontogramme intégré
  /// ou bottom-sheet mobile. Pré-remplit l'éditeur d'acte CCAM.
  final String? selectedTooth;

  /// Dernier acte ajouté avec dent (proposition de mise à jour
  /// d'odontogramme, consommé par la vue après affichage du dialogue).
  final AddedToothAct? lastAddedToothAct;

  const ConsultationCliniqueLoaded({
    required this.session,
    this.actionInProgress = false,
    this.actionError,
    this.clinicalRiskWarning,
    this.selectedTooth,
    this.lastAddedToothAct,
  });

  ConsultationCliniqueLoaded copyWith({
    ClinicalSession? session,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
    String? clinicalRiskWarning,
    bool clearClinicalRiskWarning = false,
    String? selectedTooth,
    bool clearSelectedTooth = false,
    AddedToothAct? lastAddedToothAct,
    bool clearLastAddedToothAct = false,
  }) =>
      ConsultationCliniqueLoaded(
        session: session ?? this.session,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
        clinicalRiskWarning: clearClinicalRiskWarning
            ? null
            : (clinicalRiskWarning ?? this.clinicalRiskWarning),
        selectedTooth:
            clearSelectedTooth ? null : (selectedTooth ?? this.selectedTooth),
        lastAddedToothAct: clearLastAddedToothAct
            ? null
            : (lastAddedToothAct ?? this.lastAddedToothAct),
      );

  @override
  List<Object?> get props => [
        session,
        actionInProgress,
        actionError,
        clinicalRiskWarning,
        selectedTooth,
        lastAddedToothAct,
      ];
}

class ConsultationCliniqueError extends ConsultationCliniqueState {
  final String message;
  const ConsultationCliniqueError(this.message);

  @override
  List<Object?> get props => [message];
}

class ConsultationCliniqueCompleted extends ConsultationCliniqueState {
  final SessionCompleteResult result;
  const ConsultationCliniqueCompleted(this.result);

  @override
  List<Object?> get props => [result];
}

class ConsultationHistoriqueLoaded extends ConsultationCliniqueState {
  final List<ClinicalSession> sessions;
  const ConsultationHistoriqueLoaded({required this.sessions});

  @override
  List<Object?> get props => [sessions];
}
