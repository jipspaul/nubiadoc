import 'package:equatable/equatable.dart';

/// Statut d'une note clinique. `unknown` est le repli sûr pour une valeur API
/// non reconnue (#5053) — jamais interprété comme [signed].
enum ClinicalNoteStatus { signed, draft, unsigned, unknown }

class ClinicalNoteSummary extends Equatable {
  final String id;
  final DateTime timestamp;
  final String patientInitials;
  final ClinicalNoteStatus status;

  /// Nom complet du patient. `null` tant que l'API `GET
  /// /v1/cabinet/today-notes` ne l'expose pas (choix délibéré « zéro PII »,
  /// voir `api/src/clinical.rs::TodayNoteItem` et le test
  /// `today_notes_returns_todays_sessions`) — les vues de survol retombent
  /// alors sur [patientInitials] (#5048).
  final String? patientName;

  const ClinicalNoteSummary({
    required this.id,
    required this.timestamp,
    required this.patientInitials,
    required this.status,
    this.patientName,
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
