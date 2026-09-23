import 'package:nubia_domain/src/entities/letter_template_import_result.dart';

class LetterTemplateImportResultDto {
  final String templateId;
  final List<String> placeholders;

  const LetterTemplateImportResultDto({
    required this.templateId,
    required this.placeholders,
  });

  factory LetterTemplateImportResultDto.fromJson(Map<String, dynamic> json) =>
      LetterTemplateImportResultDto(
        templateId: json['template_id'] as String,
        placeholders: (json['placeholders'] as List<dynamic>?)
                ?.map((p) => p as String)
                .toList() ??
            const [],
      );

  LetterTemplateImportResult toDomain() => LetterTemplateImportResult(
        templateId: templateId,
        placeholders: placeholders,
      );
}
