import 'package:nubia_domain/src/entities/medical_record_summary.dart';

/// `allergies`/`treatments` sont des `jsonb` libres côté back
/// (`Vec<serde_json::Value>`, `medical_record.rs`) — chaque entrée peut être
/// une chaîne (`"Pénicilline"`) ou un objet (`{"name": "Pénicilline"}`).
/// Convertit défensivement vers une chaîne d'affichage plutôt que d'imposer
/// un schéma strict que le back ne garantit pas.
String _entryToDisplayString(dynamic entry) {
  if (entry is String) return entry;
  if (entry is Map) {
    final name = entry['name'] ?? entry['label'];
    if (name is String && name.isNotEmpty) return name;
  }
  return entry.toString();
}

class MedicalRecordSummaryDto {
  final List<String> allergies;
  final List<String> treatments;

  const MedicalRecordSummaryDto({
    required this.allergies,
    required this.treatments,
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
    );
  }

  MedicalRecordSummary toDomain() => MedicalRecordSummary(
        allergies: allergies,
        treatments: treatments,
      );
}
