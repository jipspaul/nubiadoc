import 'package:equatable/equatable.dart';
import 'package:nubia_domain/src/entities/questionnaire_question.dart';

/// Modèle de questionnaire médical (`questionnaire_template`, #7158) :
/// catalogue global seedé ([isGlobal], lecture seule) ou variante propre au
/// cabinet (éditable). Jamais édité en place côté API — toute évolution crée
/// une nouvelle ligne ([version] incrémentée).
///
/// [isGlobal]/[createdAt] sont `null` quand ce template provient de
/// `GET /v1/account/medical-questionnaire/active-template` (résolution du
/// modèle actif côté patient) — cette réponse n'expose pas la portée
/// global/cabinet ni la date de création, seulement de quoi rendre le
/// formulaire (`schema`).
class QuestionnaireTemplate extends Equatable {
  final String id;
  final String title;
  final List<QuestionnaireQuestion> schema;
  final int version;
  final bool? isGlobal;
  final DateTime? createdAt;

  const QuestionnaireTemplate({
    required this.id,
    required this.title,
    required this.schema,
    required this.version,
    this.isGlobal,
    this.createdAt,
  });

  @override
  List<Object?> get props => [id];
}
