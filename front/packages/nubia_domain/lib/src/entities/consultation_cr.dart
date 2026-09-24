import 'package:equatable/equatable.dart';

/// Une section rédigée du CR structuré (`consultation_cr`, #7154) — clé
/// stable (ex. `"chirurgie"`) utilisée par le front pour retrouver la
/// section entre deux autosaves.
class CrSectionEntry extends Equatable {
  final String key;
  final String title;
  final String content;

  const CrSectionEntry({
    required this.key,
    required this.title,
    required this.content,
  });

  CrSectionEntry copyWith({String? content}) => CrSectionEntry(
        key: key,
        title: title,
        content: content ?? this.content,
      );

  @override
  List<Object?> get props => [key, title, content];
}

/// CR structuré d'une séance (`PUT`/`GET /v1/cabinet/consultations/:id/cr`,
/// #7154) — brouillon tant que [status] vaut `"draft"`, figé une fois
/// `"finalized"` (plus de ré-édition possible).
class ConsultationCr extends Equatable {
  final String? templateId;
  final List<CrSectionEntry> sections;
  final String status;

  const ConsultationCr({
    this.templateId,
    required this.sections,
    required this.status,
  });

  bool get isFinalized => status == 'finalized';

  @override
  List<Object?> get props => [templateId, sections, status];
}
