import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class ConsultationCliniqueState extends Equatable {
  const ConsultationCliniqueState();

  @override
  List<Object?> get props => [];
}

/// Acte dont l'ajout a été refusé par l'alerte clinique (#4057) — conservé
/// le temps que le praticien réponde au dialogue, pour pouvoir rejouer la
/// requête avec `riskAcknowledged: true` sans ressaisie (#7911).
class PendingClinicalRiskAct extends Equatable {
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;

  const PendingClinicalRiskAct({
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
  });

  @override
  List<Object?> get props => [ccamCode, label, tooth, amountCents, included];
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

  /// Acte à l'origine de [clinicalRiskWarning] — rejoué avec
  /// `riskAcknowledged: true` si le praticien acquitte le dialogue (#7911).
  /// `null` dès que l'alerte est consommée (acquittée ou annulée).
  final PendingClinicalRiskAct? pendingClinicalRiskAct;

  /// Horodatage du dernier enregistrement réussi de la note de séance
  /// (#4943, #4963) — alimente l'indicateur « Enregistré automatiquement à
  /// HH:MM », qui remplace le bouton d'enregistrement manuel explicite.
  final DateTime? lastNoteSavedAt;

  const ConsultationCliniqueLoaded({
    required this.session,
    this.actionInProgress = false,
    this.actionError,
    this.clinicalRiskWarning,
    this.pendingClinicalRiskAct,
    this.lastNoteSavedAt,
  });

  ConsultationCliniqueLoaded copyWith({
    ClinicalSession? session,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
    String? clinicalRiskWarning,
    PendingClinicalRiskAct? pendingClinicalRiskAct,
    bool clearClinicalRiskWarning = false,
    DateTime? lastNoteSavedAt,
  }) =>
      ConsultationCliniqueLoaded(
        session: session ?? this.session,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
        clinicalRiskWarning: clearClinicalRiskWarning
            ? null
            : (clinicalRiskWarning ?? this.clinicalRiskWarning),
        pendingClinicalRiskAct: clearClinicalRiskWarning
            ? null
            : (pendingClinicalRiskAct ?? this.pendingClinicalRiskAct),
        lastNoteSavedAt: lastNoteSavedAt ?? this.lastNoteSavedAt,
      );

  @override
  List<Object?> get props => [
        session,
        actionInProgress,
        actionError,
        clinicalRiskWarning,
        pendingClinicalRiskAct,
        lastNoteSavedAt,
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

  /// Statut demandé au serveur pour produire [sessions] (#7033) — permet à
  /// `HistoriqueView` de resynchroniser le segment sélectionné après un
  /// rechargement (l'instance de la vue est recréée à chaque changement
  /// d'état du bloc).
  final String? statusFilter;

  const ConsultationHistoriqueLoaded({
    required this.sessions,
    this.statusFilter,
  });

  @override
  List<Object?> get props => [sessions, statusFilter];
}
