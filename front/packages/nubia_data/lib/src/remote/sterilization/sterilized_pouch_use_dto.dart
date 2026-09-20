import 'package:nubia_domain/src/entities/sterilized_pouch_use.dart';

class SterilizedPouchUseDto {
  final String pouchId;
  final String code;
  final String cycleId;
  final String patientId;
  final String? consultationId;
  final String usedAt;
  final bool alreadyUsed;

  const SterilizedPouchUseDto({
    required this.pouchId,
    required this.code,
    required this.cycleId,
    required this.patientId,
    this.consultationId,
    required this.usedAt,
    required this.alreadyUsed,
  });

  factory SterilizedPouchUseDto.fromJson(Map<String, dynamic> json) =>
      SterilizedPouchUseDto(
        pouchId: json['pouch_id'] as String,
        code: json['code'] as String,
        cycleId: json['cycle_id'] as String,
        patientId: json['patient_id'] as String,
        consultationId: json['consultation_id'] as String?,
        usedAt: json['used_at'] as String,
        alreadyUsed: json['already_used'] as bool,
      );

  SterilizedPouchUse toDomain() => SterilizedPouchUse(
        pouchId: pouchId,
        code: code,
        cycleId: cycleId,
        patientId: patientId,
        consultationId: consultationId,
        usedAt: DateTime.parse(usedAt),
        alreadyUsed: alreadyUsed,
      );
}
