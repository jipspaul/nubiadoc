import 'package:nubia_domain/src/entities/cr_template.dart';

class CrTemplateDto {
  final String id;
  final String? ccamCode;
  final String title;
  final String bodyTemplate;

  const CrTemplateDto({
    required this.id,
    this.ccamCode,
    required this.title,
    required this.bodyTemplate,
  });

  factory CrTemplateDto.fromJson(Map<String, dynamic> json) {
    return CrTemplateDto(
      id: json['id'] as String,
      ccamCode: json['ccam_code'] as String?,
      title: json['title'] as String,
      bodyTemplate: json['body_template'] as String,
    );
  }

  CrTemplate toDomain() => CrTemplate(
        id: id,
        ccamCode: ccamCode,
        title: title,
        bodyTemplate: bodyTemplate,
      );
}
