import 'package:nubia_domain/src/entities/today_lab_work_order.dart';

class TodayLabWorkOrderDto {
  final String id;
  final String patientId;
  final String patientDisplayName;
  final String appointmentId;
  final String appointmentStartsAt;
  final String? toothFdi;
  final String? workNature;
  final String labName;
  final String status;
  final String? shippedAt;
  final String? receivedAt;

  const TodayLabWorkOrderDto({
    required this.id,
    required this.patientId,
    required this.patientDisplayName,
    required this.appointmentId,
    required this.appointmentStartsAt,
    this.toothFdi,
    this.workNature,
    required this.labName,
    required this.status,
    this.shippedAt,
    this.receivedAt,
  });

  factory TodayLabWorkOrderDto.fromJson(Map<String, dynamic> json) =>
      TodayLabWorkOrderDto(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        patientDisplayName: json['patient_display_name'] as String,
        appointmentId: json['appointment_id'] as String,
        appointmentStartsAt: json['appointment_starts_at'] as String,
        toothFdi: json['tooth_fdi'] as String?,
        workNature: json['work_nature'] as String?,
        labName: json['lab_name'] as String,
        status: json['status'] as String,
        shippedAt: json['shipped_at'] as String?,
        receivedAt: json['received_at'] as String?,
      );

  TodayLabWorkOrder toDomain() => TodayLabWorkOrder(
        id: id,
        patientId: patientId,
        patientDisplayName: patientDisplayName,
        appointmentId: appointmentId,
        appointmentStartsAt: appointmentStartsAt,
        toothFdi: toothFdi,
        workNature: workNature,
        labName: labName,
        status: status,
        shippedAt: shippedAt,
        receivedAt: receivedAt,
      );
}
