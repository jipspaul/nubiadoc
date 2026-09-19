import 'package:nubia_domain/src/entities/letter_template.dart';

class LetterTemplateDto {
  final String id;
  final String name;
  final String kind;

  const LetterTemplateDto({
    required this.id,
    required this.name,
    required this.kind,
  });

  factory LetterTemplateDto.fromJson(Map<String, dynamic> json) =>
      LetterTemplateDto(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
      );

  LetterTemplate toDomain() => LetterTemplate(id: id, name: name, kind: kind);
}
