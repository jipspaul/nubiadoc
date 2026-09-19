import 'package:nubia_domain/src/entities/cabinet_brief.dart';

class BriefAppointmentItemDto {
  final String id;
  final String startsAt;
  final String patientId;
  final String patientDisplayName;
  final String? motif;
  final String status;

  const BriefAppointmentItemDto({
    required this.id,
    required this.startsAt,
    required this.patientId,
    required this.patientDisplayName,
    this.motif,
    required this.status,
  });

  factory BriefAppointmentItemDto.fromJson(Map<String, dynamic> json) =>
      BriefAppointmentItemDto(
        id: json['id'] as String,
        startsAt: json['starts_at'] as String,
        patientId: json['patient_id'] as String,
        patientDisplayName: json['patient_display_name'] as String,
        motif: json['motif'] as String?,
        status: json['status'] as String,
      );

  BriefAppointmentItem toDomain() => BriefAppointmentItem(
        id: id,
        startsAt: startsAt,
        patientId: patientId,
        patientDisplayName: patientDisplayName,
        motif: motif,
        status: status,
      );
}

class BriefPractitionerAppointmentsDto {
  final String practitionerId;
  final String? practitionerDisplayName;
  final List<BriefAppointmentItemDto> appointments;

  const BriefPractitionerAppointmentsDto({
    required this.practitionerId,
    this.practitionerDisplayName,
    required this.appointments,
  });

