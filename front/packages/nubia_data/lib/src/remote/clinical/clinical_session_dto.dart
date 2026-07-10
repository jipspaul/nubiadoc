import 'package:nubia_domain/src/entities/clinical_session.dart';

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
  final String? note;
  final String? patientName;
  final String? startedAt;

  /// Nom affichable du praticien propriétaire de la séance (#3403 — distinguer
  /// visuellement la consultation d'un confrère). Renvoyé par le sous-objet
  /// `practitioner.display_name` de la liste et du détail.
  final String? practitionerName;

  const ClinicalSessionDto({
    required this.id,
    required this.appointmentId,
    required this.status,
    required this.acts,
    this.note,
    this.patientName,
    this.startedAt,
    this.practitionerName,
  });

  factory ClinicalSessionDto.fromJson(Map<String, dynamic> json) =>
      ClinicalSessionDto(
        // POST .../start renvoie `consultation_id` (pas `id`) ; GET
        // .../consultations/{id} renvoie `id`. On accepte les deux.
        id: (json['id'] ?? json['consultation_id']) as String,
        appointmentId: json['appointment_id'] as String,
        status: json['status'] as String,
        acts: (json['acts'] as List<dynamic>? ?? [])
            .map((e) => ClinicalActDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        note: json['note'] as String?,
        patientName: json['patient_name'] as String?,
        startedAt: json['started_at'] as String?,
        practitionerName: (json['practitioner']
            as Map<String, dynamic>?)?['display_name'] as String?,
      );

  ClinicalSession toDomain() => ClinicalSession(
        id: id,
        appointmentId: appointmentId,
        status: status,
        acts: acts.map((a) => a.toDomain()).toList(),
        note: note,
        patientName: patientName,
        startedAt: startedAt == null ? null : DateTime.tryParse(startedAt!),
        practitionerName: practitionerName,
      );
}
