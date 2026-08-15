import 'package:equatable/equatable.dart';

import 'clinical_session.dart' show MedicalAlert;

/// Résumé du dossier médical d'un patient (#4076) — affichage passif
/// uniquement (ADR-009, `docs/07-conformite.md` §8.6) : jamais de blocage
/// automatique ni de suggestion d'alternative, cf. périmètre MDR.
/// Source : `GET /v1/cabinet/patients/{id}/medical-record`.
class MedicalRecordSummary extends Equatable {
  final List<String> allergies;
  final List<String> treatments;

  /// Alertes affichables (allergie + flags médico-légaux à `true`, #4103) —
  /// même entité et même calcul serveur que `ClinicalSession.medicalAlerts`
  /// (consultation au fauteuil, #4936), pour les pastilles d'en-tête de la
  /// fiche patient (#4974). Vide si le dossier n'a aucune alerte.
  final List<MedicalAlert> medicalAlerts;

  const MedicalRecordSummary({
    required this.allergies,
    required this.treatments,
    this.medicalAlerts = const [],
  });

  @override
  List<Object?> get props => [allergies, treatments, medicalAlerts];
}
