import 'package:equatable/equatable.dart';

/// Résumé du dossier médical d'un patient (#4076) — affichage passif
/// uniquement (ADR-009, `docs/07-conformite.md` §8.6) : jamais de blocage
/// automatique ni de suggestion d'alternative, cf. périmètre MDR.
/// Source : `GET /v1/cabinet/patients/{id}/medical-record`.
class MedicalRecordSummary extends Equatable {
  final List<String> allergies;
  final List<String> treatments;

  const MedicalRecordSummary({
    required this.allergies,
    required this.treatments,
  });

  @override
  List<Object?> get props => [allergies, treatments];
}
