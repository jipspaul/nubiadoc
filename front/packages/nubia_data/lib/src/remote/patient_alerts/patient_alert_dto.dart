import 'package:nubia_domain/src/entities/patient_alert.dart';

class PatientAlertDto {
  final String kind;
  final String message;

  const PatientAlertDto({required this.kind, required this.message});

  factory PatientAlertDto.fromJson(Map<String, dynamic> json) =>
      PatientAlertDto(
        kind: json['kind'] as String,
        message: json['message'] as String,
      );

  PatientAlert toDomain() => PatientAlert(kind: kind, message: message);
}
