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

  const WaitingRoomEntryDto({
    required this.id,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    this.appointmentId,
    required this.arrivedAt,
    this.estimatedWaitMinutes,
  });

  factory WaitingRoomEntryDto.fromJson(Map<String, dynamic> json) =>
      WaitingRoomEntryDto(
        id: json['id'] as String,
        cabinetId: json['cabinet_id'] as String,
        patientId: json['patient_id'] as String,
        patientName: json['patient_name'] as String,
        appointmentId: json['appointment_id'] as String?,
        arrivedAt: json['arrived_at'] as String,
        estimatedWaitMinutes: (json['estimated_wait_minutes'] as num?)?.toInt(),
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
        cabinetId: json['cabinet_id'] as String,
        patientId: json['patient_id'] as String,
        patientName: json['patient_name'] as String,
        motif: json['motif'] as String,
        requestedAt: json['requested_at'] as String,
        position: (json['position'] as num).toInt(),
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
