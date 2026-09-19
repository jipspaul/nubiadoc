import 'package:nubia_domain/src/entities/letter_template.dart';

class LetterTemplateDto {
  final String id;
  final String name;
  final String kind;
  final String bodyTemplate;
  final bool isGlobal;
  final List<String> placeholders;

  const LetterTemplateDto({
    required this.id,
    required this.name,
    required this.kind,
    this.bodyTemplate = '',
    this.isGlobal = false,
    this.placeholders = const [],
  });

  factory LetterTemplateDto.fromJson(Map<String, dynamic> json) =>
      LetterTemplateDto(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        bodyTemplate: json['body_template'] as String? ?? '',
        isGlobal: json['is_global'] as bool? ?? false,
        placeholders: (json['placeholders'] as List<dynamic>?)
                ?.map((p) => p as String)
                .toList() ??
            const [],
      );

  LetterTemplate toDomain() => LetterTemplate(
        id: id,
        name: name,
        kind: kind,
        bodyTemplate: bodyTemplate,
        isGlobal: isGlobal,
        placeholders: placeholders,
      );
}
