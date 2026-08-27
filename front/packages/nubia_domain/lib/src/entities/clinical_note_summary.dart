import 'package:equatable/equatable.dart';

/// Statut d'une note clinique. `unknown` est le repli sûr pour une valeur API
/// non reconnue (#5053) — jamais interprété comme [signed].
enum ClinicalNoteStatus { signed, draft, unsigned, unknown }

class ClinicalNoteSummary extends Equatable {
  final String id;
  final DateTime timestamp;
  final String patientInitials;
  final ClinicalNoteStatus status;

  /// Nom à afficher en titre de la ligne (#5047). Le nom complet du patient
  /// tant que l'API `GET /v1/cabinet/today-notes` l'expose ; sinon repli sur
  /// [patientInitials], appliqué par le repository (choix délibéré
  /// « zéro PII » côté API, voir `api/src/clinical.rs::TodayNoteItem` et le
  /// test `today_notes_returns_todays_sessions`) — jamais nul pour que la
  /// ligne ait toujours un titre.
  final String patientName;

  const ClinicalNoteSummary({
    required this.id,
    required this.timestamp,
    required this.patientInitials,
    required this.status,
    required this.patientName,
  });

  @override
  List<Object?> get props => [
        id,
        timestamp,
        patientInitials,
        status,
        patientName,
      ];
}
