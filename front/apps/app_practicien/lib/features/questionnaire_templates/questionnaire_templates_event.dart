import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class QuestionnaireTemplatesEvent extends Equatable {
  const QuestionnaireTemplatesEvent();

  @override
  List<Object?> get props => [];
}

/// Charge le catalogue global + le modèle propre au cabinet s'il existe.
class QuestionnaireTemplatesLoadRequested extends QuestionnaireTemplatesEvent {
  const QuestionnaireTemplatesLoadRequested();
}

/// Crée le modèle propre au cabinet (un seul à la fois — 409 si un existe
/// déjà).
class QuestionnaireTemplatesCreateRequested
    extends QuestionnaireTemplatesEvent {
  const QuestionnaireTemplatesCreateRequested({
    required this.title,
    required this.schema,
  });

  final String title;
  final List<QuestionnaireQuestion> schema;

  @override
  List<Object?> get props => [title, schema];
}

/// Fait évoluer le modèle du cabinet (nouvelle version, jamais éditée en
/// place côté API — cf. `QuestionnaireTemplateRepository.patch`).
class QuestionnaireTemplatesUpdateRequested
    extends QuestionnaireTemplatesEvent {
  const QuestionnaireTemplatesUpdateRequested({
    required this.id,
    required this.title,
    required this.schema,
  });

  final String id;
  final String title;
  final List<QuestionnaireQuestion> schema;

  @override
  List<Object?> get props => [id, title, schema];
}
