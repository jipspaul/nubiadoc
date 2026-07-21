import 'package:nubia_domain/src/entities/patient_tag.dart';

class PatientTagDto {
  final String id;
  final String label;
  final String color;
  final String createdBy;
  final String createdAt;

  const PatientTagDto({
    required this.id,
    required this.label,
    required this.color,
    required this.createdBy,
    required this.createdAt,
  });

  factory PatientTagDto.fromJson(Map<String, dynamic> json) => PatientTagDto(
        id: json['id'] as String,
        label: json['label'] as String,
        color: json['color'] as String,
        createdBy: json['created_by'] as String,
        createdAt: json['created_at'] as String,
      );

  PatientTag toDomain() => PatientTag(
        id: id,
        label: label,
        color: color,
        createdBy: createdBy,
        createdAt: DateTime.parse(createdAt),
      );
}
