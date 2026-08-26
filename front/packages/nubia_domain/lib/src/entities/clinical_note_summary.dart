import 'package:equatable/equatable.dart';

/// Statut d'une note clinique. `unknown` est le repli sûr pour une valeur API
/// non reconnue (#5053) — jamais interprété comme [signed].
enum ClinicalNoteStatus { signed, draft, unsigned, unknown }

class ClinicalNoteSummary extends Equatable {
  final String id;
  final DateTime timestamp;
  final String patientInitials;
  final ClinicalNoteStatus status;

  const ClinicalNoteSummary({
    required this.id,
    required this.timestamp,
    required this.patientInitials,
    required this.status,
  });

  @override
  List<Object?> get props => [id, timestamp, patientInitials, status];
}
