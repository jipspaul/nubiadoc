import 'package:equatable/equatable.dart';

/// A CCAM act added during a clinical consultation.
class ClinicalAct extends Equatable {
  final String id;
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;

  const ClinicalAct({
    required this.id,
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
  });

  @override
  List<Object?> get props =>
      [id, ccamCode, label, tooth, amountCents, included];
}

/// Patient de la séance (bandeau patient de la vue fauteuil).
/// L'API ne renvoie jamais la date de naissance — seulement l'âge calculé.
class PatientSummary extends Equatable {
  final String id;
  final String displayName;
  final int? ageYears;

  const PatientSummary({
    required this.id,
    required this.displayName,
    this.ageYears,
  });

  @override
  List<Object?> get props => [id, displayName, ageYears];
}

/// Alerte médicale en affichage PASSIF uniquement (périmètre non-DM).
/// `kind` : 'allergie' | 'medico_legal'.
class MedicalAlert extends Equatable {
  final String kind;
  final String label;

  const MedicalAlert({required this.kind, required this.label});

  @override
  List<Object?> get props => [kind, label];
}

/// Phase de plan de traitement en cours (panneau « Prochaine étape »).
class CurrentPhase extends Equatable {
  final String planId;
  final String planTitle;
  final String phaseId;
  final String phaseTitle;
  final int position;
  final int phaseCount;
  final int? plannedSessions;
  final int completedSessions;
  final String? nextPhaseTitle;

  const CurrentPhase({
    required this.planId,
    required this.planTitle,
    required this.phaseId,
    required this.phaseTitle,
    required this.position,
    required this.phaseCount,
    this.plannedSessions,
    required this.completedSessions,
    this.nextPhaseTitle,
  });

  @override
  List<Object?> get props => [
        planId,
        planTitle,
        phaseId,
        phaseTitle,
        position,
        phaseCount,
        plannedSessions,
        completedSessions,
        nextPhaseTitle,
      ];
}

/// Extrait daté de la note de la dernière séance terminée du patient.
class LastNote extends Equatable {
  final DateTime? date;
  final String excerpt;

  const LastNote({this.date, required this.excerpt});

  @override
  List<Object?> get props => [date, excerpt];
}

/// The clinical session context returned by GET /v1/cabinet/consultations/{id}.
class ClinicalSession extends Equatable {
  final String id;
  final String appointmentId;
  final String status; // 'in_progress' | 'completed' | 'cancelled'
  final List<ClinicalAct> acts;

  /// Note de séance (chiffrée côté serveur). `null` si aucune note enregistrée.
  final String? note;

  /// Nom du patient (renvoyé par la liste GET /v1/cabinet/consultations —
  /// #3371 : la carte titrait par l'UUID de séance).
  final String? patientName;

  /// Début de séance (liste uniquement).
  final DateTime? startedAt;

  /// Nom affichable du praticien propriétaire de la séance (#3403 — distinguer
  /// la consultation d'un confrère dans l'historique).
  final String? practitionerName;

  // ── Contexte enrichi (refonte consultation, lot 1) ────────────────────────
  // Tous nullables : la route liste ne les renvoie pas, et un back déployé
  // en décalé non plus — le front doit tolérer leur absence.

  /// Patient de la séance (détail uniquement).
  final PatientSummary? patient;

  /// Début du RDV lié à la séance (détail uniquement).
  final DateTime? appointmentStartsAt;

  /// Motif du RDV en texte libre (détail uniquement).
  final String? appointmentMotif;

  /// Alertes médicales passives (liste vide si dossier vide ou route liste).
  final List<MedicalAlert> medicalAlerts;

  /// Antécédents en texte libre (`medical_record.history`).
  final String? medicalHistory;

  /// Phase de plan de traitement en cours pour ce patient.
  final CurrentPhase? currentPhase;

  /// Dernière note de séance terminée du patient.
  final LastNote? lastNote;

  const ClinicalSession({
    required this.id,
    required this.appointmentId,
    required this.status,
    required this.acts,
    this.note,
    this.patientName,
    this.startedAt,
    this.practitionerName,
    this.patient,
    this.appointmentStartsAt,
    this.appointmentMotif,
    this.medicalAlerts = const [],
    this.medicalHistory,
    this.currentPhase,
    this.lastNote,
  });

  bool get isCompleted => status == 'completed';

  bool get isCancelled => status == 'cancelled';

  /// Séance qui n'est plus actionnable (ni "Terminer" ni autre action de
  /// séance en cours) : `completed` OU `cancelled` (#3833 — `isCompleted`
  /// seul traitait `cancelled` comme non-terminé, laissant le bouton
  /// « Terminer » actif sur une séance annulée → 409 `invalid_status`).
  bool get isFinished => isCompleted || isCancelled;

  @override
  List<Object?> get props => [
        id,
        appointmentId,
        status,
        acts,
        note,
        patientName,
        startedAt,
        practitionerName,
        patient,
        appointmentStartsAt,
        appointmentMotif,
        medicalAlerts,
        medicalHistory,
        currentPhase,
        lastNote,
      ];
}

/// Result of POST .../complete
class SessionCompleteResult extends Equatable {
  final String? invoiceId;
  final String? nextStep;

  /// Séances restantes sur la phase de plan décomptée à la clôture
  /// (`sessions_remaining`, #4120) — `null` si la séance n'était pas
  /// rattachée à une phase avec `planned_sessions`.
  final int? sessionsRemaining;

  const SessionCompleteResult({
    this.invoiceId,
    this.nextStep,
    this.sessionsRemaining,
  });

  @override
  List<Object?> get props => [invoiceId, nextStep, sessionsRemaining];
}
