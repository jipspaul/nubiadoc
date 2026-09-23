import 'package:equatable/equatable.dart';

/// Type d'une question de questionnaire (`api/src/questionnaire_templates.rs`
/// `VALID_QUESTION_TYPES`, fermé côté API : un type inconnu est rejeté à
/// l'écriture, pas de valeur `unknown` de repli côté front).
enum QuestionnaireQuestionType { text, boolean, select }

/// Condition « afficher si » : une question n'est visible que si la réponse
/// déjà saisie à la question [key] du même schéma vaut [equals] (comparaison
/// stricte, une seule passe — pas de résolution transitive de chaînes de
/// conditions, cohérent avec `condition_met` côté API).
class QuestionnaireCondition extends Equatable {
  final String key;
  final dynamic equals;

  const QuestionnaireCondition({required this.key, required this.equals});

  bool isSatisfiedBy(Map<String, dynamic> payload) => payload[key] == equals;

  @override
  List<Object?> get props => [key, equals];
}

/// Question d'un modèle de questionnaire (#7158). `options` non vide requis
/// si [type] == [QuestionnaireQuestionType.select]. [safetyFlag] : annotation
/// d'affichage renforcé praticien uniquement, sans aucune portée décisionnelle
/// (pas de fonction dispositif médical, cf. `AGENTS.md` racine).
class QuestionnaireQuestion extends Equatable {
  final String key;
  final QuestionnaireQuestionType type;
  final String label;
  final List<String> options;
  final QuestionnaireCondition? condition;
  final bool safetyFlag;
  final bool required;

  const QuestionnaireQuestion({
    required this.key,
    required this.type,
    required this.label,
    this.options = const [],
    this.condition,
    this.safetyFlag = false,
    this.required = false,
  });

  /// `true` si aucune condition, ou si la condition est satisfaite par
  /// [payload] — les réponses déjà saisies pour les autres questions du même
  /// schéma.
  bool isVisible(Map<String, dynamic> payload) =>
      condition == null || condition!.isSatisfiedBy(payload);

  @override
  List<Object?> get props =>
      [key, type, label, options, condition, safetyFlag, required];
}
