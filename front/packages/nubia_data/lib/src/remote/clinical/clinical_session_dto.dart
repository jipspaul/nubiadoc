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

  /// POST .../acts renvoie seulement `{ act_id }` (vérifié en live), pas
  /// l'acte complet (#3697, même schéma que le confirm RDV JEL-19) : on
  /// reconstruit le DTO à partir de la réponse et des champs envoyés.
  factory ClinicalActDto.fromCreateResponse(
    Map<String, dynamic> json, {
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
    required bool included,
  }) =>
      ClinicalActDto(
        id: json['act_id'] as String,
        ccamCode: ccamCode,
        label: label,
        tooth: tooth,
        amountCents: amountCents,
        included: included,
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

  // Contexte enrichi (refonte consultation, lot 1) — détail uniquement,
  // tous absents de la route liste : nullables de bout en bout.
  final PatientSummary? patient;
  final String? appointmentStartsAt;
  final String? appointmentMotif;
  final List<MedicalAlert> medicalAlerts;
  final String? medicalHistory;
  final CurrentPhase? currentPhase;
  final LastNote? lastNote;

  const ClinicalSessionDto({
    required this.id,
    required this.appointmentId,
    required this.status,
    required this.acts,
    this.note,
    this.patientName,
    this.startedAt,
    this.practitionerName,
    this.patient,
    this.appointmentStartsAt,
    this.appointmentMotif,
    this.medicalAlerts = const [],
    this.medicalHistory,
    this.currentPhase,
    this.lastNote,
  });

  factory ClinicalSessionDto.fromJson(Map<String, dynamic> json) {
    final patientJson = json['patient'] as Map<String, dynamic>?;
    final appointmentJson = json['appointment'] as Map<String, dynamic>?;
    final phaseJson = json['current_phase'] as Map<String, dynamic>?;
    final lastNoteJson = json['last_note'] as Map<String, dynamic>?;

    return ClinicalSessionDto(
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
      patient: patientJson == null
          ? null
          : PatientSummary(
              id: patientJson['id'] as String,
              displayName: patientJson['display_name'] as String,
              ageYears: (patientJson['age_years'] as num?)?.toInt(),
            ),
      appointmentStartsAt: appointmentJson?['starts_at'] as String?,
      appointmentMotif: appointmentJson?['motif'] as String?,
      medicalAlerts: (json['medical_alerts'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(
            (a) => MedicalAlert(
              kind: a['kind'] as String,
              label: a['label'] as String,
            ),
          )
          .toList(),
      medicalHistory: json['medical_history'] as String?,
      currentPhase: phaseJson == null
          ? null
          : CurrentPhase(
              planId: phaseJson['plan_id'] as String,
              planTitle: phaseJson['plan_title'] as String,
              phaseId: phaseJson['phase_id'] as String,
              phaseTitle: phaseJson['phase_title'] as String,
              position: (phaseJson['position'] as num).toInt(),
              phaseCount: (phaseJson['phase_count'] as num).toInt(),
              plannedSessions: (phaseJson['planned_sessions'] as num?)?.toInt(),
              completedSessions:
                  (phaseJson['completed_sessions'] as num).toInt(),
              nextPhaseTitle: phaseJson['next_phase_title'] as String?,
            ),
      lastNote: lastNoteJson == null
          ? null
          : LastNote(
              date: DateTime.tryParse((lastNoteJson['date'] as String?) ?? ''),
              excerpt: lastNoteJson['excerpt'] as String? ?? '',
            ),
    );
  }

  ClinicalSession toDomain() => ClinicalSession(
        id: id,
        appointmentId: appointmentId,
        status: status,
        acts: acts.map((a) => a.toDomain()).toList(),
        note: note,
        patientName: patientName,
        startedAt: startedAt == null ? null : DateTime.tryParse(startedAt!),
        practitionerName: practitionerName,
        patient: patient,
        appointmentStartsAt: appointmentStartsAt == null
            ? null
            : DateTime.tryParse(appointmentStartsAt!),
        appointmentMotif: appointmentMotif,
        medicalAlerts: medicalAlerts,
        medicalHistory: medicalHistory,
        currentPhase: currentPhase,
        lastNote: lastNote,
      );
}
