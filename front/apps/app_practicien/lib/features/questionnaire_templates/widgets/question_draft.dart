import 'package:nubia_domain/nubia_domain.dart';

/// Brouillon éditable d'une question, le temps de la session d'édition
/// (#7158). [id] est un identifiant synthétique local (stable pour la
/// `Key` Flutter de [QuestionEditorTile] tant que la question n'est pas
/// supprimée) — distinct de [key], le champ métier éditable par le
/// praticien et envoyé à l'API.
class QuestionDraft {
  QuestionDraft({
    required this.id,
    this.key = '',
    this.type = QuestionnaireQuestionType.text,
    this.label = '',
    List<String>? options,
    this.conditionKey,
    this.required = false,
    this.safetyFlag = false,
  }) : options = options ?? [];

  final int id;
  String key;
  QuestionnaireQuestionType type;
  String label;
  List<String> options;

  /// Clé d'une question booléenne déjà définie plus haut dans le schéma —
  /// condition « afficher si `conditionKey` == true ». `null` : toujours
  /// visible.
  String? conditionKey;
  bool required;
  bool safetyFlag;

  factory QuestionDraft.fromDomain(int id, QuestionnaireQuestion question) =>
      QuestionDraft(
        id: id,
        key: question.key,
        type: question.type,
        label: question.label,
        options: List.of(question.options),
        conditionKey: question.condition?.key,
        required: question.required,
        safetyFlag: question.safetyFlag,
      );

  QuestionnaireQuestion toDomain() => QuestionnaireQuestion(
        key: key,
        type: type,
        label: label,
        options: type == QuestionnaireQuestionType.select ? options : const [],
        condition:
            conditionKey != null
                ? QuestionnaireCondition(key: conditionKey!, equals: true)
                : null,
        required: required,
        safetyFlag: safetyFlag,
      );

  bool get isValid {
    if (key.trim().isEmpty || label.trim().isEmpty) return false;
    if (type == QuestionnaireQuestionType.select && options.isEmpty) {
      return false;
    }
    return true;
  }
}
