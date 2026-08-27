import 'package:nubia_domain/src/entities/waiting_room_entry.dart';
import 'package:nubia_domain/src/entities/waiting_list_entry.dart';

class WaitingRoomEntryDto {
  final String id;
  final String cabinetId;
  final String patientId;
  final String patientName;
  final String? appointmentId;
  final String arrivedAt;
  final int? estimatedWaitMinutes;
  final String? reason;
  final String? appointmentTime;
  final String? practitionerId;
  final String? practitionerName;
  final String? scheduledAt;

  const WaitingRoomEntryDto({
    required this.id,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    this.appointmentId,
    required this.arrivedAt,
    this.estimatedWaitMinutes,
    this.reason,
    this.appointmentTime,
    this.practitionerId,
    this.practitionerName,
    this.scheduledAt,
  });

  factory WaitingRoomEntryDto.fromJson(Map<String, dynamic> json) =>
      WaitingRoomEntryDto(
        // GET /v1/cabinet/waiting-room (api/src/scheduling.rs, WaitingRoomEntry)
        // n'envoie jamais `id` — seulement `appointment_id` (#3782). Un cast
        // dur sur `id` faisait échouer le décodage de CHAQUE entrée dès qu'un
        // patient était en salle d'attente (écran d'erreur plein écran).
        id: (json['id'] as String?) ??
            (json['appointment_id'] as String?) ??
            '',
        cabinetId: (json['cabinet_id'] as String?) ?? '',
        patientId: (json['patient_id'] as String?) ?? '',
        patientName: (json['patient_name_initials'] as String?) ??
            (json['patient_name'] as String?) ??
            '',
        appointmentId: json['appointment_id'] as String?,
        arrivedAt: (json['checkin_at'] as String?) ??
            (json['arrived_at'] as String?) ??
            DateTime.now().toIso8601String(),
        estimatedWaitMinutes: (json['wait_minutes'] as num?)?.toInt() ??
            (json['estimated_wait_minutes'] as num?)?.toInt(),
        reason: json['motif'] as String?,
        appointmentTime: json['starts_at'] as String?,
        practitionerId: json['practitioner_id'] as String?,
        practitionerName: json['practitioner_name'] as String?,
        scheduledAt: json['scheduled_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'patient_id': patientId,
        if (appointmentId != null) 'appointment_id': appointmentId,
        if (estimatedWaitMinutes != null)
          'estimated_wait_minutes': estimatedWaitMinutes,
      };

  WaitingRoomEntry toDomain() => WaitingRoomEntry(
        id: id,
        cabinetId: cabinetId,
        patientId: patientId,
        patientName: patientName,
        appointmentId: appointmentId,
        arrivedAt: DateTime.parse(arrivedAt),
        estimatedWaitMinutes: estimatedWaitMinutes,
        reason: reason,
        appointmentTime:
            appointmentTime != null ? DateTime.tryParse(appointmentTime!) : null,
        practitionerId: practitionerId,
        practitionerName: practitionerName,
        scheduledAt: scheduledAt != null ? DateTime.tryParse(scheduledAt!) : null,
      );
}

class WaitingListEntryDto {
  final String id;
  final String cabinetId;
  final String patientId;
  final String patientName;
  final String motif;
  final String requestedAt;
  final int position;

  const WaitingListEntryDto({
    required this.id,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    required this.motif,
    required this.requestedAt,
    required this.position,
  });

  factory WaitingListEntryDto.fromJson(Map<String, dynamic> json) =>
      WaitingListEntryDto(
        id: json['id'] as String,
        cabinetId: (json['cabinet_id'] as String?) ?? '',
        patientId: (json['patient_id'] as String?) ?? '',
        patientName: (json['patient_name'] as String?) ?? '',
        motif: (json['motif'] as String?) ?? '',
        requestedAt: (json['requested_at'] as String?) ??
            (json['created_at'] as String?) ??
            DateTime.now().toIso8601String(),
        position: (json['position'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'patient_id': patientId,
        'motif': motif,
      };

  WaitingListEntry toDomain() => WaitingListEntry(
        id: id,
        cabinetId: cabinetId,
        patientId: patientId,
        patientName: patientName,
        motif: motif,
        requestedAt: DateTime.parse(requestedAt),
        position: position,
      );
}