  factory BriefPractitionerAppointmentsDto.fromJson(
    Map<String, dynamic> json,
  ) =>
      BriefPractitionerAppointmentsDto(
        practitionerId: json['practitioner_id'] as String,
        practitionerDisplayName: json['practitioner_display_name'] as String?,
        appointments: (json['appointments'] as List<dynamic>? ?? [])
            .map((e) =>
                BriefAppointmentItemDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  BriefPractitionerAppointments toDomain() => BriefPractitionerAppointments(
        practitionerId: practitionerId,
        practitionerDisplayName: practitionerDisplayName,
        appointments: appointments.map((a) => a.toDomain()).toList(),
      );
}

class BriefNewPatientDto {
  final String patientId;
  final String patientDisplayName;
  final String appointmentId;
  final String startsAt;

  const BriefNewPatientDto({
    required this.patientId,
    required this.patientDisplayName,
    required this.appointmentId,
    required this.startsAt,
  });

  factory BriefNewPatientDto.fromJson(Map<String, dynamic> json) =>
      BriefNewPatientDto(
        patientId: json['patient_id'] as String,
        patientDisplayName: json['patient_display_name'] as String,
        appointmentId: json['appointment_id'] as String,
        startsAt: json['starts_at'] as String,
      );

  BriefNewPatient toDomain() => BriefNewPatient(
        patientId: patientId,
        patientDisplayName: patientDisplayName,
        appointmentId: appointmentId,
        startsAt: startsAt,
      );
}

class BriefPlannedActDto {
  final String motif;
  final int count;

  const BriefPlannedActDto({required this.motif, required this.count});

  factory BriefPlannedActDto.fromJson(Map<String, dynamic> json) =>
      BriefPlannedActDto(
        motif: json['motif'] as String,
        count: json['count'] as int,
      );

  BriefPlannedAct toDomain() => BriefPlannedAct(motif: motif, count: count);
}

class BriefProsthesisDto {
  final String id;
  final String patientId;
  final String patientDisplayName;
  final String appointmentId;
  final String appointmentStartsAt;
  final String? toothFdi;
  final String? workNature;
  final String labName;
  final String status;

  const BriefProsthesisDto({
    required this.id,
    required this.patientId,
    required this.patientDisplayName,
    required this.appointmentId,
    required this.appointmentStartsAt,
    this.toothFdi,
    this.workNature,
    required this.labName,
    required this.status,
  });

  factory BriefProsthesisDto.fromJson(Map<String, dynamic> json) =>
      BriefProsthesisDto(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        patientDisplayName: json['patient_display_name'] as String,
        appointmentId: json['appointment_id'] as String,
        appointmentStartsAt: json['appointment_starts_at'] as String,
        toothFdi: json['tooth_fdi'] as String?,
        workNature: json['work_nature'] as String?,
        labName: json['lab_name'] as String,
        status: json['status'] as String,
      );

  BriefProsthesis toDomain() => BriefProsthesis(
        id: id,
        patientId: patientId,
        patientDisplayName: patientDisplayName,
        appointmentId: appointmentId,
        appointmentStartsAt: appointmentStartsAt,
        toothFdi: toothFdi,
        workNature: workNature,
        labName: labName,
        status: status,
      );
}

class BriefOpenTaskDto {
  final String id;
  final String title;
  final String? assigneeDisplayName;
  final String? patientDisplayName;
  final String? dueDate;

  const BriefOpenTaskDto({
    required this.id,
    required this.title,
    this.assigneeDisplayName,
    this.patientDisplayName,
    this.dueDate,
  });

  factory BriefOpenTaskDto.fromJson(Map<String, dynamic> json) =>
      BriefOpenTaskDto(
        id: json['id'] as String,
        title: json['title'] as String,
        assigneeDisplayName: json['assignee_display_name'] as String?,
        patientDisplayName: json['patient_display_name'] as String?,
        dueDate: json['due_date'] as String?,
      );

  BriefOpenTask toDomain() => BriefOpenTask(
        id: id,
        title: title,
        assigneeDisplayName: assigneeDisplayName,
        patientDisplayName: patientDisplayName,
        dueDate: dueDate,
      );
}

class CabinetBriefDto {
  final String view;
  final String rangeStart;
  final String rangeEnd;
  final List<BriefPractitionerAppointmentsDto> appointmentsByPractitioner;
  final List<BriefNewPatientDto> newPatients;
  final List<BriefPlannedActDto> plannedActs;
  final List<BriefProsthesisDto> prosthesesToFit;
  final List<BriefOpenTaskDto> openTasks;

  const CabinetBriefDto({
    required this.view,
    required this.rangeStart,
    required this.rangeEnd,
    required this.appointmentsByPractitioner,
    required this.newPatients,
    required this.plannedActs,
    required this.prosthesesToFit,
    required this.openTasks,
  });

  factory CabinetBriefDto.fromJson(Map<String, dynamic> json) =>
      CabinetBriefDto(
        view: json['view'] as String,
        rangeStart: json['range_start'] as String,
        rangeEnd: json['range_end'] as String,
        appointmentsByPractitioner:
            (json['appointments_by_practitioner'] as List<dynamic>? ?? [])
                .map((e) => BriefPractitionerAppointmentsDto.fromJson(
                    e as Map<String, dynamic>))
                .toList(),
        newPatients: (json['new_patients'] as List<dynamic>? ?? [])
            .map((e) => BriefNewPatientDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        plannedActs: (json['planned_acts'] as List<dynamic>? ?? [])
            .map((e) => BriefPlannedActDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        prosthesesToFit: (json['prostheses_to_fit'] as List<dynamic>? ?? [])
            .map((e) => BriefProsthesisDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        openTasks: (json['open_tasks'] as List<dynamic>? ?? [])
            .map((e) => BriefOpenTaskDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  CabinetBrief toDomain() => CabinetBrief(
        view: view,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        appointmentsByPractitioner:
            appointmentsByPractitioner.map((a) => a.toDomain()).toList(),
        newPatients: newPatients.map((n) => n.toDomain()).toList(),
        plannedActs: plannedActs.map((a) => a.toDomain()).toList(),
        prosthesesToFit: prosthesesToFit.map((p) => p.toDomain()).toList(),
        openTasks: openTasks.map((t) => t.toDomain()).toList(),
      );
}
