import 'package:equatable/equatable.dart';

/// Résultat d'un import de modèle `.docx` (#7157/#7156) —
/// `POST /v1/letter-templates/import` renvoie l'identifiant du modèle créé
/// et les placeholders détectés dans `word/document.xml`.
class LetterTemplateImportResult extends Equatable {
  final String templateId;
  final List<String> placeholders;

  const LetterTemplateImportResult({
    required this.templateId,
    required this.placeholders,
  });

  @override
  List<Object?> get props => [templateId, placeholders];
}
