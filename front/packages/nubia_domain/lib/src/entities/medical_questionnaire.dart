import 'package:equatable/equatable.dart';

/// Questionnaire médical patient pré-consultation (#4109). `payload` : objet
/// libre (antécédents, allergies, traitements en cours, ALD) — aucun
/// vocabulaire fermé n'est imposé côté API (`api/src/medical_questionnaire.rs`).
class MedicalQuestionnaire extends Equatable {
  final String id;
  final String cabinetId;
  final Map<String, dynamic> payload;
  final String status;
  final DateTime? submittedAt;

  /// Modèle et version sur lesquels cette soumission a été figée (#7158).
  /// `null` pour les soumissions historiques antérieures au versionnage.
  final String? templateId;
  final int? templateVersion;

  const MedicalQuestionnaire({
    required this.id,
    required this.cabinetId,
    required this.payload,
    required this.status,
    this.submittedAt,
    this.templateId,
    this.templateVersion,
  });

  @override
  List<Object?> get props => [
        id,
        cabinetId,
        payload,
        status,
        submittedAt,
        templateId,
        templateVersion,
      ];
}
