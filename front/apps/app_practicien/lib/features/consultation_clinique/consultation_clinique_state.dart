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

  const ConsultationCliniqueLoaded({
    required this.session,
    this.actionInProgress = false,
    this.actionError,
    this.clinicalRiskWarning,
  });

  ConsultationCliniqueLoaded copyWith({
    ClinicalSession? session,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
    String? clinicalRiskWarning,
    bool clearClinicalRiskWarning = false,
  }) =>
      ConsultationCliniqueLoaded(
        session: session ?? this.session,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
        clinicalRiskWarning: clearClinicalRiskWarning
            ? null
            : (clinicalRiskWarning ?? this.clinicalRiskWarning),
      );

  @override
  List<Object?> get props =>
      [session, actionInProgress, actionError, clinicalRiskWarning];
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
