import 'package:nubia_domain/src/entities/consent_template.dart';

class ConsentTemplateDto {
  final String id;
  final String actCategory;
  final String title;
  final String bodyMarkdown;
  final int version;
  final bool isGlobal;
  final DateTime createdAt;

  const ConsentTemplateDto({
    required this.id,
    required this.actCategory,
    required this.title,
    required this.bodyMarkdown,
    required this.version,
    required this.isGlobal,
    required this.createdAt,
  });

  factory ConsentTemplateDto.fromJson(Map<String, dynamic> json) {
    return ConsentTemplateDto(
      id: json['id'] as String,
      actCategory: json['act_category'] as String,
      title: json['title'] as String,
      bodyMarkdown: json['body_markdown'] as String,
      version: json['version'] as int,
      isGlobal: json['is_global'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  ConsentTemplate toDomain() => ConsentTemplate(
        id: id,
        actCategory: actCategory,
        title: title,
        bodyMarkdown: bodyMarkdown,
        version: version,
        isGlobal: isGlobal,
        createdAt: createdAt,
      );
}
