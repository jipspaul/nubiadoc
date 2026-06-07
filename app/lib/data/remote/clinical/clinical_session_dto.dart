import 'package:nubia_patient/domain/entities/clinical_session.dart';

class ClinicalActDto {
  final String id;
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;

  const ClinicalActDto({
    required this.id,
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
  });

  factory ClinicalActDto.fromJson(Map<String, dynamic> json) => ClinicalActDto(
        id: json['id'] as String,
        ccamCode: json['ccam_code'] as String,
        label: json['label'] as String,
        tooth: json['tooth'] as String?,
        amountCents: (json['amount_cents'] as num?)?.toInt(),
        included: (json['included'] as bool?) ?? false,
      );

  ClinicalAct toDomain() => ClinicalAct(
        id: id,
        ccamCode: ccamCode,
        label: label,
        tooth: tooth,
        amountCents: amountCents,
        included: included,
      );
}

class ClinicalSessionDto {
  final String id;
  final String appointmentId;
  final String status;
  final List<ClinicalActDto> acts;

  const ClinicalSessionDto({
    required this.id,
    required this.appointmentId,
    required this.status,
    required this.acts,
  });

  factory ClinicalSessionDto.fromJson(Map<String, dynamic> json) =>
      ClinicalSessionDto(
        id: json['id'] as String,
        appointmentId: json['appointment_id'] as String,
        status: json['status'] as String,
        acts: (json['acts'] as List<dynamic>? ?? [])
            .map((e) => ClinicalActDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  ClinicalSession toDomain() => ClinicalSession(
        id: id,
        appointmentId: appointmentId,
        status: status,
        acts: acts.map((a) => a.toDomain()).toList(),
      );
}
