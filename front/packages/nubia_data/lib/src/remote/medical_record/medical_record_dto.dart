import 'package:nubia_domain/src/entities/clinical_session.dart' show MedicalAlert;
import 'package:nubia_domain/src/entities/medical_record_summary.dart';

/// `allergies`/`treatments` sont des `jsonb` libres côté back
/// (`Vec<serde_json::Value>`, `medical_record.rs`) — chaque entrée peut être
/// une chaîne (`"Pénicilline"`), un objet `{"name": "Pénicilline"}` /
/// `{"label": "Pénicilline"}`, un objet structuré
/// `{"severity": "high", "substance": "Pénicilline"}`, ou un objet issu du
/// questionnaire patient `{"source": "questionnaire_patient", "text": "…"}`
/// (`api/src/medical_questionnaire.rs`). Convertit défensivement vers une
/// chaîne d'affichage plutôt que d'imposer un schéma strict que le back ne
/// garantit pas.
String _entryToDisplayString(dynamic entry) {
  if (entry is String) return entry;
  if (entry is Map) {
    final name =
        entry['name'] ?? entry['label'] ?? entry['substance'] ?? entry['text'];
    if (name is String && name.isNotEmpty) return name;
  }
  return entry.toString();
}

class MedicalRecordSummaryDto {
  final List<String> allergies;
  final List<String> treatments;
  final List<MedicalAlert> medicalAlerts;

  const MedicalRecordSummaryDto({
    required this.allergies,
    required this.treatments,
    this.medicalAlerts = const [],
  });

  factory MedicalRecordSummaryDto.fromJson(Map<String, dynamic> json) {
    final rawAllergies = json['allergies'] as List<dynamic>? ?? [];
    final rawTreatments = json['treatments'] as List<dynamic>? ?? [];
    return MedicalRecordSummaryDto(
      allergies: rawAllergies
          .map(_entryToDisplayString)
          .where((s) => s.trim().isNotEmpty)
          .toList(),
      treatments: rawTreatments
          .map(_entryToDisplayString)
          .where((s) => s.trim().isNotEmpty)
          .toList(),
      medicalAlerts: (json['medical_alerts'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(
            (a) => MedicalAlert(
              kind: a['kind'] as String,
              label: a['label'] as String,
            ),
          )
          .toList(),
    );
  }

  MedicalRecordSummary toDomain() => MedicalRecordSummary(
        allergies: allergies,
        treatments: treatments,
        medicalAlerts: medicalAlerts,
      );
}
