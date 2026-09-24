import 'package:nubia_domain/src/entities/consultation_cr.dart';

class CrSectionDto {
  final String key;
  final String title;
  final String content;

  const CrSectionDto({
    required this.key,
    required this.title,
    required this.content,
  });

  factory CrSectionDto.fromJson(Map<String, dynamic> json) => CrSectionDto(
        key: json['key'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
      );

  factory CrSectionDto.fromDomain(CrSectionEntry entry) => CrSectionDto(
        key: entry.key,
        title: entry.title,
        content: entry.content,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'content': content,
      };

  CrSectionEntry toDomain() =>
      CrSectionEntry(key: key, title: title, content: content);
}

class ConsultationCrDto {
  final String? templateId;
  final List<CrSectionDto> sections;
  final String status;

  const ConsultationCrDto({
    this.templateId,
    required this.sections,
    required this.status,
  });

  factory ConsultationCrDto.fromJson(Map<String, dynamic> json) {
    return ConsultationCrDto(
      templateId: json['template_id'] as String?,
      sections: (json['sections'] as List<dynamic>? ?? [])
          .map((e) => CrSectionDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      status: json['status'] as String,
    );
  }

  ConsultationCr toDomain() => ConsultationCr(
        templateId: templateId,
        sections: sections.map((s) => s.toDomain()).toList(),
        status: status,
      );
}
