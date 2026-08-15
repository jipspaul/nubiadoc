import 'package:equatable/equatable.dart';

/// A CCAM act added during a clinical consultation.
class ClinicalAct extends Equatable {
  final String id;
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;

  /// Horodatage d'ajout de l'acte (#4950 — heure `HH:MM` affichée sur la
  /// ligne d'acte). `null` uniquement pour un acte reconstruit localement
  /// depuis une réponse de création qui ne renvoie pas cette donnée.
  final DateTime? createdAt;

  const ClinicalAct({
    required this.id,
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
    this.createdAt,
  });

  @override
  List<Object?> get props =>
      [id, ccamCode, label, tooth, amountCents, included, createdAt];
}

/// Alerte médicale passive du dossier patient (allergie ou flag
/// médico-légal, #4103) — AFFICHAGE PASSIF uniquement (périmètre
/// non-dispositif-médical), jamais de contrôle ni de recommandation.
/// `kind` : 'allergie' | 'medico_legal'.
class MedicalAlert extends Equatable {
  final String kind;
  final String label;

  const MedicalAlert({required this.kind, required this.label});

  @override
  List<Object?> get props => [kind, label];
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

  /// Id du patient de la séance — sert au cloisonnement de l'historique
  /// « Dernières séances » (#4937, filtre `patientId` sur `listSessions`).
  final String? patientId;

  /// Début de séance (liste uniquement).
  final DateTime? startedAt;

  /// Nom affichable du praticien propriétaire de la séance (#3403 — distinguer
  /// la consultation d'un confrère dans l'historique).
  final String? practitionerName;

  /// Date de naissance du patient de la séance (#4945 — barre d'identité
  /// patient, sous-titre « <âge> ans · née le JJ/MM/AAAA »). `null` si
  /// absente du dossier patient.
  final DateTime? patientBirthDate;

  /// Alertes médicales du dossier patient (détail uniquement — absent de la
  /// route liste, #4936). Liste vide si le dossier n'a aucune alerte.
  final List<MedicalAlert> medicalAlerts;

  const ClinicalSession({
    required this.id,
    required this.appointmentId,
    required this.status,
    required this.acts,
    this.note,
    this.patientName,
    this.patientId,
    this.startedAt,
    this.practitionerName,
    this.patientBirthDate,
    this.medicalAlerts = const [],
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
        patientId,
        startedAt,
        practitionerName,
        patientBirthDate,
        medicalAlerts,
      ];
}

/// Result of POST .../complete
class SessionCompleteResult extends Equatable {
  final String? invoiceId;
  final String? nextStep;

  const SessionCompleteResult({this.invoiceId, this.nextStep});

  @override
  List<Object?> get props => [invoiceId, nextStep];
}
