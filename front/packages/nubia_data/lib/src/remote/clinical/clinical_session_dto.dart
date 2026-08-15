import 'package:nubia_domain/src/entities/clinical_session.dart';

class ClinicalActDto {
  final String id;
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;
  final String? createdAt;

  const ClinicalActDto({
    required this.id,
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
    this.createdAt,
  });

  factory ClinicalActDto.fromJson(Map<String, dynamic> json) => ClinicalActDto(
    id: json['id'] as String,
    ccamCode: json['ccam_code'] as String,
    label: json['label'] as String,
    tooth: json['tooth'] as String?,
    amountCents: (json['amount_cents'] as num?)?.toInt(),
    included: (json['included'] as bool?) ?? false,
    createdAt: json['created_at'] as String?,
  );

  /// POST .../acts renvoie seulement `{ act_id }` (vérifié en live), pas
  /// l'acte complet (#3697, même schéma que le confirm RDV JEL-19) : on
  /// reconstruit le DTO à partir de la réponse et des champs envoyés.
  /// `createdAt` n'est pas renvoyé par cette route ; l'appelant peut fournir
  /// l'horodatage local d'ajout (#4950).
  factory ClinicalActDto.fromCreateResponse(
    Map<String, dynamic> json, {
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
    required bool included,
    DateTime? createdAt,
  }) => ClinicalActDto(
    id: json['act_id'] as String,
    ccamCode: ccamCode,
    label: label,
    tooth: tooth,
    amountCents: amountCents,
    included: included,
    createdAt: createdAt?.toIso8601String(),
  );

  ClinicalAct toDomain() => ClinicalAct(
    id: id,
    ccamCode: ccamCode,
    label: label,
    tooth: tooth,
    amountCents: amountCents,
    included: included,
    createdAt: createdAt == null ? null : DateTime.tryParse(createdAt!),
  );
}

class ClinicalSessionDto {
  final String id;
  final String appointmentId;
  final String status;
  final List<ClinicalActDto> acts;
  final String? note;
  final String? patientName;
  final String? patientId;
  final String? startedAt;

  /// Nom affichable du praticien propriétaire de la séance (#3403 — distinguer
  /// visuellement la consultation d'un confrère). Renvoyé par le sous-objet
  /// `practitioner.display_name` de la liste et du détail.
  final String? practitionerName;

  /// Date de naissance du patient (`YYYY-MM-DD`, détail uniquement — #4945).
  final String? patientBirthDate;

  /// Alertes du dossier patient (détail uniquement, absent de la route liste
  /// — #4936). Vide par défaut.
  final List<MedicalAlert> medicalAlerts;

  const ClinicalSessionDto({
    required this.id,
    required this.appointmentId,
    required this.status,
    required this.acts,
    this.note,
    this.patientName,
    this.patientId,
    this.startedAt,
    this.practitionerName,
    this.patientBirthDate,
    this.medicalAlerts = const [],
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
        patientId: json['patient_id'] as String?,
        startedAt: json['started_at'] as String?,
        practitionerName:
            (json['practitioner'] as Map<String, dynamic>?)?['display_name']
                as String?,
        patientBirthDate: json['patient_birth_date'] as String?,
        medicalAlerts: (json['medical_alerts'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(
              (a) => MedicalAlert(
                kind: a['kind'] as String,
                label: a['label'] as String,
              ),
            )
            .toList(),
      );

  ClinicalSession toDomain() => ClinicalSession(
    id: id,
    appointmentId: appointmentId,
    status: status,
    acts: acts.map((a) => a.toDomain()).toList(),
    note: note,
    patientName: patientName,
    patientId: patientId,
    startedAt: startedAt == null ? null : DateTime.tryParse(startedAt!),
    practitionerName: practitionerName,
    patientBirthDate: patientBirthDate == null
        ? null
        : DateTime.tryParse(patientBirthDate!),
    medicalAlerts: medicalAlerts,
  );
}
