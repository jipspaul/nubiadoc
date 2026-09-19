import 'package:equatable/equatable.dart';

sealed class ConsentTemplatesEvent extends Equatable {
  const ConsentTemplatesEvent();

  @override
  List<Object?> get props => [];
}

/// Charge le catalogue global + les modèles propres au cabinet.
class ConsentTemplatesLoadRequested extends ConsentTemplatesEvent {
  const ConsentTemplatesLoadRequested();
}

/// Crée un modèle propre au cabinet.
class ConsentTemplatesCreateRequested extends ConsentTemplatesEvent {
  const ConsentTemplatesCreateRequested({
    required this.actCategory,
    required this.title,
    required this.bodyMarkdown,
  });

  final String actCategory;
  final String title;
  final String bodyMarkdown;

  @override
  List<Object?> get props => [actCategory, title, bodyMarkdown];
}

/// Fait évoluer un modèle du cabinet (nouvelle version, jamais éditée en
/// place côté API — cf. `ConsentTemplateRepository.patch`).
class ConsentTemplatesUpdateRequested extends ConsentTemplatesEvent {
  const ConsentTemplatesUpdateRequested({
    required this.id,
    required this.actCategory,
    required this.title,
    required this.bodyMarkdown,
  });

  final String id;
  final String actCategory;
  final String title;
  final String bodyMarkdown;

  @override
  List<Object?> get props => [id, actCategory, title, bodyMarkdown];
}
