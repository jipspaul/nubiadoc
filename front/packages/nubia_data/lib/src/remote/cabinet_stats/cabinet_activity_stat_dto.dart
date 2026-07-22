import 'package:nubia_domain/src/entities/cabinet_activity_stat.dart';

class CabinetActivityStatDto {
  final String practitionerId;
  final String? practitionerName;
  final String ccamCode;
  final String label;
  final int actCount;
  final int totalAmountCents;

  const CabinetActivityStatDto({
    required this.practitionerId,
    this.practitionerName,
    required this.ccamCode,
    required this.label,
    required this.actCount,
    required this.totalAmountCents,
  });

  factory CabinetActivityStatDto.fromJson(Map<String, dynamic> json) =>
      CabinetActivityStatDto(
        practitionerId: json['practitioner_id'] as String,
        practitionerName: json['practitioner_name'] as String?,
        ccamCode: json['ccam_code'] as String,
        label: json['label'] as String,
        actCount: json['act_count'] as int,
        totalAmountCents: json['total_amount_cents'] as int,
      );

  CabinetActivityStat toDomain() => CabinetActivityStat(
        practitionerId: practitionerId,
        practitionerName: practitionerName,
        ccamCode: ccamCode,
        label: label,
        actCount: actCount,
        totalAmountCents: totalAmountCents,
      );
}
